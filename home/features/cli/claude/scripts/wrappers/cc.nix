# cc function — run Claude Code inside a Nix-built Docker container.
''
  cc() {
    local image="claude-code-container:latest"

    if ! docker image inspect "$image" >/dev/null 2>&1; then
      echo "🐳 Building claude container from nix (first run)…"
      nix build "$NALYX_DIR#claude-container" --print-out-paths \
        | xargs docker load \
        && echo "✅ Image loaded."
    fi

    docker run --rm -it \
      -v "$(pwd):/workspace" \
      -v "$HOME/.claude:/home/claude/.claude" \
      -v "$HOME/.config/git:/home/claude/.config/git:ro" \
      -v "$HOME/.ssh:/home/claude/.ssh:ro" \
      -e ANTHROPIC_API_KEY \
      -w /workspace \
      "$image" \
      "$@"
  }
''
