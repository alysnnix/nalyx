{
  pkgs,
  lib,
  config,
  isServer ? false,
  ...
}:
let
  cfg = config.modules.cli.agentBrowser.dashboard.tailnet;
  agentBrowser = pkgs.callPackage ../../../../packages/agent-browser.nix { };
  exe = lib.getExe agentBrowser;
  port = 4848;

  # `dashboard start` forks its server and exits. Allowed origins are read only
  # at start ("stop the dashboard before changing its port or allowed
  # origins"), so a running one is stopped first, or a new origin would never
  # take effect.
  #
  # Behind `tailscale serve` the browser sends `https://<node>:4848` as Origin,
  # which the dashboard rejects unless listed. The name is read from `tailscale
  # status`, never declared, so the tailnet stays out of this repo. Without a
  # running tailscale the dashboard still starts, loopback only: the local
  # view matters more than the remote one.
  #
  # Distro tailscale off NixOS, same reason as paseo-tailnet-serve: the CLI
  # has to match the tailscaled the machine runs.
  start = pkgs.writeShellApplication {
    name = "agent-browser-dashboard-start";
    runtimeInputs = [
      pkgs.jq
      pkgs.coreutils
    ];
    text = ''
      ${exe} dashboard stop >/dev/null 2>&1 || true
    ''
    + lib.optionalString cfg.enable ''
      fqdn=""
      for _ in $(seq 1 60); do
        state="$(tailscale status --json 2>/dev/null | jq -r .BackendState)" || state=""
        if [ "$state" = "Running" ]; then
          fqdn="$(tailscale status --json | jq -r '.Self.DNSName | rtrimstr(".")')"
          break
        fi
        sleep 1
      done
      if [ -z "$fqdn" ]; then
        echo "tailscale is not running, dashboard stays loopback only" >&2
        exec ${exe} dashboard start --port ${toString port}
      fi

      # Prints the external URL with its access token: open that one once from
      # the other machine, the bare https://<node>:${toString port} is refused.
      ${exe} dashboard start --port ${toString port} --allowed-origins "https://$fqdn:${toString port}"
    ''
    + lib.optionalString (cfg.enable && cfg.serve) ''

      if ! tailscale serve --bg --https=${toString port} http://127.0.0.1:${toString port}; then
        echo "tailscale serve refused. It needs root or the operator role; grant it once with" >&2
        echo "  sudo tailscale set --operator=\"$USER\"" >&2
        exit 1
      fi
      echo "agent-browser dashboard published at https://$fqdn:${toString port}"
    ''
    + lib.optionalString (!cfg.enable) ''
      exec ${exe} dashboard start --port ${toString port}
    '';
  };
in
{
  options.modules.cli.agentBrowser.dashboard.tailnet = {
    enable = lib.mkEnableOption ''
      the agent-browser dashboard reachable from the tailnet, at
      `https://<node>:${toString port}` behind `tailscale serve`.

      Its own port rather than a path under the Paseo name: the dashboard is a
      Next.js export with absolute `/_next/...` asset paths, so under a prefix
      its assets would land on whatever serves `/`. Who reaches the port is the
      tailnet ACL's call, plus the token in the URL the dashboard prints at
      start, since anyone holding that URL drives every browser session here
    '';

    serve = lib.mkOption {
      type = lib.types.bool;
      default = cfg.enable;
      defaultText = lib.literalExpression "config.modules.cli.agentBrowser.dashboard.tailnet.enable";
      description = ''
        Run `tailscale serve` from this user unit. Needs the user to be the
        tailscale operator. A NixOS host turns it off and publishes the port
        from a root unit instead (modules/services/agent-browser-tailnet.nix),
        so the account never gets to reconfigure tailscaled.
      '';
    };
  };

  config = lib.mkIf (!isServer) {
    # Browser automation CLI for the agents (Claude Code, omp, Codex). Skipped
    # on servers: it drives a real Chrome, and the package pins one in.
    #
    # Kept on terminal-only hosts on purpose: it has no window of its own, and
    # it is the one browser tool every agent is standardized on.
    home.packages = [ agentBrowser ];

    # The dashboard (http://localhost:${toString port}), up from login so the
    # agents' sessions can be watched without anyone starting it by hand.
    # Oneshot plus RemainAfterExit because `dashboard start` forks: the server
    # stays in the unit's cgroup, and stop runs the CLI's own `dashboard stop`.
    systemd.user.services.agent-browser-dashboard = {
      Unit.Description = "agent-browser observability dashboard";
      Service = {
        Type = "oneshot";
        # tailscale is not in a user unit's PATH on either kind of host: on
        # NixOS it lives in the system profile, off NixOS it comes from apt.
        Environment = lib.optional cfg.enable "PATH=/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin";
        ExecStart = lib.getExe start;
        ExecStop = [
          "${exe} dashboard stop"
        ]
        ++ lib.optional cfg.serve "-/usr/bin/env tailscale serve --https=${toString port} off";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
