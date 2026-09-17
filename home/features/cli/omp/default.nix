{
  pkgs,
  lib,
  isWsl,
  config,
  ...
}:
let
  # Shared with modules/services/paseo.nix, which needs the same overlay in the
  # daemon's service environment: a home-manager session variable never reaches
  # a system service. See the header of that file.
  configOverlay = import ./config-overlay.nix { inherit pkgs; };

  # On the WSL, point omp's `/collab` at the self-hosted tailnet relay (the
  # omp-collab module), so live session sharing never touches the public
  # my.omp.sh. The relay + guest client live on the WSL's own tailnet node, so
  # the URL is that node's MagicDNS name. Derived at activation
  # (not hardcoded) to keep the private tailnet name out of this public repo,
  # and written to a file that rides in PI_CONFIG_FILES. Written only when a
  # tailscale name is available; a previously-good overlay is never clobbered
  # if tailscale is momentarily down (e.g. at boot), so it survives cold boots.
  collabOverlay = "${config.home.homeDirectory}/.config/omp/collab-overlay.yml";

  healClaudePlugins = import ./heal-claude-plugins.nix { inherit pkgs; };
in
{
  home.packages = [ healClaudePlugins ];

  home.sessionVariables.PI_CONFIG_FILES =
    "${configOverlay}" + lib.optionalString isWsl ":${collabOverlay}";

  home.activation = lib.mkMerge [
    {
      # Runs on every switch, and the private `omp` shell wrapper runs it again
      # per launch: Claude Code can invalidate its own plugin paths at any time,
      # not only between rebuilds.
      ompHealClaudePlugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        ${healClaudePlugins}/bin/omp-heal-claude-plugins || true
      '';
    }

    (lib.mkIf isWsl {
      ompCollabOverlay = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        name="$(${pkgs.tailscale}/bin/tailscale status --json 2>/dev/null \
          | ${pkgs.jq}/bin/jq -r '(.Self.DNSName // "") | rtrimstr(".")' || true)"
        mkdir -p "$(dirname "${collabOverlay}")"
        if [ -n "$name" ]; then
          printf 'collab:\n  relayUrl: wss://%s\n  webUrl: https://%s\n' \
            "$name" "$name" > "${collabOverlay}"
        elif [ ! -e "${collabOverlay}" ]; then
          printf '{}\n' > "${collabOverlay}"
        fi
      '';
    })
  ];
}
