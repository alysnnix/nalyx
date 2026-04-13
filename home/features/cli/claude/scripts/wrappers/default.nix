# Main claude wrapper — parses flags and dispatches to appropriate handler.
# Profiles (--work, etc.) use separate config dirs with shared settings via symlinks.
# Modifiers (--minimax, --openrouter, --litellm, --english) compose with each other and profiles.
# Profile flags and modifier cases are auto-generated from profiles.nix.
{
  pkgs,
  lib,
  profiles,
}:
let
  jq = "${pkgs.jq}/bin/jq";

  profileCases = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: _: "        --${name}) profile=\"${name}\" ;;") profiles
  );
in
''
    : ''${NALYX_DIR:=$HOME/nalyx}

    ${import ./cc.nix}
    ${import ./cc-rebuild.nix}

    # Ensure a profile dir has shared config symlinked from personal.
    # If Claude replaced a symlink (atomic write), merge changes back first.
    _claude_sync_profile() {
      local profile_dir="$HOME/.claude/accounts/$1"
      mkdir -p "$profile_dir"

      for f in settings.json settings.local.json; do
        local target="$HOME/.claude/$f"
        local link="$profile_dir/$f"
        if [ -f "$target" ]; then
          if [ -f "$link" ] && [ ! -L "$link" ]; then
            ${jq} -s '.[0] * .[1]' "$target" "$link" > "$target.tmp" \
              && mv "$target.tmp" "$target"
            rm "$link"
          fi
          [ ! -e "$link" ] && ln -s "$target" "$link"
        fi
      done

      for d in skills plugins; do
        local target="$HOME/.claude/$d"
        local link="$profile_dir/$d"
        if [ -d "$target" ]; then
          [ -d "$link" ] && [ ! -L "$link" ] && rm -rf "$link"
          [ ! -e "$link" ] && ln -s "$target" "$link"
        fi
      done
    }

    claude() {
      local profile=""
      local minimax=0 openrouter=0 litellm=0 english=0
      local remaining_args=()

      for arg in "$@"; do
        case "$arg" in
  ${profileCases}
          --minimax) minimax=1 ;;
          --openrouter) openrouter=1 ;;
          --litellm) litellm=1 ;;
          --english) english=1 ;;
          *) remaining_args+=("$arg") ;;
        esac
      done

      if (( minimax + openrouter + litellm > 1 )); then
        echo "Error: --minimax, --openrouter, and --litellm are mutually exclusive"
        return 1
      fi

      local -a extra_env=()
      local -a extra_args=()

      # Profile: separate config dir with shared settings via symlinks
      if [[ -n "$profile" ]]; then
        _claude_sync_profile "$profile"
        extra_env+=("CLAUDE_CONFIG_DIR=$HOME/.claude/accounts/$profile")
        extra_env+=("CLAUDE_PROFILE=$profile")

        local prompt_file="$HOME/.claude/accounts/$profile/.system-prompt"
        if [[ -f "$prompt_file" ]]; then
          extra_args+=(--append-system-prompt "$(cat "$prompt_file")")
        fi
      fi

      # Provider modifiers
      if (( minimax )); then
  ${import ./minimax.nix}
      fi
      if (( openrouter )); then
  ${import ./openrouter.nix}
      fi
      if (( litellm )); then
  ${import ./litellm.nix}
      fi

      # Behavior modifiers
      if (( english )); then
  ${import ./english.nix}
      fi

      # Execute in subshell to isolate env changes
      (
        for e in "''${extra_env[@]}"; do export "$e"; done
        command claude "''${extra_args[@]}" "''${remaining_args[@]}"
      )
    }
''
