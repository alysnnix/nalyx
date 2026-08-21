# Home Assistant, served on the tailnet over HTTPS under a custom domain.
#
# Topology:
#   browser (tailnet peer) --HTTPS 443--> nginx --HTTP--> 127.0.0.1:8123
#
# Why nginx and a custom domain instead of `tailscale serve`:
#   - Home Assistant does not support living under a subpath. Its frontend
#     derives absolute URLs from the document root, so the path-mount that
#     `tailscale serve` offers on the node's MagicDNS name cannot host it.
#   - A custom domain is what makes a bare hostname possible at all, since
#     `serve` only ever answers for `<node>.<tailnet>.ts.net`.
#
# Why TLS is not optional here:
#   the whole `.dev` TLD is on the HSTS preload list shipped in every current
#   browser, so a `.dev` host is unreachable over plain HTTP no matter what
#   nginx offers. The certificate comes from ACME over DNS-01 because an
#   HTTP-01 challenge needs a publicly reachable port 80, and this host
#   deliberately has no public port at all.
#
# Why this is not internet-exposed, even though nginx binds 0.0.0.0:443:
#   two independent layers, either of which alone is sufficient.
#     1. 443 is never added to the host's public `allowedTCPPorts`, and the
#        host trusts only `tailscale0`, so the port is accepted from tailnet
#        peers and dropped on every other interface.
#     2. `hostName` resolves to this node's tailnet address, which lives in
#        the CGNAT range (100.64.0.0/10) and is not routable from the
#        internet. A non-tailnet client cannot open the socket even if the
#        firewall were to let it through.
#   Binding the wildcard rather than the tailnet address on purpose: the
#   tailscale0 address only exists once tailscaled has settled, and a vhost
#   pinned to it would fail to bind on a cold boot.
{
  config,
  lib,
  vars,
  ...
}:
let
  cfg = config.nalyx.homeAssistant;

  # Loopback-only backend. nginx is the sole client and therefore also the
  # sole trusted proxy, so no tailnet peer can forge `X-Forwarded-For`.
  backendHost = "127.0.0.1";
  backendPort = 8123;
in
{
  options.nalyx.homeAssistant = {
    enable = lib.mkEnableOption "Home Assistant, reachable only from the tailnet";

    hostName = lib.mkOption {
      type = lib.types.str;
      example = "home-assistant.example.dev";
      description = ''
        Public DNS name the instance answers to.

        Its A record must point at this host's tailnet address, which is what
        keeps the instance reachable only from the tailnet. On Cloudflare the
        record has to be DNS-only (grey cloud): the proxy cannot reach a CGNAT
        address, and proxying it would also publish the service.

        The name must sit in the zone that `acmeCredentialsFile` is scoped to,
        since the certificate is issued over a DNS-01 challenge.
      '';
    };

    acmeCredentialsFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/secrets/cloudflare_dns_token";
      description = ''
        Path to an environment file holding `CF_DNS_API_TOKEN=<token>`, for a
        Cloudflare token scoped to `Zone:DNS:Edit` on the zone of
        {option}`hostName`. Point it at a sops-nix secret.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.acmeCredentialsFile != null;
        message =
          "nalyx.homeAssistant.acmeCredentialsFile must be set: ${cfg.hostName} cannot be"
          + " served over plain HTTP because `.dev` is HSTS-preloaded, and the certificate"
          + " needs a Cloudflare token to answer the DNS-01 challenge.";
      }
    ];

    # `extraComponents` and `homeassistant.time_zone` are left at their module
    # defaults on purpose: the former already carries the onboarding set
    # (default_config, met, esphome) and the latter inherits `time.timeZone`.
    services.home-assistant = {
      enable = true;
      config = {
        default_config = { };
        homeassistant.external_url = "https://${cfg.hostName}";
        http = {
          server_host = [ backendHost ];
          use_x_forwarded_for = true;
          trusted_proxies = [ backendHost ];
        };
      };
    };

    security.acme = {
      acceptTerms = true;
      defaults.email = vars.user.email;
      certs.${cfg.hostName} = {
        dnsProvider = "cloudflare";
        environmentFile = cfg.acmeCredentialsFile;
        # nginx reads the key directly, so it owns the group rather than the
        # default `acme`.
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
          proxyPass = "http://${backendHost}:${toString backendPort}";
          # The frontend streams every state change over a WebSocket. Without
          # the upgrade the page loads and then stays permanently blank.
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
  };
}
