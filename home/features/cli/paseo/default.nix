{
  pkgs,
  lib,
  config,
  # Mirrors `hasDesktop` in home/default.nix. WSL is a terminal host whose
  # graphical layer belongs to Windows, so anything that ships a window is as
  # out of place here as it is on a server. Same `config`-position-only rule as
  # `terminalOnly` below.
  isWsl ? false,
  isServer ? false,
  # Terminal-only host: keep the shell, the agents and the CLI toolchain, drop
  # everything that ships a window. Distinct from `isServer`, which describes a
  # headless machine that still syncs with the personal fleet; this describes a
  # managed work laptop where the graphical layer belongs to someone else.
  #
  # Read only from `config` positions below, never from `imports`. A specialArg
  # with a default that is consulted while building the module tree sends the
  # module system to `_module.args`, which needs `config`, and that recurses.
  # Conditional imports are gated by real options instead (see ../syncthing).
  terminalOnly ? false,
  ...
}:
# Paseo, outro front end para os agentes de codigo que esta config ja instala.
#
# A topologia tem duas metades e elas nao moram no mesmo lugar. O daemon roda
# onde o codigo esta, nao onde a janela esta, entao ele e declarado no nivel
# NixOS pelo host que hospeda os repositorios: `services.paseo` em
# hosts/wsl/default.nix, com o modulo vindo do flake do proprio Paseo.
#
# Este arquivo cuida so do lado home-manager, e sao duas coisas: o CLI `paseo`,
# que vai para todo host porque e util em qualquer terminal, e o app desktop,
# que so faz sentido onde existe uma janela para abrir. Um host sem sessao
# grafica (WSL, servidor, laptop gerenciado) fica com o CLI e nada mais; o
# cliente, quando precisa, e o web UI embutido no navegador ou a build nativa
# da plataforma que tunela ate o daemon por SSH.
let
  # The same guard home/default.nix uses for the graphical tree, plus the
  # terminal-only work laptop, which that file never has to consider.
  hasDesktop = !isWsl && !isServer && !terminalOnly;

  cfg = config.modules.cli.paseo;
  paseoHome = "${config.home.homeDirectory}/.paseo";
  listen = "127.0.0.1:${toString cfg.daemon.port}";

  # `existing * managed`, managed wins, same merge the Claude settings use.
  # Not a plain overwrite like the NixOS module does on WSL: here the desktop
  # app also writes into config.json at runtime, and clobbering it on every
  # start would undo whatever was toggled in its settings screen.
  configMerge = pkgs.writeShellApplication {
    name = "paseo-config-merge";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      # usage: paseo-config-merge <managed.json>
      target="$PASEO_HOME/config.json"
      mkdir -p "$PASEO_HOME"
      tmp="$(mktemp "$PASEO_HOME/config.json.XXXXXX")"
      if [ -s "$target" ]; then
        jq -s '.[0] * .[1]' "$target" "$1" > "$tmp"
      else
        jq . "$1" > "$tmp"
      fi
      chmod 0600 "$tmp"
      mv "$tmp" "$target"
    '';
  };

  settingsFile = (pkgs.formats.json { }).generate "paseo-config.json" cfg.daemon.settings;

  # Publishes the loopback daemon on this node's own MagicDNS name, over TLS
  # that tailscaled provisions itself. The name is read from `tailscale status`
  # at start rather than declared, so the tailnet never appears in this repo,
  # and both checks the daemon runs on a browser request are fed from it:
  # `daemon.hostnames` (the Host header, DNS rebinding guard) and
  # `daemon.cors.allowedOrigins` (the Origin header, sent on every WebSocket
  # handshake even from the same origin). The daemon hot-reloads both fields,
  # so no restart is needed after the merge.
  #
  # `tailscale` is resolved from PATH, not pinned to a store path, because off
  # NixOS the CLI has to be the one that matches the running tailscaled, and
  # there that one comes from apt. The unit PATH below therefore carries both
  # `/run/current-system/sw/bin` (NixOS) and `/usr/bin` (everything else).
  tailnetServe = pkgs.writeShellApplication {
    name = "paseo-tailnet-serve";
    runtimeInputs = [
      pkgs.jq
      configMerge
    ];
    text = ''
      for _ in $(seq 1 60); do
        state="$(tailscale status --json 2>/dev/null | jq -r .BackendState)" || state=""
        [ "$state" = "Running" ] && break
        sleep 1
      done
      if [ "$state" != "Running" ]; then
        echo "tailscale is not running (state: ''${state:-unknown}), not publishing paseo" >&2
        exit 1
      fi

      fqdn="$(tailscale status --json | jq -r '.Self.DNSName | rtrimstr(".")')"
      if [ -z "$fqdn" ]; then
        echo "tailscale reports no MagicDNS name for this node, not publishing paseo" >&2
        exit 1
      fi

      # The daemon checks Origin on every WebSocket handshake. Its own name
      # covers the bundled web UI opened directly; extraAllowedOrigins covers
      # a Paseo UI served from elsewhere that adds this daemon as a host, and
      # would otherwise get a silent close 1006.
      managed="$(mktemp)"
      jq -n --arg fqdn "$fqdn" --args \
        '{daemon: {hostnames: [$fqdn], cors: {allowedOrigins: (["https://\($fqdn)"] + $ARGS.positional)}}}' \
        ${lib.escapeShellArgs cfg.tailnetServe.extraAllowedOrigins} > "$managed"
      paseo-config-merge "$managed"
      rm -f "$managed"

      # Renaming the node in the admin console leaves the handler behind under
      # the old name, which no longer resolves, and `serve --https=443 off`
      # only ever touches the current name's. The CLI has no per-name removal,
      # so the leftover can only go with a reset, and the result is a `serve
      # status` that lists an address nobody can reach.
      #
      # The reset is destructive, so it runs only when 443 is the whole serve
      # config on this node; with anything else served, the leftover is
      # reported and kept rather than taking that config down with it.
      stale="$(tailscale serve status --json 2>/dev/null |
        jq -r --arg k "$fqdn:443" '(.Web // {}) | keys[] | select(endswith(":443")) | select(. != $k)')"
      if [ -n "$stale" ]; then
        others="$(tailscale serve status --json 2>/dev/null | jq -r '
          ((.Web // {}) | keys[] | select(endswith(":443") | not)),
          ((.TCP // {}) | keys[] | select(. != "443"))
        ')"
        if [ -z "$others" ]; then
          echo "dropping serve config left behind by a rename ($stale)"
          tailscale serve reset
        else
          echo "stale serve handler from a rename ($stale); clear it with 'tailscale serve reset'" >&2
        fi
      fi

      if ! tailscale serve --bg --https=443 http://${listen}; then
        echo "tailscale serve refused. It needs root or the operator role; grant it once with" >&2
        echo "  paseo-tailnet-operator-setup" >&2
        exit 1
      fi
      echo "paseo published at https://$fqdn"
    '';
  };

  # `tailscale serve` is a control operation, so tailscaled only takes it from
  # root or from the user named as operator. Root-only and one-time, hence a
  # script run by hand rather than an activation step, same pattern as the
  # wrk-*-setup scripts in home/profiles/wrk.
  operatorSetup = pkgs.writeShellApplication {
    name = "paseo-tailnet-operator-setup";
    text = ''
      echo "Making $USER the tailscale operator, so paseo-tailnet-serve can run without root."
      sudo tailscale set --operator="$USER"
      systemctl --user restart paseo-tailnet-serve.service
      systemctl --user --no-pager status paseo-tailnet-serve.service
    '';
  };
in
{
  options.modules.cli.paseo = {
    daemon = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Run the Paseo daemon as a systemd user service, on loopback.

          For a host with no NixOS layer to declare `services.paseo`, such as
          the standalone `wrk` profile. The split is the one WSL uses: the
          daemon is a service, the app a client. The desktop app is pointed at
          it automatically (its "Manage built-in daemon" setting is turned
          off), since two daemons cannot share the port.
        '';
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 6767;
        description = "Loopback port the daemon listens on.";
      };

      settings = lib.mkOption {
        inherit (pkgs.formats.json { }) type;
        default = { };
        description = ''
          Managed part of `~/.paseo/config.json`, merged over the existing
          file on every service start, managed keys winning. Schema is
          `PersistedConfigSchema` in the Paseo sources.
        '';
      };
    };

    tailnetServe = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Publish the daemon on the tailnet as `https://<node>.<tailnet>.ts.net`
          via `tailscale serve`, and allowlist that origin in the daemon.

          The daemon has no password; who reaches port 443 of this node is
          decided by the tailnet ACL, and that rule is its authentication.
          Needs the user to be tailscale operator once:
          `paseo-tailnet-operator-setup`.
        '';
      };

      extraAllowedOrigins = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "https://paseo.example.dev" ];
        description = ''
          Further origins the daemon accepts WebSocket connections from, on
          top of its own MagicDNS name. Needed for every other Paseo UI that
          adds this daemon as a host: the browser sends that UI's origin,
          and the daemon closes the socket (code 1006) when it is not listed.

          Empty here on purpose; a personal or project domain is a value for
          a private layer.
        '';
      };
    };
  };

  config = {
    home.packages = [
      pkgs.paseo
    ]
    # An Electron app with a window, so it follows the same rule as the rest of
    # the graphical tree. The daemon is the half that matters and it is a plain
    # service: on WSL it is declared in hosts/wsl and the client lives on the
    # Windows side, either the bundled web UI in a browser or the Windows build
    # of this same app tunnelling in over SSH.
    ++ lib.optionals hasDesktop [
      pkgs.paseo-desktop
    ]
    ++ lib.optionals cfg.tailnetServe.enable [
      operatorSetup
    ];

    # The `paseo` CLI's `paseo .` launcher only probes a few hardcoded paths for
    # the desktop app; symlink the Nix build where it looks so `paseo .` finds it.
    # The `.AppImage` name is what the launcher probes for, not a description of
    # the target: nix/desktop-package.nix produces a shell wrapper around
    # electron, never an AppImage.
    home.file."Applications/Paseo.AppImage" = lib.mkIf hasDesktop {
      source = lib.getExe pkgs.paseo-desktop;
    };

    # Point the desktop app at the service above. Without it the app spawns its
    # own daemon on the same port, the service loses the race or crash-loops,
    # and the one that wins is the app's, which is launched with `--no-web-ui`:
    # the tailnet then reaches the API and gets 404 for every UI path.
    #
    # Gated on daemon.enable rather than hasDesktop, because the machine this
    # matters on is the terminal-only work laptop, where the app is the
    # distro's package and not this tree's.
    #
    # Patched in place rather than owned: the file is the app's own state, and
    # rewriting it would drop the notification and release-channel settings
    # next to this key. The test is a plain `!= false`, never `(… // true) !=
    # false`: jq's `//` treats `false` as empty, so the alternative fires on
    # the very value being checked and the guard never closes, rewriting the
    # file on every activation. A missing key is null, which is `!= false`, so
    # an untouched file is still patched.
    home.activation.paseoDesktopDaemon = lib.mkIf cfg.daemon.enable (
      lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        settings="${config.home.homeDirectory}/.config/Paseo/desktop-settings.json"
        if [ -f "$settings" ] && ${lib.getExe pkgs.jq} -e \
          '.settings.daemon.manageBuiltInDaemon != false' "$settings" >/dev/null 2>&1; then
          $DRY_RUN_CMD ${lib.getExe pkgs.jq} '.settings.daemon.manageBuiltInDaemon = false' \
            "$settings" >"$settings.hm-tmp" && $DRY_RUN_CMD mv "$settings.hm-tmp" "$settings"
          echo "paseo: desktop app pointed at the systemd-managed daemon"
        fi
      ''
    );

    assertions = [
      {
        assertion = cfg.tailnetServe.enable -> cfg.daemon.enable;
        message = "modules.cli.paseo.tailnetServe needs modules.cli.paseo.daemon.enable: there is no daemon to publish otherwise.";
      }
    ];

    systemd.user.services = lib.mkMerge [
      (lib.mkIf cfg.daemon.enable {
        paseo = {
          Unit = {
            Description = "Paseo daemon (self-hosted, loopback)";
            After = [ "network.target" ];
          };
          Service = {
            Type = "simple";
            Environment = [
              "PASEO_HOME=${paseoHome}"
              "PASEO_LISTEN=${listen}"
              # Agents the daemon spawns need the nix userland, and a user unit
              # off NixOS starts with the distro's PATH only.
              "PATH=${config.home.profileDirectory}/bin:/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin"
            ];
            ExecStart = "${pkgs.paseo}/bin/paseo-server --no-relay";
            Restart = "on-failure";
            RestartSec = 5;
            KillSignal = "SIGTERM";
            TimeoutStopSec = 15;
          }
          // lib.optionalAttrs (cfg.daemon.settings != { }) {
            ExecStartPre = "${lib.getExe configMerge} ${settingsFile}";
          };
          Install.WantedBy = [ "default.target" ];
        };
      })

      (lib.mkIf cfg.tailnetServe.enable {
        paseo-tailnet-serve = {
          Unit = {
            Description = "Publish the Paseo daemon on the tailnet";
            After = [ "paseo.service" ];
            Wants = [ "paseo.service" ];
          };
          Service = {
            Type = "oneshot";
            RemainAfterExit = true;
            Environment = [
              "PASEO_HOME=${paseoHome}"
              "PATH=/run/current-system/sw/bin:/usr/local/bin:/usr/bin:/bin"
            ];
            ExecStart = lib.getExe tailnetServe;
            ExecStop = "/usr/bin/env tailscale serve --https=443 off";
          };
          Install.WantedBy = [ "default.target" ];
        };
      })
    ];
  };
}
