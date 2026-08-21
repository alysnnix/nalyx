# Hermes Agent - the homelab's 24/7 messaging gateway, inside a micro-VM.
#
# Isolation: the agent runs in its own NixOS guest with its own kernel, booted
# through KVM. This is the same class of boundary the previous OpenClaw
# deployment got from Kata Containers, and for the same reason: the agent reads
# untrusted input and executes shell commands, and upstream is blunt about what
# that means - "The only security boundary against an adversarial LLM is the
# operating system. Nothing inside the agent process constitutes containment."
#
# Kata is not reused because it drags Docker back in: the upstream NixOS module's
# container mode hardcodes `--network=host` before its `extraOptions` escape
# hatch, and Kata 3.x needs Docker pinned to 25.x (moby/moby#47626). microvm.nix
# gives the same hardware boundary declaratively, with no container runtime and
# no root daemon on the host.
#
# Network policy: internet YES, LAN/host/tailnet NO. The guest's only path out is
# SLIRP inside the hypervisor process, so `IPAddressDeny` on that one unit is a
# boundary the guest cannot route around - it has no other interface.
#
# Management (from the host):
#   systemctl status microvm@hermes        - hypervisor process
#   journalctl -u microvm@hermes -f        - guest console and kernel log
#   microvm -s hermes                      - shell inside the guest, over vsock
#   systemctl restart microvm@hermes       - reboot the guest
#
# Config is Nix-owned: the guest unit sets HERMES_MANAGED=true, so `hermes config
# set` and `hermes update` refuse to run and point at `nixos-rebuild` instead.
{
  config,
  lib,
  pkgs,
  inputs,
  vars,
  ...
}:
let
  cfg = config.nalyx.hermes;

  # Host paths. The state directory is shared into the guest read-write and holds
  # everything the agent owns: its SQLite DB, sessions, skills and memories.
  stateDir = "/var/lib/hermes";

  # Where the agent's credentials are staged on the host for sharing. sops-nix
  # renders a template as a SYMLINK into /run/secrets/rendered, and that target
  # does not exist inside the guest, so the real bytes are copied here before
  # the VM starts (see ExecStartPre below).
  secretsDir = "/run/hermes-secrets";
  secretsFileName = "hermes.env";

  # The guest mounts the secrets share here, deliberately NOT under /run:
  # systemd mounts /run as a fresh tmpfs in stage 2, which would shadow a
  # stage-1 mount underneath it.
  guestSecretsDir = "/var/lib/hermes-secrets";

  # The guest's hermes user is pinned so the state directory on the host can be
  # owned by the matching numeric ids. virtiofs passes uid/gid through untouched,
  # so a mismatch here means the agent cannot write to its own state.
  hermesUid = 990;
  hermesGid = 990;

  # Context id for the guest's AF_VSOCK channel, which carries sshd. Needed for
  # the interactive commands that refuse to run without a TTY (`hermes claw
  # migrate`, `hermes whatsapp`), which is what `docker exec -it openclaw` used
  # to cover. 0, 1 and 2 are reserved by the vsock spec.
  vsockCid = 42;

  # Everything the agent must never reach: RFC1918, link-local and the CGNAT
  # range Tailscale allocates from. Only IPAddressDeny is set, never
  # IPAddressAllow, because Allow takes precedence over Deny in systemd and
  # `allow=any` would silently defeat the whole list.
  blockedRanges = [
    "10.0.0.0/8"
    "172.16.0.0/12"
    "192.168.0.0/16"
    "169.254.0.0/16"
    "100.64.0.0/10"
    "fc00::/7"
    "fe80::/10"
  ];

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

  # Files Nix owns inside a profile. Rewritten on every activation: Nix is the
  # source of truth for identity and model choice, the agent owns everything else
  # under the profile (the memories it curates, the skills it writes, sessions).
  seedFiles =
    profile:
    lib.optionalAttrs (profile.soul != null) { "SOUL.md" = profile.soul; }
    // lib.optionalAttrs (profile.settings != { }) {
      # YAML is a superset of JSON and hermes reads config.yaml with
      # yaml.safe_load - the same trick upstream's own module uses.
      "config.yaml" = builtins.toJSON profile.settings;
    }
    // profile.documents;

  seedProfile =
    name: profile:
    let
      dir = "${stateDir}/.hermes/profiles/${name}";
      mkDir = sub: "install -d -o hermes -g hermes -m 2770 ${dir}/${sub}\n";
      mkFile =
        rel: content:
        let
          label = lib.replaceStrings [ "/" ] [ "-" ] rel;
          file = pkgs.writeText "hermes-profile-${name}-${label}" content;
        in
        "install -o hermes -g hermes -m 0640 ${file} ${dir}/${rel}\n";
    in
    lib.concatStrings (
      [ (mkDir "") ] ++ map mkDir profileDirs ++ lib.mapAttrsToList mkFile (seedFiles profile)
    );

  # Non-secret defaults, deep-merged under whatever the private module sets, so
  # dropping one of these cannot happen by forgetting to repeat it there.
  baseSettings = {
    # Required, and silent when missing: without it `gateway.profile_routes` is
    # ignored outright and every message lands on the root profile instead of
    # its persona.
    gateway.multiplex_profiles = true;

    # The security boundary is the micro-VM, not a nested sandbox. `docker` here
    # would need /var/run/docker.sock, root on the host, and would still leave
    # MCP servers, plugins, hooks and skills running outside it.
    terminal.backend = "local";

    # Voice notes transcribed locally with faster-whisper, which is already in
    # the default Nix package together with ffmpeg. No cloud STT key.
    stt = {
      enabled = true;
      provider = "local";
      local.model = "base";
    };

    # `smart` pre-screens destructive shell commands instead of running
    # everything unattended. cron_mode defaults to `deny` upstream, which would
    # hang a scheduled job on an approval nobody is there to see.
    approvals = {
      mode = "smart";
      cron_mode = "approve";
    };
  };
