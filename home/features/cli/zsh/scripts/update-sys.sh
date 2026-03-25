#!/bin/bash
set -euo pipefail

HOST="${1:-$(hostname)}"

find_flake_dir() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    [ -f "$dir/flake.nix" ] && echo "$dir" && return
    dir=$(dirname "$dir")
  done
  echo "$HOME/nalyx"
}

FLAKE_DIR=$(find_flake_dir)
PRIVATE_DIR="$FLAKE_DIR/.private/nalyx-private"

echo "Rodando update do sistema..."
echo "  flake: $FLAKE_DIR"
echo "  host:  $HOST"

PRIVATE_REPO="git@github.com:alysnnix/nalyx-private.git"

EXTRA_ARGS=()
if [ -d "$PRIVATE_DIR" ] && [ -f "$PRIVATE_DIR/vars-override.nix" ]; then
  echo "  private: $PRIVATE_DIR"
  EXTRA_ARGS+=(--override-input private "path:$PRIVATE_DIR")
elif ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new git@github.com 2>/dev/null; [ $? -eq 1 ]; then
  echo "  private: cloning $PRIVATE_REPO..."
  mkdir -p "$(dirname "$PRIVATE_DIR")"
  git clone "$PRIVATE_REPO" "$PRIVATE_DIR"
  if [ -f "$PRIVATE_DIR/vars-override.nix" ]; then
    echo "  private: $PRIVATE_DIR"
    EXTRA_ARGS+=(--override-input private "path:$PRIVATE_DIR")
  else
    echo "  private: cloned but vars-override.nix not found, using defaults"
  fi
else
  echo "  private: (not found, no SSH access to GitHub, using defaults)"
fi

sudo nixos-rebuild switch --flake "$FLAKE_DIR#$HOST" "${EXTRA_ARGS[@]}"
