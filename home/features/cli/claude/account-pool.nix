{
  pkgs,
  lib,
  config,
  ...
}:
# A pool of Claude subscriptions behind one local endpoint, so that an account
# nearing its limit hands traffic to the next one without any running claude
# noticing.
#
# The pool is teamclaude (https://github.com/KarpelesLab/teamclaude), a reverse
# proxy on loopback. Every claude process sends its requests to it through
# ANTHROPIC_BASE_URL, and the proxy picks an account per request, injects that
# account's token, and reads the anthropic-ratelimit-unified-* headers of each
# response to know when to move on. The switch therefore happens inside the
# proxy, between two requests, and no claude ever holds a token that went
# stale: that is the whole reason for a proxy over a tool that swaps
# ~/.claude/.credentials.json on disk, whose running sessions only learn about
# the swap on their next token check and still meet a quota 429 that lands
# between two usage polls.
#
# Adding accounts (with the option still off, because turning it on points
# every claude at the proxy, and the proxy refuses to start with no account):
#
#   teamclaude login            # browser OAuth, once per account
#   teamclaude login --token    # same, copy/paste flow for a headless host
#   teamclaude accounts         # what the pool holds, with tier and expiry
#
# Prefer `login` to `teamclaude import`. Import copies the refresh token that
# Claude Code itself is using, and refresh tokens rotate on use: whichever of
# the two refreshes second holds a dead token, and when that is Claude Code it
# stops and asks for /login, which is the exact stall this exists to avoid.
# A fresh `login` is an independent grant for the same account. Do not run
# `teamclaude service install` or `teamclaude alias --install` either: the
# unit and the routing are declared here, and those write their own copies.
#
# Turning it on, per host, once the accounts are in:
#
#   home-manager.users.${vars.user.name}.modules.cli.claude.accountPool.enable = true;
#
# then `switch`. Claude processes started before the switch keep talking to
# Anthropic directly until they exit; everything started after goes through
# the pool. On a host that runs the Paseo daemon, modules/services/paseo.nix
# also turns on lingering, so the proxy is up at boot and not only after the
# first login.
#
# Verifying:
#
#   systemctl --user status teamclaude     # active (running)
#   teamclaude status                      # accounts, quota bars, threshold
#   claude -p 'Reply with exactly: ok'     # then:
#   journalctl --user -u teamclaude -n 20  # the POST /v1/messages and its account
let
  cfg = config.modules.cli.claude.accountPool;

  port = 3456;
  baseUrl = "http://127.0.0.1:${toString port}";

  # Rotate off an account at 95% of its 5h or weekly window instead of the
  # upstream 98%: a fleet of parallel agents can burn the last few percent
  # between two responses, and the margin is what keeps a rotation ahead of a
  # quota 429 rather than behind it.
  switchThreshold = 0.95;

  # When every account is spent the proxy holds the request open and polls
  # once a minute instead of returning a 429, which Claude Code would turn into
  # its interactive rate-limit menu. Five hours is the length of the session
  # window, so any account that is out only on its 5h bucket comes back inside
  # the hold. The proxy sends nothing while it holds, so the client timeout has
  # to outlast it: the same hold plus one poll that `teamclaude run` sets.
  holdSeconds = 5 * 60 * 60;
  apiTimeoutMs = (holdSeconds + 60) * 1000;

  # The same path teamclaude resolves on its own ($XDG_CONFIG_HOME, else
  # ~/.config), spelled out so the service and the CLI in a shell cannot drift.
  configFile = "${config.xdg.configHome}/teamclaude.json";

  # The config file holds every account's OAuth tokens and the proxy key, and
  # teamclaude rewrites it whenever it refreshes a token, so it is mutable state
  # written by `teamclaude login` and never a store path. What this module owns
  # is a handful of keys inside it, set before every start through teamclaude's
  # own `atomicConfigUpdate`: that honours the advisory lock the CLI and the
  # server take on the file, writes it atomically at 0600, and creates the
  # default config (with a random proxy key) when there is none yet. Importing
  # a module from the package's source tree is not a published API, so an
  # upstream rename fails the unit loudly at start, which is the right way for
  # it to break.
  #
  # Besides the routing knobs, it re-closes every surface that reaches past
  # this host or acts on its own, so a TUI or hand edit cannot keep one open
  # across a restart: the npm self-updater (the package wrapper already sets
  # TEAMCLAUDE_DISABLE_AUTOUPDATE, but an empty inherited value would undo
  # it), the MCP control plane, the sx.org residential egress, and the quota
  # probe and keep-warm, which make calls with nobody at the keyboard. The
  # client mode goes to base-URL so a manual `teamclaude run` or `env` never
  # hands a child the MITM CA.
  #
  # `proxy.trustLoopback` stays at its default (true) on purpose: this is a
  # single-user host, and the exemption is what lets claude reach the pool
  # without carrying the proxy key. A shared host would need it false.
  managedSettings = pkgs.writeText "teamclaude-managed-settings.mjs" ''
    import { atomicConfigUpdate } from "${pkgs.teamclaude}/share/teamclaude/src/config.js";

    await atomicConfigUpdate((config) => {
      config.proxy = { ...config.proxy, port: ${toString port} };
      delete config.proxy.mcp;
      config.switchThreshold = ${builtins.toJSON switchThreshold};
      config.holdSeconds = ${toString holdSeconds};
      config.autoUpdate = false;
      config.defaultClientMode = "base-url";
      delete config.sx;
      config.quotaProbeSeconds = 0;
      config.warmupSeconds = 0;
      delete config.warmupSchedule;
    });
  '';

  # Claude Code itself, pointed at the pool. A wrapper around the binary rather
  # than a session variable because omp reads ANTHROPIC_BASE_URL too, and a
  # shell-wide or daemon-wide variable would send its traffic through the pool
  # as well. The wrapper reaches every claude that resolves through PATH: the
  # shell, scripts, and the Paseo daemon's `claude` provider, which spawns the
  # binary from the home-manager profile on its PATH. `--set-default` keeps an
  # explicit ANTHROPIC_BASE_URL winning, so a launch that points claude at
  # another backend on purpose is left alone.
  claudeThroughPool = pkgs.symlinkJoin {
    name = "claude-code-account-pool";
    paths = [ pkgs.claude-code ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/claude \
        --set-default ANTHROPIC_BASE_URL ${baseUrl} \
        --set-default API_TIMEOUT_MS ${toString apiTimeoutMs}
    '';
    meta.mainProgram = "claude";
  };
in
{
  options.modules.cli.claude.accountPool.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Run the teamclaude account pool as a user service on ${baseUrl} and
      route every claude through it.

      Add the accounts with `teamclaude login` before turning this on: with no
      account the proxy refuses to start, and every claude would then fail to
      connect. See the comment at the top of this file.
    '';
  };

  config = lib.mkMerge [
    # The CLI is installed with the option off too, because the accounts have
    # to be logged in before the option can be turned on.
    { home.packages = [ pkgs.teamclaude ]; }

    (lib.mkIf cfg.enable {
      # Shadows the plain claude-code that ./default.nix installs.
      home.packages = [ (lib.hiPrio claudeThroughPool) ];

      systemd.user.services.teamclaude = {
        Unit = {
          Description = "teamclaude, the Claude account pool proxy";
          Documentation = "https://github.com/KarpelesLab/teamclaude";
        };
        Service = {
          Environment = [
            "TEAMCLAUDE_CONFIG=${configFile}"
            # Loopback only, whatever the config file says: the proxy injects
            # real account tokens, so an off-box listener would lend them out.
            "TEAMCLAUDE_HOST=127.0.0.1"
          ];
          ExecStartPre = "${lib.getExe pkgs.nodejs_24} ${managedSettings}";
          ExecStart = "${lib.getExe pkgs.teamclaude} server --headless";
          # `always`, not `on-failure`: every claude on the host depends on
          # this listener, so it has to come back from a clean exit as well. A
          # stop asked of systemd still stops it. 3s keeps five restarts
          # outside systemd's default 10s start limit, so a pool emptied by
          # hand keeps retrying and resumes on its own once an account is back.
          Restart = "always";
          RestartSec = "3s";
        };
        Install.WantedBy = [ "default.target" ];
      };
    })
  ];
}
