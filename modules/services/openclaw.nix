# OpenClaw AI assistant — runs 24/7 in a Kata Containers micro-VM
# Isolation: each container gets its own kernel (hardware virtualization via KVM)
# Network policy: internet YES, LAN/host/Tailscale NO
#
# Prerequisites:
#   1. Build the image (from cloned openclaw repo):
#      docker build -t openclaw:latest --build-arg OPENCLAW_INSTALL_BROWSER=1 .
#   2. (Optional) Configure /var/lib/openclaw/.env with OpenClaw settings
#   3. Switch: the container starts automatically via systemd
#
# Management:
#   systemctl status openclaw          — check status
#   journalctl -u openclaw -f          — follow logs
#   systemctl restart openclaw         — restart
#
# WhatsApp pairing:
#   docker exec -it openclaw openclaw channels login --channel whatsapp
{
  pkgs,
  vars,
  config,
  ...
}:
let
  bridgeName = "br-openclaw";
  networkName = "openclaw-isolated";
  subnet = "172.30.0.0/24";
  dataDir = "/var/lib/openclaw";
in
{
  # ── Kata Containers: hardware-level isolation ──
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
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 ${vars.user.name} docker -"
  ];

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

  # ── Firewall: isolate container from LAN, host, and Tailscale ──
  #
  # IPv4 FORWARD chain (container → external):
  #   DROP → all RFC 1918 ranges (LAN)
  #   DROP → 100.64.0.0/10 (Tailscale CGNAT)
  #   DROP → 169.254.0.0/16 (link-local)
  #   ALLOW → everything else (internet via Docker NAT)
  #
  # IPv4 INPUT chain (container → host):
  #   DROP → everything (no host access at all)
  #
  # IPv6: DROP everything (defense in depth, IPv6 also disabled on bridge)
  #
  # DNS: container uses external resolvers (1.1.1.1, 9.9.9.9) via --dns flag,
  #       so no host DNS access is needed
  networking.firewall.extraCommands = ''
    # === IPv4 ===
    # FORWARD: block container → private/reserved networks
    iptables -I FORWARD -i ${bridgeName} -d 10.0.0.0/8 -j DROP
    iptables -I FORWARD -i ${bridgeName} -d 172.16.0.0/12 -j DROP
    iptables -I FORWARD -i ${bridgeName} -d 192.168.0.0/16 -j DROP
    iptables -I FORWARD -i ${bridgeName} -d 169.254.0.0/16 -j DROP
    iptables -I FORWARD -i ${bridgeName} -d 100.64.0.0/10 -j DROP

    # INPUT: block ALL container → host traffic (no exceptions)
    iptables -I INPUT -i ${bridgeName} -j DROP

    # === IPv6: block everything (defense in depth) ===
    ip6tables -I FORWARD -i ${bridgeName} -j DROP
    ip6tables -I INPUT -i ${bridgeName} -j DROP
  '';

  networking.firewall.extraStopCommands = ''
    iptables -D FORWARD -i ${bridgeName} -d 10.0.0.0/8 -j DROP 2>/dev/null || true
    iptables -D FORWARD -i ${bridgeName} -d 172.16.0.0/12 -j DROP 2>/dev/null || true
    iptables -D FORWARD -i ${bridgeName} -d 192.168.0.0/16 -j DROP 2>/dev/null || true
    iptables -D FORWARD -i ${bridgeName} -d 169.254.0.0/16 -j DROP 2>/dev/null || true
    iptables -D FORWARD -i ${bridgeName} -d 100.64.0.0/10 -j DROP 2>/dev/null || true
    iptables -D INPUT -i ${bridgeName} -j DROP 2>/dev/null || true
    ip6tables -D FORWARD -i ${bridgeName} -j DROP 2>/dev/null || true
    ip6tables -D INPUT -i ${bridgeName} -j DROP 2>/dev/null || true
  '';

  # ── Container service: auto-start OpenClaw with kata isolation ──
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

      # Ensure .env file exists (empty is fine, OpenClaw handles defaults)
      if [ ! -f ${dataDir}/.env ]; then
        install -m 0640 -o ${vars.user.name} -g docker /dev/null ${dataDir}/.env
        echo "NOTICE: Created empty ${dataDir}/.env"
      fi

      # Clean up stale container from previous crash
      docker rm -f openclaw 2>/dev/null || true
    '';

    script = ''
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

  # ── Health check: safety net if container dies without systemd noticing ──
  systemd.services.openclaw-healthcheck = {
    description = "OpenClaw Health Check";
    serviceConfig.Type = "oneshot";
    path = [ config.virtualisation.docker.package ];
    script = ''
      # Only act if the service is supposed to be running
      if ! systemctl is-active --quiet openclaw.service; then
        exit 0
      fi

      STATE=$(docker inspect openclaw --format '{{.State.Status}}' 2>/dev/null || echo "missing")
      if [ "$STATE" != "running" ]; then
        echo "OpenClaw container state: $STATE — restarting service"
        systemctl restart openclaw.service
      fi
    '';
  };

  systemd.timers.openclaw-healthcheck = {
    description = "OpenClaw Health Check Timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnActiveSec = "2min";
      OnUnitActiveSec = "5min";
    };
  };
}
