{
  pkgs,
  lib,
  isWsl,
  config,
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

  # On the WSL, point omp's `/collab` at the self-hosted tailnet relay (the
  # omp-collab module), so live session sharing never touches the public
  # my.omp.sh. The relay + guest client live on the WSL's own tailnet node, so
  # the URL is that node's MagicDNS name on port 8443. Derived at activation
  # (not hardcoded) to keep the private tailnet name out of this public repo,
  # and written to a file that rides in PI_CONFIG_FILES. If tailscale is down,
  # the file is empty and omp falls back to its default relay.
  collabOverlay = "${config.home.homeDirectory}/.config/omp/collab-overlay.yml";
in
{
  home.sessionVariables.PI_CONFIG_FILES =
    "${configOverlay}" + lib.optionalString isWsl ":${collabOverlay}";

  home.activation = lib.mkIf isWsl {
    ompCollabOverlay = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      name="$(${pkgs.tailscale}/bin/tailscale status --json 2>/dev/null \
        | ${pkgs.jq}/bin/jq -r '(.Self.DNSName // "") | rtrimstr(".")' || true)"
      mkdir -p "$(dirname "${collabOverlay}")"
      if [ -n "$name" ]; then
        printf 'collab:\n  relayUrl: wss://%s:8443\n  webUrl: https://%s:8443\n' \
          "$name" "$name" > "${collabOverlay}"
      else
        printf '{}\n' > "${collabOverlay}"
      fi
    '';
  };
}
