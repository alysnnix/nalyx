# cc-rebuild function — rebuild the Docker container image.
''
  cc-rebuild() {
    echo "🔨 Rebuilding claude container…"
    docker rmi claude-code-container:latest 2>/dev/null || true
    nix build "$NALYX_DIR#claude-container" --print-out-paths \
      | xargs docker load \
      && echo "✅ Container rebuilt!"
  }
''
