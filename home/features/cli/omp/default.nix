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

  # Shared with modules/services/paseo.nix too, for the same reason: the
  # derived `omp-frontend` provider there hands one of these to every session
  # it launches. See the header of ./persona-overlays.nix.
  personaOverlays = import ./persona-overlays.nix { inherit pkgs lib; };

  healClaudePlugins = import ./heal-claude-plugins.nix { inherit pkgs; };
in
{
  home.packages = [ healClaudePlugins ];

  home.file =
    {
      # The frontend persona. OMP discovers user task agents from
      # ~/.omp/agent/agents/*.md, and this one is the only consumer of the
      # skills marked `persona = "frontend"` in ../agent-skills/sources.nix:
      # they carry `hide: true`, so they stay out of every other session's
      # prompt and reach this agent through its `autoloadSkills` frontmatter,
      # which resolves against the parent session's discovered skills (hidden
      # ones included).
      #
      # Dispatch it with the task tool (`agent: "frontend-builder"`), or from
      # the Paseo side by launching a worker on the `Frontend` profile, which
      # runs the derived `omp-frontend` provider (modules/services/paseo.nix).
      ".omp/agent/agents/frontend-builder.md".source = ./agents/frontend-builder.md;
    }
    # The persona overlays, at a path a human can type. Deliberately absent
    # from PI_CONFIG_FILES below: an overlay that is always loaded is not a
    # persona, it is just more prompt. A terminal session opts in per launch,
    # `PI_CONFIG_FILES="$PI_CONFIG_FILES:$HOME/.config/omp/persona-frontend.yml" omp`.
    // lib.mapAttrs' (
      persona: overlay:
      lib.nameValuePair ".config/omp/persona-${persona}.yml" { source = overlay; }
    ) personaOverlays;

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
