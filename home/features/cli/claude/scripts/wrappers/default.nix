# Main claude wrapper — parses flags and dispatches to appropriate handler.
# Handles: --minimax, --english, or passthrough.
''
  # Root of the nalyx flake — override if you keep the repo elsewhere
  : ''${NALYX_DIR:=$HOME/nalyx}

  ${import ./cc.nix}
  ${import ./cc-rebuild.nix}

  # Claude Code wrapper — handles --minimax and --english flags.
  # All other arguments are passed through to the real claude binary.
  # NOTE: Uses subshell + export instead of inline VAR=value prefix because
  # zsh does not propagate inline assignments through the `command` builtin.
  claude() {
    local minimax=0 english=0
    local remaining_args=()

    for arg in "$@"; do
      case "$arg" in
        --minimax) minimax=1 ;;
        --english) english=1 ;;
        *) remaining_args+=("$arg") ;;
      esac
    done

    if (( minimax )); then
      ${import ./minimax.nix}
      _claude_minimax "''${remaining_args[@]}"
    elif (( english )); then
      ${import ./english.nix}
      _claude_english "''${remaining_args[@]}"
    else
      ${import ./passthrough.nix}
      _claude_passthrough "$@"
    fi
  }
''
