#!/bin/bash
set -euo pipefail

HOST="${1:-$(hostname)}"
FLAKE_DIR="$HOME/nalyx"
PRIVATE_DIR="$FLAKE_DIR/.private/nalyx-private"

echo "Rodando update do sistema..."
echo "  flake: $FLAKE_DIR"
echo "  host:  $HOST"

echo "  pulling repos in parallel..."
git -C "$FLAKE_DIR" pull --ff-only 2>/dev/null &
PID_NALYX=$!

EXTRA_ARGS=()
if [ -d "$PRIVATE_DIR" ] && [ -f "$PRIVATE_DIR/flake.nix" ]; then
  git -C "$PRIVATE_DIR" pull --ff-only 2>/dev/null &
  PID_PRIVATE=$!
  wait "$PID_PRIVATE" || echo "  private: pull failed, using local version"
  echo "  private: $PRIVATE_DIR"
  EXTRA_ARGS+=(--override-input private "path:$PRIVATE_DIR")
else
  echo "  private: (not found, using defaults)"
fi

wait "$PID_NALYX" || echo "  nalyx: pull failed, using local version"

# Clone notes vault (Obsidian) if available and not already cloned
NOTES_DIR="$FLAKE_DIR/.private/notes"
if [ ! -d "$NOTES_DIR" ] && [ -d "$PRIVATE_DIR" ]; then
  NOTES_REMOTE=$(git -C "$PRIVATE_DIR" remote get-url origin 2>/dev/null | sed 's|nalyx-private|notes|')
  if [ -n "$NOTES_REMOTE" ]; then
    echo "  notes: cloning..."
    git clone "$NOTES_REMOTE" "$NOTES_DIR" || echo "  notes: clone failed, skipping"
  fi
elif [ -d "$NOTES_DIR" ]; then
  echo "  notes: $NOTES_DIR"
fi

sudo nixos-rebuild switch --flake "$FLAKE_DIR#$HOST" "${EXTRA_ARGS[@]}"
