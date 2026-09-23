# Declarative omp settings, layered on top of the mutable global config
# (~/.omp/agent/config.yml) via the PI_CONFIG_FILES overlay mechanism.
# Overlays sit above the global config in omp's precedence, so these values
# win without ever owning or overwriting the file omp itself writes at
# runtime (and which syncthing syncs across machines).
#
# Why this is a standalone file and not a `let` inside ./default.nix: the home
# feature only reaches the omp a login shell starts, because PI_CONFIG_FILES is
# a home-manager session variable. The agents the Paseo daemon spawns come from
# a system service, which never sources hm-session-vars, so they used to run
# with no overlay at all: `enabledProviders` fell back to omp's empty default
# and every Paseo session silently lost the whole ~/.claude surface, MCP servers
# included. modules/services/paseo.nix imports this same file and puts it in the
# service environment, so both entry points read one definition.
{ pkgs }:
let
  yamlFormat = pkgs.formats.yaml { };

  # Anthropic only. Opus where the role decides or writes code, Sonnet where
  # it reads, summarizes, or does rote work: effort trims thinking tokens but
  # not the per-token price, and Opus costs twice what Sonnet does. Change a
  # role here, not in `/model`: the overlay outranks the mutable config, so a
  # role picked in the TUI is written but never wins.
  opus = effort: "anthropic/claude-opus-5-5:${effort}";
  sonnet = effort: "anthropic/claude-sonnet-5:${effort}";
in
yamlFormat.generate "omp-nix-overlay.yml" {
  # Foreign user-level discovery sources omp is allowed to read. The default
  # is empty, and an empty list means omp ignores ~/.claude entirely: no
  # Claude skills, no Claude marketplace plugins, no MCP servers from
  # ~/.claude/settings.json. Enabling `claude` also enables `claude-plugins`
  # (omp special-cases the pair), so this one entry is what makes omp see
  # everything Claude Code sees.
  #
  # This used to live only in ~/.omp/agent/config.yml, which omp writes
  # itself at setup time: a host that never ran that setup, or a config reset,
  # silently dropped every Claude-side skill with no error. Declaring it here
  # makes the discovery surface a property of the flake instead.
  #
  # Consequence to know about: the overlay outranks the mutable config, so
  # toggling a user source from inside omp no longer sticks. Adding a source
  # means adding it to this list.
  enabledProviders = [ "claude" ];

  # Model personas. Built-in roles first, then two custom ones (`review`,
  # `explore`) that only exist to be targeted by the agent map below.
  modelRoles = {
    default = opus "high"; # the main session
    plan = opus "xhigh"; # plan mode
    slow = opus "max"; # `--slow`, the hard problems
    task = opus "high"; # implementation subagents
    advisor = opus "high"; # the turn reviewer, when enabled
    review = opus "xhigh"; # reviewer agents
    vision = sonnet "medium";
    commit = sonnet "low";
    smol = sonnet "low"; # quick one-shots, sonic, prewalk target
    explore = sonnet "low"; # scout: read-heavy, so input tokens dominate
    # Session titles, memory, auto-thinking classification: background
    # chores that run on every turn, where Opus buys nothing but latency.
    tiny = "anthropic/claude-haiku-4-5";
  };

  # Route each task agent through a role instead of its bundled default, so
  # the table above is the single place a subagent's model is decided.
  task.agentModelOverrides = {
    task = "@task";
    frontend-builder = "@task";
    sonic = "@smol";
    scout = "@explore";
    reviewer = "@review";
    security-reviewer = "@review";
  };

  startup = {
    # Suppress omp's startup/status notices, including the `xd://: mounted
    # <every mcp tool name>` banner that `#notifyXdevMountDelta` emits the
    # first time MCP servers finish connecting (i.e. right after the first
    # message of a session). With this many MCP servers that notice is a
    # screenful of noise in the Paseo transcript, and `startup.quiet` is the
    # only gate omp has on it. Nothing else is lost but the welcome screen.
    quiet = true;
  };

  tools = {
    # Mount rarely-used (discoverable) tools (MCP, LSP, inspect_image,
    # generate_image) under xd:// device URLs, driven on demand via
    # read/write, instead of shipping every schema on every request. This
    # is omp's own default (tools.xdev defaults to true); we set it
    # explicitly to document the choice. With many MCP servers connected,
    # top-level exposure (xdev = false) added ~90k tokens of tool schemas
    # to the base of every request, even a bare greeting. Essential coding
    # tools (read/write/edit/bash/glob/grep) stay top-level regardless; the
    # trade-off is a one-hop discovery when an MCP or image tool is
    # actually needed, paid only then rather than on every message.
    xdev = true;
  };

  # Load the context image-pruner extension in every session. It keeps only
  # the most-recent N image blocks per request (env OMP_MAX_CONTEXT_IMAGES,
  # default 10) so a long session never trips Anthropic's stricter 2000px
  # per-image cap that applies once a request carries more than 20 images.
  extensions = [ "${./prune-context-images.js}" ];
}
