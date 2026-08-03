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
  };
in
{
  home.sessionVariables = {
    PI_CONFIG_FILES = "${configOverlay}";
  };
}
