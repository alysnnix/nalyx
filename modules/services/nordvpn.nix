{
  config,
  lib,
  pkgs,
  vars,
  ...
}:
let
  nordVpnPkg = pkgs.callPackage (
    {
      autoPatchelfHook,
      buildFHSEnv,
      dpkg,
      fetchurl,
      lib,
      stdenv,
      iptables,
      iproute2,
      procps,
      cacert,
      libnl, # Needed for 3.9.x +
      libcap_ng, # Needed for 3.9.x +
      sqlite, # Needed for 4.1.x +
      libxml2,
      libidn2,
      zlib,
      wireguard-tools,
    }:
    let
      pname = "nordvpn";
      version = "4.3.1";

      nordVPNBase = stdenv.mkDerivation {
        inherit pname version;

        src = fetchurl {
          url = "https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/nordvpn_${version}_amd64.deb";
          hash = "sha256-oFf4uxZsucAh2yW++SQRxFx8+JdL8ZsNzWqzjJ2JqUs=";
        };

        buildInputs = [
          libxml2
          libidn2
          libnl
          sqlite
          libcap_ng
          zlib
        ];
        nativeBuildInputs = [
          dpkg
          autoPatchelfHook
          stdenv.cc.cc.lib
        ];

        dontConfigure = true;
        dontBuild = true;

        unpackPhase = ''
          runHook preUnpack
          dpkg --extract $src .
          runHook postUnpack
        '';

        installPhase = ''
          runHook preInstall
          mkdir -p $out
          mv usr/* $out/
          mv var/ $out/
          mv etc/ $out/
          runHook postInstall
        '';
      };

      nordVPNfhs = buildFHSEnv {
        name = "nordvpnd";
        runScript = "nordvpnd";

        # hardcoded path to /sbin/ip
        targetPkgs = _: [
          sqlite # Needed for 4.1.x +
          nordVPNBase
          iptables
          iproute2
          procps
          cacert
          libnl # Needed for 3.9.x +
          libcap_ng # Needed for 3.9.x +
          libxml2
          libidn2
          zlib
          wireguard-tools
        ];
      };
    in
    stdenv.mkDerivation {
      inherit pname version;

      dontUnpack = true;
      dontConfigure = true;
      dontBuild = true;

      installPhase = ''
        runHook preInstall
        mkdir -p $out/bin $out/share
        ln -s ${nordVPNBase}/bin/nordvpn $out/bin
        ln -s ${nordVPNfhs}/bin/nordvpnd $out/bin
        ln -s ${nordVPNBase}/share/* $out/share/
        ln -s ${nordVPNBase}/var $out/
        runHook postInstall
      '';

      meta = with lib; {
        description = "CLI client for NordVPN";
        homepage = "https://www.nordvpn.com";
        license = licenses.unfreeRedistributable;
        maintainers = with maintainers; [ dr460nf1r3 ];
        platforms = [ "x86_64-linux" ];
      };
    }
  ) { };
in
with lib;
{
  options.modules.services.nordvpn.enable = mkOption {
    type = types.bool;
    default = false;
    description = ''
      Whether to enable the NordVPN daemon.

      WARNING: enabling this option automatically sets
      `networking.firewall.checkReversePath = "loose"`, which relaxes
      reverse-path filtering. Required by NordVPN — accepted trade-off.

      The nordvpnd binary runs as root inside an FHS env with access
      to iptables, wireguard-tools and procps. NordVPN is proprietary
      closed-source software — audit is not possible.

      Firewall change applied automatically:
        - checkReversePath set to "loose" (required, accepted trade-off)

      NOTE: if Tailscale is also enabled, routing conflicts may occur
      since both manage iptables rules and routing tables simultaneously.

      Your user (${vars.user.name}) is added to the "nordvpn" group automatically.
    '';
  };

  config = mkIf config.modules.services.nordvpn.enable {
    # "loose" satisfies NordVPN's routing requirements while retaining
    # partial protection against IP spoofing (stricter than false).
    # NOTE: ports 1194/443 are outgoing connections (allowed by default),
    # no inbound firewall rules needed for a VPN client.
    networking.firewall.checkReversePath = "loose";

    environment.systemPackages = [ nordVpnPkg ];

    users.groups.nordvpn.members = [ vars.user.name ];

    systemd.services.nordvpn = {
      description = "NordVPN daemon.";
      serviceConfig = {
        ExecStart = "${nordVpnPkg}/bin/nordvpnd";
        ExecStartPre = pkgs.writeShellScript "nordvpn-start" ''
          if [ -z "$(ls -A /var/lib/nordvpn)" ]; then
            cp -r ${nordVpnPkg}/var/lib/nordvpn/* /var/lib/nordvpn
            chown -R root:nordvpn /var/lib/nordvpn
          fi
        '';
        NonBlocking = true;
        KillMode = "control-group";
        Restart = "on-failure";
        RestartSec = 5;
        StateDirectory = "nordvpn";
        StateDirectoryMode = "0750";
        RuntimeDirectory = "nordvpn";
        RuntimeDirectoryMode = "0750";
        Group = "nordvpn";

        # Systemd hardening (compatible with VPN daemon requirements)
        PrivateTmp = true;
        ProtectHome = true;
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = false; # WireGuard kernel module must be loadable at runtime
        RestrictSUIDSGID = true;
        LockPersonality = true;
        RestrictRealtime = true;
      };
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
    };
  };
}
