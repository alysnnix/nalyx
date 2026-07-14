#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
switch - build the NixOS system from the nalyx flake

Usage:
  switch [host] [--no-main]

Arguments:
  host         host to build (default: current hostname)

Options:
  --no-main    pull the current branch instead of switching to main
  -h, --help   show this help

Examples:
  switch                 # switch to main, pull, rebuild current host
  switch wsl             # switch to main, pull, rebuild the wsl host
  switch --no-main       # stay on current branch, pull, rebuild
  switch wsl --no-main
EOF
}

HOST="$(hostname)"
NO_MAIN=0
for arg in "$@"; do
  case "$arg" in
    --no-main) NO_MAIN=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) HOST="$arg" ;;
  esac
done

FLAKE_DIR="$HOME/nalyx"
PRIVATE_DIR="$FLAKE_DIR/.private/nalyx-private"

echo "Rodando update do sistema..."
echo "  flake: $FLAKE_DIR"
echo "  host:  $HOST"

ORIGINAL_BRANCH=""
STASHED=0

restore_state() {
  if [ -n "$ORIGINAL_BRANCH" ]; then
    if git -C "$FLAKE_DIR" checkout "$ORIGINAL_BRANCH" 2>/dev/null; then
      echo "  branch: returned to $ORIGINAL_BRANCH"
    else
      echo "  branch: failed to return to $ORIGINAL_BRANCH"
    fi
  fi
  if [ "$STASHED" -eq 1 ]; then
    if git -C "$FLAKE_DIR" stash pop 2>/dev/null; then
      echo "  stash: restored local changes"
    else
      echo "  stash: failed to restore, check 'git stash list'"
    fi
  fi
}

if [ "$NO_MAIN" -eq 0 ]; then
  CURRENT_BRANCH="$(git -C "$FLAKE_DIR" branch --show-current)"
  if [ "$CURRENT_BRANCH" = "main" ]; then
    echo "  branch: already on main"
  else
    if [ -n "$(git -C "$FLAKE_DIR" status --porcelain)" ]; then
      git -C "$FLAKE_DIR" stash push -u -m "switch: auto-stash before main"
      STASHED=1
      echo "  stash: saved local changes from $CURRENT_BRANCH"
    fi
    if git -C "$FLAKE_DIR" checkout main 2>/dev/null; then
      ORIGINAL_BRANCH="$CURRENT_BRANCH"
      trap restore_state EXIT
      echo "  branch: switched to main (from $CURRENT_BRANCH)"
    else
      echo "  branch: checkout main failed, staying on $CURRENT_BRANCH"
      if [ "$STASHED" -eq 1 ]; then
        git -C "$FLAKE_DIR" stash pop 2>/dev/null && STASHED=0
        echo "  stash: restored local changes"
      fi
    fi
  fi
else
  echo "  branch: --no-main, staying on $(git -C "$FLAKE_DIR" branch --show-current)"
fi

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

echo "  pruning old generations (keeping last 5)..."
sudo nix-env --profile /nix/var/nix/profiles/system --delete-generations +5
