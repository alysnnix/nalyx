# Home Assistant, reachable only from the tailnet.
#
# Two ways to publish it, picked with `mode`, mutually exclusive because both
# want the tailnet address's port 443:
#
#   serve (default)
#     browser --HTTPS 443--> tailscaled --> 127.0.0.1:8123
#     `tailscale serve` answers for the node's MagicDNS name and terminates
#     TLS with a certificate it provisions and renews on its own. No DNS
#     record and no credentials to manage. The URL is fixed to
#     `https://<node>.<tailnet>.ts.net`, so it follows the node's name, and it
#     claims that name's root path.
#
#   nginx
#     browser --HTTPS 443--> nginx --HTTP--> 127.0.0.1:8123
#     Serves `hostName` with an ACME certificate. Buys a custom domain at the
#     cost of a DNS record and a Cloudflare token.
#
# Home Assistant is never mounted on a subpath in either mode: its frontend
# derives absolute URLs from the document root, so only a root mount works.
#
# Why the nginx mode needs DNS-01 rather than the usual HTTP-01: an HTTP-01
# challenge has to be answered on a publicly reachable port 80, and this host
# deliberately has no public port. Note also that a `.dev` hostname has no
# plain-HTTP fallback to fall back on, since the whole TLD ships in the HSTS
# preload list of every current browser.
#
# Why neither mode is internet-exposed:
#   - `tailscale serve` is tailnet-only by construction. Publishing to the
#     internet is a different verb (`funnel`), which is not used here.
#   - In nginx mode, 443 is never added to the host's public
#     `allowedTCPPorts`, and the host trusts only `tailscale0`, so the port is
#     accepted from tailnet peers and dropped on every other interface. On top
#     of that, `hostName` resolves to the node's tailnet address, which lives
#     in the CGNAT range (100.64.0.0/10) and is not routable from the
#     internet. Binding the wildcard rather than that address is deliberate:
#     the tailscale0 address only exists once tailscaled has settled, and a
#     vhost pinned to it would fail to bind on a cold boot.
{
  config,
  lib,
  pkgs,
  vars,
  ...
}:
let
  cfg = config.nalyx.homeAssistant;

  # Loopback-only backend. In both modes the proxy is the sole client and
  # therefore also the sole trusted proxy, so no tailnet peer can forge
  # `X-Forwarded-For`.
  backendHost = "127.0.0.1";
  backendPort = 8123;
  backend = "http://${backendHost}:${toString backendPort}";
in
{
  options.nalyx.homeAssistant = {
    enable = lib.mkEnableOption "Home Assistant, reachable only from the tailnet";

    mode = lib.mkOption {
      type = lib.types.enum [
        "serve"
        "nginx"
      ];
      default = "serve";
      description = ''
        How the instance is published. `serve` uses `tailscale serve` on the
        node's MagicDNS name and needs no configuration at all. `nginx` serves
        {option}`hostName` with an ACME certificate and requires
        {option}`acmeCredentialsFile`.
      '';
    };

    hostName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "home-assistant.example.dev";
      description = ''
        Public DNS name the instance answers to. Required in `nginx` mode.

        Its A record must point at this host's tailnet address, which is what
        keeps the instance reachable only from the tailnet. On Cloudflare the
        record has to be DNS-only (grey cloud): the proxy cannot reach a CGNAT
        address, and proxying it would also publish the service. The name must
        sit in the zone that {option}`acmeCredentialsFile` is scoped to.

        In `serve` mode the name is decided by Tailscale, so this is only used
        to fill in Home Assistant's `external_url`, and may be left null.
      '';
    };

    acmeCredentialsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/cloudflare_dns_token";
      description = ''
        Path to an environment file holding `CF_DNS_API_TOKEN=<token>`, for a
        Cloudflare token scoped to `Zone:DNS:Edit` on the zone of
        {option}`hostName`. Point it at a sops-nix secret. Only used in
        `nginx` mode.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        assertions = [
          {
            assertion = cfg.mode == "nginx" -> cfg.hostName != null;
            message = "nalyx.homeAssistant.hostName is required in nginx mode: it is the name the vhost and its certificate are issued for.";
          }
          {
            assertion = cfg.mode == "nginx" -> cfg.acmeCredentialsFile != null;
            message =
              "nalyx.homeAssistant.acmeCredentialsFile is required in nginx mode:"
              + " the certificate needs a Cloudflare token to answer the DNS-01 challenge,"
              + " and a `.dev` host has no plain-HTTP fallback because the TLD is HSTS-preloaded.";
          }
        ];

        # `extraComponents` and `homeassistant.time_zone` are left at their
        # module defaults on purpose: the former already carries the onboarding
        # set (default_config, met, esphome) and the latter inherits
        # `time.timeZone`.
        services.home-assistant = {
          enable = true;
          config = {
            default_config = { };
            http = {
              server_host = [ backendHost ];
              use_x_forwarded_for = true;
              trusted_proxies = [ backendHost ];
            };
          }
          // lib.optionalAttrs (cfg.hostName != null) {
            homeassistant.external_url = "https://${cfg.hostName}";
          };
        };
      }

      (lib.mkIf (cfg.mode == "serve") {
        systemd.services.home-assistant-tailscale-serve = {
          description = "Tailscale Serve → Home Assistant";
          after = [
            "tailscaled.service"
            "home-assistant.service"
            "network-online.target"
          ];
          requires = [ "tailscaled.service" ];
          wants = [
            "home-assistant.service"
            "network-online.target"
          ];
          wantedBy = [ "multi-user.target" ];

          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            TimeoutStartSec = "120s";
            Restart = "on-failure";
            RestartSec = "5s";
          };

          # Setting the root mount replaces whatever was mounted there before,
          # so a stale mount left in tailscaled's persisted serve config is
          # corrected on the next start without a node-wide `serve reset`.
          script = ''
            # On a cold boot tailscaled is still settling (netMap is nil /
            # NoState) and `tailscale serve` fails outright, so wait until the
            # backend reports Running before touching it.
            for _ in $(seq 1 60); do
              ${pkgs.tailscale}/bin/tailscale status --json 2>/dev/null \
                | grep -q '"BackendState": *"Running"' && break
              sleep 1
            done
            ${pkgs.tailscale}/bin/tailscale serve --bg ${backend}
          '';
          preStop = "${pkgs.tailscale}/bin/tailscale serve --https=443 off || true";
        };
      })

      (lib.mkIf (cfg.mode == "nginx") {
        security.acme = {
          acceptTerms = true;
          defaults.email = vars.user.email;
          certs.${cfg.hostName} = {
            dnsProvider = "cloudflare";
            environmentFile = cfg.acmeCredentialsFile;
            # nginx reads the key directly, so it owns the group rather than
            # the default `acme`.
            group = config.services.nginx.group;
          };
        };

        services.nginx = {
          enable = true;
          recommendedProxySettings = true;
          recommendedTlsSettings = true;

          virtualHosts.${cfg.hostName} = {
            forceSSL = true;
            useACMEHost = cfg.hostName;
            locations."/" = {
              proxyPass = backend;
              # The frontend streams every state change over a WebSocket.
              # Without the upgrade the page loads and then stays blank.
              proxyWebsockets = true;
            };
          };
        };

        # Redundant while `trustedInterfaces` trusts all of tailscale0, but it
        # records the intent and survives that being tightened later.
        networking.firewall.interfaces."tailscale0".allowedTCPPorts = [
          80
          443
        ];
      })
    ]
  );
}
