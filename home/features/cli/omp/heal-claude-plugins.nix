{ pkgs }:

# Repair dead `installPath` entries in Claude Code's plugin registry
# (~/.claude/plugins/installed_plugins.json), so omp keeps seeing the plugins
# Claude Code sees.
#
# Why this exists: the two agents disagree about how much that registry is
# trusted. Claude Code treats it as a hint. When the recorded install path is
# gone (its housekeeping prunes ~/.claude/plugins/cache, and a version bump
# changes the version-stamped directory name), it falls back to the marketplace
# checkout and rewrites the entry the next time it runs. omp does not: it reads
# installPath literally, and a root that does not exist contributes nothing, so
# every skill, agent, command and MCP server from that plugin silently vanishes
# from omp while Claude Code still has all of them.
#
# That is not hypothetical: it is exactly the state this script was written in,
# with eighteen enabled plugins pointing at a cache directory that no longer
# existed, and ~230 plugin skills missing from omp as a result.
#
# The repair is deliberately narrow. Only an entry whose installPath does not
# exist is touched, and only when the marketplace it came from still has a
# directory carrying a real `.claude-plugin/plugin.json`. A healthy registry is
# left byte for byte alone, so this is safe to run on every activation and
# before every omp launch.
pkgs.writeShellScriptBin "omp-heal-claude-plugins" ''
  set -u

  # Runs from a shell wrapper and from Nix activation, neither of which
  # guarantees a usable PATH.
  PATH=${
    pkgs.lib.makeBinPath [
      pkgs.coreutils
      pkgs.findutils
    ]
  }:$PATH
  jq=${pkgs.jq}/bin/jq

  registry="$HOME/.claude/plugins/installed_plugins.json"
  known="$HOME/.claude/plugins/known_marketplaces.json"

  [ -f "$registry" ] || exit 0

  tmp="$registry.omp-heal.tmp"
  cp "$registry" "$tmp" || exit 0
  changed=0

  # id, array index, recorded path, recorded version — one row per installed
  # entry. The index is needed because a plugin id maps to a list (user scope
  # plus project scopes).
  rows=$("$jq" -r '
    .plugins // {}
    | to_entries[]
    | .key as $id
    | .value
    | to_entries[]
    | [$id, (.key | tostring), (.value.installPath // ""), (.value.version // "")]
    | @tsv
  ' "$registry" 2>/dev/null) || { rm -f "$tmp"; exit 0; }

  while IFS=$'\t' read -r id idx path version; do
    [ -n "$id" ] || continue
    [ -d "$path" ] && continue

    plugin="''${id%@*}"
    marketplace="''${id##*@}"

    location=""
    if [ -f "$known" ]; then
      location=$("$jq" -r --arg m "$marketplace" '.[$m].installLocation // empty' "$known")
    fi

    # Two places a plugin can really live, in order of fidelity:
    #
    #   the download cache, keyed by version, which is what Claude Code
    #   installs for a plugin whose source is outside the marketplace repo
    #   (posthog, vercel, supabase...). A version bump leaves the old stamped
    #   directory name in the registry, so the newest sibling is the fallback.
    #
    #   the marketplace checkout, for plugins vendored in the marketplace repo
    #   itself, laid out as plugins/<name>, external_plugins/<name>, <name>, or
    #   a single plugin at the root.
    cache="$HOME/.claude/plugins/cache/$marketplace/$plugin"

    candidates=("$cache/$version")
    if [ -d "$cache" ]; then
      while IFS= read -r stamped; do
        candidates+=("$stamped")
      done < <(find "$cache" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null \
        | sort -rn | cut -d' ' -f2-)
    fi
    if [ -n "$location" ]; then
      candidates+=(
        "$location/plugins/$plugin"
        "$location/external_plugins/$plugin"
        "$location/$plugin"
        "$location"
      )
    fi

    # What makes a directory a plugin root: its manifest, one of the component
    # directories, or Claude Code's own `.in_use` install marker. Requiring the
    # manifest alone would reject the LSP plugins, which declare everything in
    # the marketplace file and ship no plugin.json of their own.
    repaired=""
    for candidate in "''${candidates[@]}"; do
      [ -d "$candidate" ] || continue
      for proof in .claude-plugin/plugin.json skills agents commands hooks .in_use; do
        if [ -e "$candidate/$proof" ]; then
          repaired="$candidate"
          break 2
        fi
      done
    done
    [ -n "$repaired" ] || continue

    if "$jq" --arg id "$id" --argjson i "$idx" --arg p "$repaired" \
      '.plugins[$id][$i].installPath = $p' "$tmp" > "$tmp.next"; then
      mv "$tmp.next" "$tmp"
      changed=1
      echo "omp-heal-claude-plugins: $id -> $repaired"
    else
      rm -f "$tmp.next"
    fi
  done <<< "$rows"

  if [ "$changed" = 1 ]; then
    mv "$tmp" "$registry"
  else
    rm -f "$tmp"
  fi
''
