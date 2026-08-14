# Hermes Agent - the homelab's 24/7 messaging gateway.
#
# Upstream ships its own NixOS module (`services.hermes-agent`), so this file
# only covers the four things upstream leaves out:
#
#   1. Profiles. Upstream models one profile per module instance, but profile
#      routing serves several personas from a single gateway process, and
#      `hermes profile create` is interactive. The profile trees are therefore
#      seeded declaratively here.
#   2. Egress policy. The agent reads untrusted input (chat, web fetches), so it
#      may reach the internet but never the LAN, the host or the tailnet. This
#      replaces the DOCKER-USER rules of the previous container deployment.
#   3. Its own resolver. NetworkManager points /etc/resolv.conf at the LAN
#      router, which rule 2 rejects, so the unit gets public resolvers instead.
#   4. systemd hardening past upstream's baseline.
#
# Persona content, channel credentials and routes live in the private repo.
#
# Management:
#   systemctl status hermes-agent      - check status
#   journalctl -u hermes-agent -f      - follow logs
#   sudo -u hermes hermes doctor       - diagnose configuration
#
# Config is Nix-owned: the unit sets HERMES_MANAGED=true, so `hermes config set`
# and `hermes update` refuse to run and point at `nixos-rebuild` instead.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.services.hermes-agent;
  inherit (config.nalyx.hermes) profiles;

  hermesHome = "${cfg.stateDir}/.hermes";

  # hermes_cli/profiles.py:_PROFILE_DIRS - a profile is a full parallel
  # HERMES_HOME, so every one of these has to exist before the gateway routes a
  # message into it.
  profileDirs = [
    "memories"
    "sessions"
    "skills"
    "skins"
    "logs"
    "plans"
    "workspace"
    "cron"
    "home"
  ];

  # Everything the agent must never reach: RFC1918, link-local, and the CGNAT
  # range Tailscale allocates from.
  blockedV4 = [
    "10.0.0.0/8"
    "172.16.0.0/12"
    "192.168.0.0/16"
    "169.254.0.0/16"
    "100.64.0.0/10"
  ];
  blockedV6 = [
    "fc00::/7"
    "fe80::/10"
  ];

  resolvConf = pkgs.writeText "hermes-resolv.conf" ''
    nameserver 1.1.1.1
    nameserver 9.9.9.9
  '';

  # Files Nix owns inside a profile. Rewritten on every activation: Nix is the
  # source of truth for identity and model choice, the agent owns everything
  # else under the profile (memories it curates, skills it writes, sessions).
  seedFiles =
    profile:
    lib.optionalAttrs (profile.soul != null) { "SOUL.md" = profile.soul; }
    // lib.optionalAttrs (profile.settings != { }) {
      # YAML is a superset of JSON, and hermes reads config.yaml with
      # yaml.safe_load - same trick upstream's own module uses.
      "config.yaml" = builtins.toJSON profile.settings;
    }
    // profile.documents;

  seedProfile =
    name: profile:
    let
      dir = "${hermesHome}/profiles/${name}";
      mkDir = sub: "install -d -o ${cfg.user} -g ${cfg.group} -m 2770 ${dir}/${sub}\n";
      mkFile =
        rel: content:
        let
          label = lib.replaceStrings [ "/" ] [ "-" ] rel;
          file = pkgs.writeText "hermes-profile-${name}-${label}" content;
        in
        "install -o ${cfg.user} -g ${cfg.group} -m 0640 ${file} ${dir}/${rel}\n";
    in
    lib.concatStrings (
      [ (mkDir "") ] ++ map mkDir profileDirs ++ lib.mapAttrsToList mkFile (seedFiles profile)
    );

  rejectRules =
    binary: reject: nets:
    lib.concatMapStrings (
      net:
      "${binary} -A OUTPUT -m owner --uid-owner ${cfg.user} -d ${net} -j REJECT --reject-with ${reject}\n"
    ) nets;

  deleteRules =
    binary: reject: nets:
    lib.concatMapStrings (
      net:
      "${binary} -D OUTPUT -m owner --uid-owner ${cfg.user} -d ${net} -j REJECT --reject-with ${reject} 2>/dev/null || true\n"
    ) nets;
