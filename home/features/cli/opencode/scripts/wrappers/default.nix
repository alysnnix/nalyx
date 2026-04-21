# Main opencode wrapper — parses flags and dispatches to appropriate handler.
# Profiles (--sec, etc.) use OPENCODE_CONFIG to point to separate config files.
# Modifiers (--minimax, --openrouter, --litellm, --english) compose with each other and profiles.
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
    _opencode_sync_profile() {
      local profile_dir="$HOME/.config/opencode/accounts/$1"
      local global_config="$HOME/.config/opencode/opencode.jsonc"
      mkdir -p "$profile_dir"

      local link="$profile_dir/opencode.jsonc"
      if [ -f "$global_config" ]; then
        if [ -f "$link" ] && [ ! -L "$link" ]; then
          ${jq} -s '.[0] * .[1]' "$global_config" "$link" > "$global_config.tmp" \
            && mv "$global_config.tmp" "$global_config"
          rm "$link"
        fi
        [ ! -e "$link" ] && ln -s "$global_config" "$link"
      fi
    }

    opencode() {
      local profile=""
      local minimax=0 openrouter=0 litellm=0 cc=0 english=0
      local remaining_args=()

      for arg in "$@"; do
        case "$arg" in
  ${profileCases}
          --minimax) minimax=1 ;;
          --openrouter) openrouter=1 ;;
          --litellm) litellm=1 ;;
          --cc) cc=1 ;;
          --english) english=1 ;;
          *) remaining_args+=("$arg") ;;
        esac
      done

      if (( minimax + openrouter + litellm + cc > 1 )); then
        echo "Error: --minimax, --openrouter, --litellm, and --cc are mutually exclusive"
        return 1
      fi

      local -a extra_env=()

      # Profile: separate config dir
      if [[ -n "$profile" ]]; then
        _opencode_sync_profile "$profile"
        extra_env+=("OPENCODE_CONFIG=$HOME/.config/opencode/accounts/$profile/opencode.jsonc")
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
      if (( cc )); then
  ${import ./cc.nix { inherit pkgs; }}
      fi

      # Behavior modifiers
      if (( english )); then
  ${import ./english.nix}
      fi

      # Execute in subshell to isolate env changes
      (
        for e in "''${extra_env[@]}"; do export "$e"; done
        command opencode "''${remaining_args[@]}"
      )
    }
''
