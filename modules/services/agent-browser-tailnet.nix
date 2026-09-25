{
  config,
  lib,
  pkgs,
  vars,
  ...
}:
# Publishes the agent-browser dashboard of this host's user on the tailnet, at
# https://<node>:4848, so another machine can watch the agents' browsers.
#
# Split in two because the halves need different privileges. The dashboard is
# a user process (home/features/cli/agent-browser), and it has to be told the
# origin it is reached from; `tailscale serve` is a control operation that
# tailscaled takes only from root or its operator. Here the serve runs as root,
# so the account never becomes operator and its agents cannot reconfigure
# tailscaled. A host without NixOS does both from the user unit instead.
#
# Access: the tailnet ACL decides who reaches 4848, and the dashboard adds a
# token of its own, printed at start (`journalctl --user -u
# agent-browser-dashboard`). Anyone past both drives every browser session
# here, logged-in profiles included.
let
  cfg = config.modules.services.agentBrowserTailnet;
  port = 4848;
  tailscale = "${pkgs.tailscale}/bin/tailscale";
in
{
  options.modules.services.agentBrowserTailnet.enable = lib.mkEnableOption ''
    the agent-browser dashboard of `vars.user.name` on the tailnet, at
    `https://<node>:${toString port}` behind `tailscale serve`. Needs an ACL rule
    allowing ${toString port} of this node to whoever should watch it
  '';

  config = lib.mkIf cfg.enable {
    home-manager.users.${vars.user.name}.modules.cli.agentBrowser.dashboard.tailnet = {
      enable = true;
      serve = false;
    };

    systemd.services.agent-browser-tailnet-serve = {
      description = "Tailscale Serve -> agent-browser dashboard";
      after = [
        "tailscaled.service"
        "network-online.target"
      ];
      requires = [ "tailscaled.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      # The handler proxies to loopback whether or not the dashboard is up, so
      # there is no ordering against the user unit; until it starts, requests
      # get a 502 rather than reaching anything else.
      script = ''
        for _ in $(seq 1 60); do
          state="$(${tailscale} status --json 2>/dev/null | ${pkgs.jq}/bin/jq -r .BackendState)" || state=""
          [ "$state" = "Running" ] && break
          sleep 1
        done
        if [ "$state" != "Running" ]; then
          echo "tailscale is not running (state: ''${state:-unknown}), not publishing the dashboard" >&2
          exit 1
        fi
        ${tailscale} serve --bg --https=${toString port} http://127.0.0.1:${toString port}
      '';

      # Only this port's handler, never `serve reset`, so the Paseo one stays.
      preStop = "${tailscale} serve --https=${toString port} off || true";
    };
  };
}