in
{
  imports = [ inputs.microvm.nixosModules.host ];

  options.nalyx.hermes = {
    enable = lib.mkEnableOption "the Hermes Agent gateway, isolated in a micro-VM";

    vcpu = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4;
      description = "vCPUs given to the guest.";
    };

    mem = lib.mkOption {
      type = lib.types.ints.positive;
      default = 4096;
      description = ''
        Guest RAM in MiB. Unlike the memory limit of the previous container
        deployment this is a reservation: the host loses it for as long as the
        guest runs.
      '';
    };

    secretsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/rendered/hermes-env";
      description = ''
        Host path to a rendered dotenv file with the agent's credentials, for
        example a sops-nix template's `path`. It is copied into the one
        directory shared into the guest right before the VM starts, so it may
        be a symlink and may live anywhere on the host.
      '';
    };

    settings = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Hermes `config.yaml` for the root profile, merged by the upstream module.";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Non-secret environment variables written to the agent's `.env`.";
    };

    profiles = lib.mkOption {
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
  };

  config = lib.mkIf cfg.enable {
    # Hardware virtualisation for the guest. Carried over from the Kata setup,
    # which needed the same modules; the microvm host module loads only tap and
    # vhost_net itself.
    boot.kernelModules = [
      "kvm-intel"
      "kvm-amd"
    ];

    systemd.tmpfiles.rules = [
      # Owned by the guest's numeric hermes uid/gid, because virtiofs passes ids
      # through and the microvm host module would otherwise create this as
      # microvm:kvm, which the agent cannot write to.
      "d ${stateDir} 2770 ${toString hermesUid} ${toString hermesGid} - -"
      "d ${secretsDir} 0700 root root - -"
    ];

    microvm.vms.hermes = {
      # Fully declarative: `nixos-rebuild switch` on the host rebuilds the guest
      # closure AND restarts the guest. A `flake`-based VM would need a separate
      # `microvm -u hermes`.
      config = {
        imports = [ inputs.hermes-agent.nixosModules.default ];

        microvm = {
          # The only hypervisor that supports user-mode networking, virtiofs and
          # credential files at once.
          hypervisor = "qemu";
          inherit (cfg) vcpu mem;

          # SLIRP user networking: no tap, no bridge, no systemd-networkd. The
          # host runs NetworkManager and never sees this interface at all.
          interfaces = [
            {
              type = "user";
              id = "hermes0";
              mac = "02:00:00:00:7a:01";
            }
          ];

          # Host to guest shell without any TCP listener: sshd is reachable only
          # over the VM's AF_VSOCK channel, so the host binds no port at all.
          # Connect with `microvm -s hermes`, which resolves the cid itself.
          vsock = {
            cid = vsockCid;
            ssh.enable = true;
          };

          # QEMU's own seccomp sandbox, the same set libvirt applies. Preferred
          # over a hand-rolled systemd SystemCallFilter on a process whose
          # syscall surface cannot be boot-tested from here. nixpkgs builds qemu
          # with libseccomp, so this is not a no-op.
          qemu.extraArgs = [
            "-sandbox"
            "on,obsolete=deny,elevateprivileges=deny,spawn=deny,resourcecontrol=deny"
          ];

          # No /nix/store share on purpose. Sharing the host store is the cheap
          # option and what microvm.nix recommends, but it would let the agent
          # read every derivation on the host (73 GB measured) when its own
          # closure is 5.9 GB. Omitting the share flips storeOnDisk on, so the
          # guest boots an erofs image carrying only its own closure.
          # Measured cost of that trade: a 2.4 GB image, rebuilt whenever the
          # guest closure changes, ~55 s on a 13600K and longer on the homelab.
          shares = [
            {
              tag = "hermes-state";
              source = stateDir;
              mountPoint = stateDir;
              proto = "virtiofs";
            }
            {
              tag = "hermes-secrets";
              source = secretsDir;
              mountPoint = guestSecretsDir;
              proto = "virtiofs";
              readOnly = true;
            }
          ];
        };

        # microvm.nix only marks the store share neededForBoot (mounts.nix:128),
        # so every other share is mounted by systemd in stage 2, AFTER NixOS
        # activation has already run. Anything activation writes under a share
        # then lands on the guest's tmpfs root and is shadowed the moment the
        # share mounts. That silently swallowed config.yaml, .env and the seeded
        # profiles: the agent booted with no config and no Discord token.
        # Marking them neededForBoot moves both mounts into stage 1, and NixOS
        # pulls virtiofs into the initrd from these fsTypes on its own
        # (nixos/modules/system/boot/stage-1.nix: boot.initrd.supportedFilesystems).
        fileSystems = {
          ${stateDir}.neededForBoot = true;
          ${guestSecretsDir}.neededForBoot = true;
        };

        networking = {
          hostName = "hermes";

          # SLIRP hands out 10.0.2.15 over its built-in DHCP, but its DNS
          # forwarder at 10.0.2.3 resolves through the host, whose resolver is on
          # the LAN and therefore blocked. Resolve publicly instead, and stop
          # dhcpcd from putting the SLIRP forwarder back into resolv.conf.
          nameservers = [
            "1.1.1.1"
            "9.9.9.9"
          ];
          dhcpcd.extraConfig = "nohook resolv.conf";

          # Nothing inbound over IP: sshd is reached over vsock, and the guest
          # serves nothing else.
          firewall.allowedTCPPorts = [ ];
        };

        # Same key source as the host, so the guest is reachable with the keys
        # Aly already carries.
        services.openssh = {
          enable = true;
          # Reached over vsock, so it needs no IP port. Left at its default this
          # would add 22 back to allowedTCPPorts by itself.
          openFirewall = false;
          settings = {
            PermitRootLogin = "prohibit-password";
            PasswordAuthentication = false;
          };
        };
        users = {
          users.root.openssh.authorizedKeys.keyFiles =
            config.users.users.${vars.user.name}.openssh.authorizedKeys.keyFiles;

          # Pinned so the shared state directory's ownership on the host matches.
          users.hermes.uid = hermesUid;
          groups.hermes.gid = hermesGid;
        };

        services.hermes-agent = {
          enable = true;
          inherit (cfg) environment;
          settings = lib.recursiveUpdate baseSettings cfg.settings;
          environmentFiles = lib.optional (cfg.secretsFile != null) "${guestSecretsDir}/${secretsFileName}";

          # Tools the agent needs on a headless box. The gateway's PATH already
          # carries bash, coreutils and git from upstream.
          extraPackages = with pkgs; [
            gh
            jq
            ripgrep
            openssh
            ffmpeg
          ];
        };

        # Defence in depth. The micro-VM is the boundary; this bounds what a
        # compromised agent can do to its own guest before it gets there.
        systemd.services.hermes-agent.serviceConfig = {
          # Upstream leaves this off so the local terminal backend can see a real
          # user's ~/.ssh and ~/.gitconfig. Nothing else lives in this guest.
          ProtectHome = lib.mkForce true;

          CapabilityBoundingSet = "";
          AmbientCapabilities = "";
          LockPersonality = true;
          PrivateDevices = true;
          ProtectClock = true;
          ProtectControlGroups = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectProc = "invisible";
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
            "AF_UNIX"
            # getaddrinfo asks the kernel for interface state over netlink, so
            # denying it breaks DNS for the Discord websocket.
            "AF_NETLINK"
          ];
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          SystemCallArchitectures = "native";
          # `@system-service` and nothing tighter. Adding `~@privileged` also
          # denies `@chown`, and the agent chowns files under its own state dir
          # on startup: seccomp answered with SIGSYS and the gateway core-dumped
          # in a restart loop (audit type=1326, syscall=92). The real bound on
          # chown here is CapabilityBoundingSet being empty, not the filter.
          SystemCallFilter = [ "@system-service" ];
        };

        system.activationScripts."hermes-agent-profiles" = lib.stringAfter [ "hermes-agent-setup" ] (
          lib.concatStrings (lib.mapAttrsToList seedProfile cfg.profiles)
        );

        system.stateVersion = config.system.stateVersion;
      };
    };

    # microvm.nix defines this instance with overrideStrategy = "asDropin", so
    # these merge into the template unit rather than replacing its ExecStart.
    systemd.services."microvm@hermes" = {
      after = lib.optional (cfg.secretsFile != null) "sops-install-secrets.service";

      serviceConfig = {
        # The guest's only route to the network is SLIRP inside this process, so
        # filtering its sockets filters the guest, and the guest has no second
        # interface to route around it.
        IPAddressDeny = blockedRanges;

        # Refuse to start without hardware isolation, the same guard the OpenClaw
        # unit had for the kata runtime. qemu is only handed `-enable-kvm` while
        # `microvm.cpu` is null; the machine's own `accel=kvm:tcg` would
        # otherwise let it fall back to software emulation, which is no boundary
        # at all. Runs as the unit's own user, so it checks the kvm group too.
        ExecStartPre = [
          "${pkgs.coreutils}/bin/test -w /dev/kvm"
        ]
        ++ lib.optional (cfg.secretsFile != null) (
          # sops-nix renders a template's `path` as a symlink into
          # /run/secrets/rendered, which does not exist inside the guest, so
          # sharing the symlink hands the guest a dangling one and upstream's
          # `[ -f ]` guard silently skips it, leaving the agent with no token.
          # Copy the real bytes in. `+` runs it as root even though the unit
          # itself is User=microvm.
          "+${pkgs.writeShellScript "hermes-stage-secret" ''
            set -eu
            ${pkgs.coreutils}/bin/install -m 0400 -o root -g root \
              ${lib.escapeShellArg cfg.secretsFile} \
              ${lib.escapeShellArg "${secretsDir}/${secretsFileName}"}
          ''}"
        );

        # SLIRP means the guest's packets are parsed by libslirp inside THIS
        # process rather than by the host kernel, so the process itself is part
        # of the attack surface. It already runs unprivileged as microvm:kvm
        # (which is more than Kata gave: its own config ships "By default QEMU
        # VMM run as root"). Shrink what a VMM escape would reach.
        NoNewPrivileges = true;
        CapabilityBoundingSet = "";
        AmbientCapabilities = "";
        ProtectSystem = "strict";
        ReadWritePaths = [ "/var/lib/microvms/hermes" ];
        ProtectHome = true;
        PrivateTmp = true;
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        RestrictNamespaces = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        LockPersonality = true;
        SystemCallArchitectures = "native";
        # AF_VSOCK carries the guest's sshd; AF_INET/AF_INET6 are SLIRP's
        # outbound sockets; AF_UNIX reaches virtiofsd and the QMP socket.
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
          "AF_VSOCK"
        ];
      };
    };
  };
}
