# OpenClaw AI assistant — runs 24/7 in a Kata Containers micro-VM
# Isolation: each container gets its own kernel (hardware virtualization via KVM)
# Network policy: internet YES, LAN/host/Tailscale NO
#
# Prerequisites:
#   1. (Optional) Configure /var/lib/openclaw/.env with OpenClaw settings
#   2. Switch: the container starts automatically via systemd
#
# Management:
#   update-openclaw                    — clone/pull repo, build image and restart service
#   systemctl status openclaw          — check status
#   journalctl -u openclaw -f          — follow logs
#   systemctl restart openclaw         — restart
#
# WhatsApp pairing:
#   docker exec -it openclaw openclaw channels login --channel whatsapp
#
# Dashboard Access (from any Tailscale device):
#   https://homelab.<tailnet>.ts.net
{
  pkgs,
  vars,
  lib,
  config,
  hasPrivate ? false,
  private ? null,
  ...
}:
let
  bridgeName = "br-openclaw";
  networkName = "openclaw-isolated";
  subnet = "172.30.0.0/24";
  dataDir = "/var/lib/openclaw";

  # Seed config for first boot — OpenClaw can modify this file freely after creation
  openclawConfigSeed = pkgs.writeText "openclaw-seed.json" (
    builtins.toJSON {
      agents.defaults.model.primary = "minimax/MiniMax-M2.7";
      models = {
        mode = "merge";
        providers.minimax = {
          baseUrl = "https://api.minimax.io/anthropic";
          api = "anthropic-messages";
          models = [
            {
              id = "MiniMax-M2.7";
              name = "MiniMax M2.7";
              reasoning = true;
              input = [
                "text"
                "image"
              ];
              cost = {
                input = 0.3;
                output = 1.2;
                cacheRead = 0.06;
                cacheWrite = 0.375;
              };
              contextWindow = 204800;
              maxTokens = 131072;
            }
          ];
        };
      };
    }
  );
