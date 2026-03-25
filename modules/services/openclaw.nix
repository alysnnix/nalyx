# OpenClaw AI assistant — runs 24/7 in a Kata Containers micro-VM
# Isolation: each container gets its own kernel (hardware virtualization via KVM)
# Network policy: internet YES, LAN/host/Tailscale NO
#
# Build the image (from cloned openclaw repo):
#   docker build -t openclaw:latest --build-arg OPENCLAW_INSTALL_BROWSER=1 .
#
# Deploy into the isolated network:
#   docker run -d --name openclaw \
#     --runtime=kata \
#     --network openclaw-isolated \
#     --restart unless-stopped \
#     --cap-drop ALL \
#     --security-opt no-new-privileges \
#     --read-only \
#     --tmpfs /tmp \
#     --tmpfs /home/node/.openclaw/logs \
#     --memory 4g \
#     --cpus 2 \
#     --pids-limit 512 \
#     --dns 1.1.1.1 --dns 9.9.9.9 \
#     -v /var/lib/openclaw:/home/node/.openclaw \
#     --env-file /var/lib/openclaw/.env \
#     openclaw:latest
#
# Gateway port: 18789 (loopback only inside container)
# Health check: GET /healthz and /readyz
# WhatsApp pairing: docker exec -it openclaw openclaw channels login --channel whatsapp
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

  virtualisation.docker.daemon.settings = {
    runtimes = {
      kata = {
        path = "${pkgs.kata-runtime}/bin/kata-runtime";
      };
    };
  };

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
}
