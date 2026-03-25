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
PRIVATE_DIR="$FLAKE_DIR/../nalyx-private"

echo "Rodando update do sistema..."
echo "  flake: $FLAKE_DIR"
echo "  host:  $HOST"

EXTRA_ARGS=()
if [ -d "$PRIVATE_DIR" ] && [ -f "$PRIVATE_DIR/vars-override.nix" ]; then
  echo "  private: $PRIVATE_DIR"
  EXTRA_ARGS+=(--override-input private "path:$PRIVATE_DIR")
else
  echo "  private: (nao encontrado, usando defaults)"
fi

sudo nixos-rebuild switch --flake "$FLAKE_DIR#$HOST" "${EXTRA_ARGS[@]}"
