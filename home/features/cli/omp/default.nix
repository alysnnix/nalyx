{
  pkgs,
  ...
}:
let
  yamlFormat = pkgs.formats.yaml { };

  # Declarative omp settings, layered on top of the mutable global config
  # (~/.omp/agent/config.yml) via the PI_CONFIG_FILES overlay mechanism.
  # Overlays sit above the global config in omp's precedence, so these values
  # win without ever owning or overwriting the file omp itself writes at
  # runtime (and which syncthing syncs across machines).
  configOverlay = yamlFormat.generate "omp-nix-overlay.yml" {
    tools = {
      # Expose every enabled tool top-level (callable by name, e.g.
      # inspect_image) instead of mounting discoverable tools under xd://
      # device URLs. Trade-off: all tool schemas ship on every request.
      xdev = false;
    };

    # Load the context image-pruner extension in every session. It keeps only
    # the most-recent N image blocks per request (env OMP_MAX_CONTEXT_IMAGES,
    # default 10) so a long session never trips Anthropic's stricter 2000px
    # per-image cap that applies once a request carries more than 20 images.
    extensions = [ "${./prune-context-images.js}" ];
  };
in
{
  home.sessionVariables = {
    PI_CONFIG_FILES = "${configOverlay}";
  };
}