in
{
  # ── Utility Script: Automate OpenClaw updates ──
  environment.systemPackages = [
    pkgs.git
    pkgs.socat
    (pkgs.writeShellScriptBin "update-openclaw" ''
      # Define a persistent path for the repository, keeping it near the data directory
      REPO_DIR="${dataDir}/source"

      echo "Syncing OpenClaw repository..."

      # Clone from the official repository if it doesn't exist, pull if it does
      if [ ! -d "$REPO_DIR" ]; then
        ${pkgs.git}/bin/git clone https://github.com/openclaw/openclaw.git "$REPO_DIR"
      else
        ${pkgs.git}/bin/git -C "$REPO_DIR" pull
      fi

      echo "Building Docker image..."

      # Build the image using the local Docker daemon
      ${config.virtualisation.docker.package}/bin/docker build -t openclaw:latest --build-arg OPENCLAW_INSTALL_BROWSER=1 "$REPO_DIR"

      echo "Restarting OpenClaw service to apply changes..."

      # Restart the Kata container to use the fresh image
      systemctl restart openclaw.service

      echo "Update complete!"
    '')
  ];

  # ── SOPS: secrets for Tailscale Serve and MiniMax API ──
  sops = lib.mkIf hasPrivate {
    secrets.tailnet_suffix = { };
    secrets.openclaw_minimax_key = { };
    templates."openclaw-env" = {
      content = ''
        ANTHROPIC_BASE_URL=https://api.minimax.io/anthropic
        ANTHROPIC_API_KEY=${config.sops.placeholder.openclaw_minimax_key}
      '';
      path = "${dataDir}/.env";
      owner = "1000";
      group = "1000";
      mode = "0640";
    };
  };

  # ── Kata Containers: Hardware-level isolation ──
  # Each container runs in its own micro-VM with a dedicated kernel.
  # Even a kernel exploit inside the container cannot reach the host.
  boot.kernelModules = [
    "kvm-intel"
    "kvm-amd"
  ];

  # Kata 3.x uses containerd shims, not the OCI runtime binary.
  # Docker spawns containerd which discovers shims by name in PATH.
  virtualisation.docker.daemon.settings = {
    runtimes = {
      kata = {
        runtimeType = "io.containerd.kata.v2";
      };
    };
  };

  # Put containerd-shim-kata-v2 in Docker/containerd's PATH
  systemd.services.docker.path = [ pkgs.kata-runtime ];

  # Persistent data directory (credentials, config, WhatsApp session)
  # Assuming the container runs as user 'node' (UID 1000).
  # This prevents permission denied errors inside the container.
  # When hasPrivate, SOPS template manages .env with the MiniMax API key;
  # otherwise create an empty .env so --env-file doesn't fail.
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 1000 1000 -"
  ]
  ++ lib.optional (!hasPrivate) "f ${dataDir}/.env 0640 1000 1000 -";

  # Create isolated Docker network on boot (IPv4 only, IPv6 disabled)
  systemd.services.docker-network-openclaw = {
    description = "Create isolated Docker network for OpenClaw";
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    path = [
      config.virtualisation.docker.package
      pkgs.procps
    ];
    script = ''
      docker network inspect ${networkName} >/dev/null 2>&1 || \
      docker network create ${networkName} \
        --subnet ${subnet} \
        --opt com.docker.network.bridge.name=${bridgeName}

      # Disable IPv6 on the bridge to prevent firewall bypass
      sysctl -w net.ipv6.conf.${bridgeName}.disable_ipv6=1
    '';
  };

  # ── Firewall: Isolate container from LAN, host, and Tailscale ──
  networking.firewall.extraCommands = ''
    # === IPv4 ===
    # Use DOCKER-USER chain to ensure rules are not bypassed by Docker networking
    iptables -I DOCKER-USER -i ${bridgeName} -d 10.0.0.0/8 -j DROP
    iptables -I DOCKER-USER -i ${bridgeName} -d 172.16.0.0/12 -j DROP
    iptables -I DOCKER-USER -i ${bridgeName} -d 192.168.0.0/16 -j DROP
    iptables -I DOCKER-USER -i ${bridgeName} -d 169.254.0.0/16 -j DROP
    iptables -I DOCKER-USER -i ${bridgeName} -d 100.64.0.0/10 -j DROP

    # Block abusive outbound ports (SMTP spam, BitTorrent)
    iptables -I DOCKER-USER -i ${bridgeName} -p tcp --dport 25 -j DROP
    iptables -I DOCKER-USER -i ${bridgeName} -p tcp --dport 465 -j DROP
    iptables -I DOCKER-USER -i ${bridgeName} -p tcp --dport 587 -j DROP
    iptables -I DOCKER-USER -i ${bridgeName} -p tcp --dport 6881:6889 -j DROP
    iptables -I DOCKER-USER -i ${bridgeName} -p udp --dport 6881:6889 -j DROP

    # INPUT: allow return traffic for host-initiated connections (docker-proxy port forwarding),
    # but block new connections from the container to the host.
    # Order: -I inserts at position 1, so the DROP is inserted first, then ACCEPT goes above it.
    iptables -I INPUT -i ${bridgeName} -j DROP
    iptables -I INPUT -i ${bridgeName} -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    # === IPv6: block everything (defense in depth) ===
    ip6tables -I DOCKER-USER -i ${bridgeName} -j DROP 2>/dev/null || true
    ip6tables -I INPUT -i ${bridgeName} -j DROP 2>/dev/null || true
  '';

  networking.firewall.extraStopCommands = ''
    iptables -D DOCKER-USER -i ${bridgeName} -p tcp --dport 25 -j DROP 2>/dev/null || true
    iptables -D DOCKER-USER -i ${bridgeName} -p tcp --dport 465 -j DROP 2>/dev/null || true
    iptables -D DOCKER-USER -i ${bridgeName} -p tcp --dport 587 -j DROP 2>/dev/null || true
    iptables -D DOCKER-USER -i ${bridgeName} -p tcp --dport 6881:6889 -j DROP 2>/dev/null || true
    iptables -D DOCKER-USER -i ${bridgeName} -p udp --dport 6881:6889 -j DROP 2>/dev/null || true
    iptables -D DOCKER-USER -i ${bridgeName} -d 10.0.0.0/8 -j DROP 2>/dev/null || true
    iptables -D DOCKER-USER -i ${bridgeName} -d 172.16.0.0/12 -j DROP 2>/dev/null || true
    iptables -D DOCKER-USER -i ${bridgeName} -d 192.168.0.0/16 -j DROP 2>/dev/null || true
    iptables -D DOCKER-USER -i ${bridgeName} -d 169.254.0.0/16 -j DROP 2>/dev/null || true
    iptables -D DOCKER-USER -i ${bridgeName} -d 100.64.0.0/10 -j DROP 2>/dev/null || true
    iptables -D INPUT -i ${bridgeName} -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -i ${bridgeName} -j DROP 2>/dev/null || true
    ip6tables -D DOCKER-USER -i ${bridgeName} -j DROP 2>/dev/null || true
    ip6tables -D INPUT -i ${bridgeName} -j DROP 2>/dev/null || true
  '';

  # ── Container service: Auto-start OpenClaw with kata isolation ──
  systemd.services.openclaw = {
    description = "OpenClaw AI Assistant (Kata Container)";
    after = [
      "docker.service"
      "docker-network-openclaw.service"
    ];
    requires = [
      "docker.service"
      "docker-network-openclaw.service"
    ];
    wantedBy = [ "multi-user.target" ];

    unitConfig = {
      StartLimitIntervalSec = "5min";
      StartLimitBurst = 5;
    };

    serviceConfig = {
      Type = "simple";
      Restart = "on-failure";
      RestartSec = "30s";
      TimeoutStopSec = "30s";
    };

    path = [
      config.virtualisation.docker.package
      pkgs.jq
    ];

    preStart = ''
      # Abort if kata runtime is missing — never run without hardware isolation
      if ! docker info --format '{{json .Runtimes}}' | jq -e '.kata' >/dev/null 2>&1; then
        echo "FATAL: kata runtime not registered — refusing to start without hardware isolation"
        exit 1
      fi

      # Ensure MiniMax M2.7 provider config is always present.
      # OpenClaw may overwrite openclaw.json at runtime (e.g. "openclaw setup"),
      # stripping our model config. This merges the seed fields on every start
      # without clobbering keys that OpenClaw has added.
      if [ ! -f "${dataDir}/openclaw.json" ]; then
        cp ${openclawConfigSeed} "${dataDir}/openclaw.json"
        chmod 0640 "${dataDir}/openclaw.json"
        chown 1000:1000 "${dataDir}/openclaw.json"
        echo "Seeded openclaw.json with MiniMax M2.7 provider"
      else
        SEED=${openclawConfigSeed}
        jq -s '.[0] * .[1]' "${dataDir}/openclaw.json" "$SEED" \
          > "${dataDir}/openclaw.json.tmp"
        mv "${dataDir}/openclaw.json.tmp" "${dataDir}/openclaw.json"
        chown 1000:1000 "${dataDir}/openclaw.json"
        echo "Merged MiniMax M2.7 provider into existing openclaw.json"
      fi

      ${lib.optionalString hasPrivate ''
        # Ensure Tailscale Serve origin is allowed in the Control UI
        TAILNET_SUFFIX=$(cat ${config.sops.secrets.tailnet_suffix.path})
        ORIGIN="https://homelab.''${TAILNET_SUFFIX}"
        CURRENT=$(jq -r '.gateway.controlUi.allowedOrigins // [] | join(",")' "${dataDir}/openclaw.json")
        if ! echo "$CURRENT" | grep -qF "$ORIGIN"; then
          jq --arg origin "$ORIGIN" '.gateway.controlUi.allowedOrigins = ((.gateway.controlUi.allowedOrigins // []) + [$origin] | unique)' \
            "${dataDir}/openclaw.json" > "${dataDir}/openclaw.json.tmp"
          mv "${dataDir}/openclaw.json.tmp" "${dataDir}/openclaw.json"
          chown 1000:1000 "${dataDir}/openclaw.json"
          echo "Added $ORIGIN to allowedOrigins"
        fi
      ''}

      # Clean up stale container from previous crash
      docker rm -f openclaw 2>/dev/null || true
    '';

    script = ''
      # The exec replaces the shell with docker run, letting systemd track the container lifecycle directly
      exec docker run --rm --name openclaw \
        --runtime=kata \
        --network ${networkName} \
        --log-driver journald \
        --cap-drop ALL \
        --security-opt no-new-privileges \
        --read-only \
        --tmpfs /tmp \
        --tmpfs /home/node/.openclaw/logs \
        --memory 4g \
        --cpus 2 \
        --pids-limit 512 \
        --dns 1.1.1.1 --dns 9.9.9.9 \
        -v ${dataDir}:/home/node/.openclaw \
        --env-file ${dataDir}/.env \
        openclaw:latest
    '';
  };

  # ── Port forwarding: bridge host port to Kata container via docker exec ──
  # Docker's port publishing (-p) does not work reliably with Kata containers
  # because the micro-VM has its own kernel and network stack. Instead, socat
  # on the host forwards TCP connections through "docker exec" into the container.
  systemd.services.openclaw-proxy = {
    description = "OpenClaw dashboard proxy (socat → docker exec)";
    after = [ "openclaw.service" ];
    requires = [ "openclaw.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Restart = "on-failure";
      RestartSec = "5s";
    };

    path = [
      pkgs.socat
      config.virtualisation.docker.package
    ];

    script = ''
      # socat accepts each TCP connection and pipes it through "docker exec"
      # into a Node.js one-liner that relays bytes to the app's localhost socket.
      # This is the only reliable path into a Kata micro-VM because the VM has
      # its own kernel and network stack — the container IP on the bridge (eth0)
      # is unreachable from the host, but "docker exec" uses the containerd shim.
      exec socat TCP-LISTEN:18789,bind=127.0.0.1,reuseaddr,fork,max-children=5 \
        EXEC:"docker exec -i openclaw node -e \"require('net').createConnection(18789,'127.0.0.1',function(){this.pipe(process.stdout);process.stdin.pipe(this)})\""
    '';
  };

  # ── Tailscale Serve: expose dashboard with HTTPS on tailnet ──
  # Provides a secure context (https://homelab.<tailnet>.ts.net) required
  # by the OpenClaw Control UI for device identity / OAuth login.
  services.tailscale.serve = {
    enable = true;
    services.openclaw.endpoints."tcp:443" = "http://localhost:18789";
  };
}
