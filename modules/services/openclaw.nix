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
# Dashboard Access (from personal computer via Tailscale):
#   ssh -N -L 18789:127.0.0.1:18789 USER@homelab
#   Then open http://127.0.0.1:18789
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
  systemd.tmpfiles.rules = [
    "d ${dataDir} 0750 1000 1000 -"
    "f ${dataDir}/.env 0640 1000 1000 -"
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

  # ── Firewall: Isolate container from LAN, host, and Tailscale ──
  networking.firewall.extraCommands = ''
    # === IPv4 ===
    # Use DOCKER-USER chain to ensure rules are not bypassed by Docker networking
    iptables -I DOCKER-USER -i ${bridgeName} -d 10.0.0.0/8 -j DROP
    iptables -I DOCKER-USER -i ${bridgeName} -d 172.16.0.0/12 -j DROP
    iptables -I DOCKER-USER -i ${bridgeName} -d 192.168.0.0/16 -j DROP
    iptables -I DOCKER-USER -i ${bridgeName} -d 169.254.0.0/16 -j DROP
    iptables -I DOCKER-USER -i ${bridgeName} -d 100.64.0.0/10 -j DROP

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
      # Wait for the container to get its IP
      for i in $(seq 1 30); do
        IP=$(docker inspect openclaw --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null)
        [ -n "$IP" ] && break
        sleep 1
      done

      if [ -z "$IP" ]; then
        echo "FATAL: could not resolve openclaw container IP"
        exit 1
      fi

      echo "Proxying 127.0.0.1:18789 → $IP:18789"
      exec socat TCP-LISTEN:18789,bind=127.0.0.1,reuseaddr,fork TCP:$IP:18789
    '';
  };
}