in
{
  imports = [ inputs.hermes-agent.nixosModules.default ];

  options.nalyx.hermes.profiles = lib.mkOption {
    default = { };
    description = ''
      Extra Hermes profiles to seed under `$HERMES_HOME/profiles/<name>`.

      A profile is an isolated persona: its own system prompt, workspace,
      model, skills, memories and sessions, all served by the single gateway
      process. Bind one to a channel with `gateway.profile_routes`; messages
      that match no route are handled by the root profile instead.
    '';
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          soul = lib.mkOption {
            type = lib.types.nullOr lib.types.lines;
            default = null;
            description = "SOUL.md contents - the persona, injected as the identity slot of the system prompt.";
          };

          settings = lib.mkOption {
            type = lib.types.attrs;
            default = { };
            description = "The profile's own config.yaml, for per-persona overrides such as `model`.";
          };

          documents = lib.mkOption {
            type = lib.types.attrsOf lib.types.lines;
            default = { };
            example = lib.literalExpression ''{ "workspace/AGENTS.md" = "# Project context"; }'';
            description = "Extra files to write, keyed by path relative to the profile root.";
          };
        };
      }
    );
  };

  config = lib.mkIf cfg.enable {
    # Non-secret defaults. The private module supplies credentials, routes and
    # personas on top.
    services.hermes-agent = {
      # Tools the agent actually needs on a headless box. The gateway's PATH
      # already carries bash, coreutils and git from upstream.
      extraPackages = with pkgs; [
        gh
        jq
        ripgrep
        openssh
        ffmpeg
      ];

      settings = {
        # The security boundary is this systemd unit, not a nested sandbox.
        # `docker` here would need /var/run/docker.sock, which is root on the
        # host, and it would still leave MCP servers, plugins, hooks and skills
        # running outside it.
        terminal.backend = "local";

        # Voice notes transcribed locally with faster-whisper (already in the
        # default Nix package, together with ffmpeg above). No cloud STT key.
        stt = {
          enabled = true;
          provider = "local";
          local.model = "base";
        };

        # `smart` pre-screens destructive shell commands instead of running
        # everything unattended. cron_mode defaults to `deny`, which would hang
        # scheduled jobs on an approval nobody sees.
        approvals = {
          mode = "smart";
          cron_mode = "approve";
        };

        # Required for `gateway.profile_routes` to be read at all.
        gateway.multiplex_profiles = true;
      };
    };

    system.activationScripts."hermes-agent-profiles" = lib.stringAfter [ "hermes-agent-setup" ] (
      lib.concatStrings (lib.mapAttrsToList seedProfile profiles)
    );

    # Egress policy, matched on the service account rather than an interface, so
    # nothing else on the host is affected.
    networking.firewall = {
      extraCommands = ''
        ${rejectRules "iptables" "icmp-net-prohibited" blockedV4}
        ${rejectRules "ip6tables" "icmp6-adm-prohibited" blockedV6}
      '';
      extraStopCommands = ''
        ${deleteRules "iptables" "icmp-net-prohibited" blockedV4}
        ${deleteRules "ip6tables" "icmp6-adm-prohibited" blockedV6}
      '';
    };

    systemd.services.hermes-agent.serviceConfig = {
      # Upstream leaves this off so the local terminal backend can see a real
      # user's ~/.ssh and ~/.gitconfig. This is a dedicated service account on
      # a headless box and has no business reading /home.
      ProtectHome = lib.mkForce true;

      BindReadOnlyPaths = [ "${resolvConf}:/etc/resolv.conf" ];

      CapabilityBoundingSet = "";
      AmbientCapabilities = "";
      LockPersonality = true;
      PrivateDevices = true;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectProc = "invisible";
      RestrictAddressFamilies = [
        "AF_INET"
        "AF_INET6"
        "AF_UNIX"
      ];
      # Blocks unshare(). Browser automation would need this relaxed, but
      # Chromium is not part of the Nix package anyway.
      RestrictNamespaces = true;
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      SystemCallArchitectures = "native";
      SystemCallFilter = [
        "@system-service"
        "~@privileged"
      ];

      # Bound a runaway agent loop on a small box. Matches the memory ceiling
      # the previous deployment gave the container.
      MemoryMax = "8G";
      TasksMax = 1024;
    };
  };
}
