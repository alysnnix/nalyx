#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
switch - build the system from the nalyx flake

On NixOS this rebuilds the whole system. Anywhere else it activates the
homeConfiguration of the same name, since the system layer belongs to the
distro (Seazone's managed Ubuntu, Ubuntu WSL) and nix owns the userland only.

Usage:
  switch [target] [--no-main]

Arguments:
  target       host or home profile to build (default: current hostname)

Options:
  --no-main    pull the current branch instead of switching to main
  -h, --help   show this help

Examples:
  switch                 # switch to main, pull, rebuild current host
  switch wsl             # switch to main, pull, rebuild the wsl host
  switch szn             # activate the Seazone terminal-only home profile
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

# Per-repo state so both checkouts can be put back exactly as they were.
NALYX_BRANCH=""
NALYX_STASHED=0
PRIVATE_BRANCH=""
PRIVATE_STASHED=0

# Restore one repo: branch first, then the stash, so the pop lands on the same
# tree it was taken from.
# shellcheck disable=SC2329  # invoked from restore_state, which the EXIT trap calls
restore_repo() {
  local dir="$1" label="$2" branch="$3" stashed="$4"
  [ -d "$dir/.git" ] || return 0
  if [ -n "$branch" ]; then
    if git -C "$dir" checkout --quiet "$branch"; then
      echo "  $label: returned to $branch"
    else
      echo "  $label: failed to return to $branch"
    fi
  fi
  if [ "$stashed" -eq 1 ]; then
    if git -C "$dir" stash pop --quiet; then
      echo "  $label: restored local changes"
    else
      echo "  $label: failed to restore stash, check 'git stash list'"
    fi
  fi
}

# shellcheck disable=SC2329  # invoked indirectly via `trap restore_state EXIT`
restore_state() {
  restore_repo "$FLAKE_DIR" nalyx "$NALYX_BRANCH" "$NALYX_STASHED"
  restore_repo "$PRIVATE_DIR" private "$PRIVATE_BRANCH" "$PRIVATE_STASHED"
  # Idempotent on purpose: this also runs from the EXIT trap, and a second
  # `stash pop` would pop an unrelated entry off the stack.
  NALYX_BRANCH=""
  NALYX_STASHED=0
  PRIVATE_BRANCH=""
  PRIVATE_STASHED=0
}

# Move a repo to main so the build uses the shared revision, reporting back
# through namerefs what had to be changed. Both repos need this: the private one
# is injected by path, so leaving it on a feature branch builds that branch's
# secrets and peer addresses while the public side builds main.
enter_main() {
  local dir="$1" label="$2"
  local -n branch_out="$3" stashed_out="$4"
  local current
  current="$(git -C "$dir" branch --show-current 2>/dev/null)" || return 0
  # Empty means detached HEAD; do not touch it.
  [ -n "$current" ] || return 0
  if [ "$current" = "main" ]; then
    echo "  $label: already on main"
    return 0
  fi
  if [ -n "$(git -C "$dir" status --porcelain)" ]; then
    if git -C "$dir" stash push -u -m "switch: auto-stash before main" >/dev/null; then
      stashed_out=1
      echo "  $label: stashed local changes from $current"
    else
      echo "  $label: stash failed, staying on $current"
      return 0
    fi
  fi
  if git -C "$dir" checkout --quiet main; then
    # shellcheck disable=SC2034  # nameref: writes to the caller's variable
    branch_out="$current"
    echo "  $label: switched to main (from $current)"
  else
    echo "  $label: checkout main failed, staying on $current"
    if [ "$stashed_out" -eq 1 ]; then
      git -C "$dir" stash pop --quiet && stashed_out=0
      echo "  $label: restored local changes"
    fi
  fi
}

if [ "$NO_MAIN" -eq 0 ]; then
  # Armed before touching anything so a failure halfway through still restores.
  trap restore_state EXIT
  enter_main "$FLAKE_DIR" nalyx NALYX_BRANCH NALYX_STASHED
  if [ -d "$PRIVATE_DIR/.git" ]; then
    enter_main "$PRIVATE_DIR" private PRIVATE_BRANCH PRIVATE_STASHED
  fi
else
  echo "  branch: --no-main, staying on nalyx=$(git -C "$FLAKE_DIR" branch --show-current)$([ -d "$PRIVATE_DIR/.git" ] && echo " private=$(git -C "$PRIVATE_DIR" branch --show-current)")"
fi

echo "  pulling repos in parallel..."
# Keep stderr: a swallowed git error is what makes a stale build look like a
# successful one.
git -C "$FLAKE_DIR" pull --ff-only >/dev/null &
PID_NALYX=$!

# llm-agents packages (claude-code, codex, omp, gemini-cli) are prebuilt on
# cache.numtide.com. modules/core declares this substituter, but nixos-rebuild
# builds against the ACTIVE /etc/nix/nix.conf, so a host whose running config
# predates that line (or a fresh install) compiles the codex and omp Rust
# workspaces from source on this very switch. root is a trusted user, so passing
# the substituter on the CLI makes the cache reachable regardless of nix.conf
# state, closing that bootstrap gap.
EXTRA_ARGS=(
  --option extra-substituters "https://cache.numtide.com"
  --option extra-trusted-public-keys "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
)
if [ -d "$PRIVATE_DIR" ] && [ -f "$PRIVATE_DIR/flake.nix" ]; then
  git -C "$PRIVATE_DIR" pull --ff-only >/dev/null &
  PID_PRIVATE=$!
  PRIVATE_PULL_OK=1
  wait "$PID_PRIVATE" || PRIVATE_PULL_OK=0
  echo "  private: $PRIVATE_DIR"

  # The private repo carries secrets and peer addresses, and it is injected by
  # path, so a failed pull silently builds the previous revision. That drift is
  # invisible until something downstream breaks (a Syncthing peer that no longer
  # resolves, a rotated secret that never lands). Fail loudly instead, but only
  # when the local checkout is actually behind: a dirty tree with no incoming
  # commits is the normal state right after editing secrets locally.
  if [ "$PRIVATE_PULL_OK" -eq 0 ]; then
    git -C "$PRIVATE_DIR" fetch --quiet origin 2>/dev/null || true
    BEHIND="$(git -C "$PRIVATE_DIR" rev-list --count 'HEAD..@{upstream}' 2>/dev/null || echo 0)"
    if [ "$BEHIND" -gt 0 ]; then
      echo "  private: ERROR pull failed and the checkout is $BEHIND commit(s) behind"
      echo "  private: building now would use a stale private config; aborting."
      echo "  private: resolve it in $PRIVATE_DIR (commit, stash or reset), then rerun"
      # No explicit restore_state here: exit fires the EXIT trap, which does it.
      exit 1
    fi
    echo "  private: warning, pull failed but nothing to pull (dirty tree?), using local"
  fi

  EXTRA_ARGS+=(--override-input private "path:$PRIVATE_DIR")
else
  # Override with the placeholder rather than leaving the input alone. The
  # input is declared as git+ssh to the personal private repo, so without an
  # override nix tries to fetch it, and on a host that has no business holding
  # that key (the Seazone laptop) the build dies on "Permission denied
  # (publickey)" instead of falling back to public defaults. Same placeholder
  # CI uses, and it outputs {} so privateHmModules resolves to an empty list.
  echo "  private: (not found, using ci/empty-private placeholder)"
  EXTRA_ARGS+=(--override-input private "path:$FLAKE_DIR/ci/empty-private")
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

# nixos-rebuild spawns `nix build`, which opens a descriptor per store path it
# touches. The session soft limit is 1024 (systemd DefaultLimitNOFILE), so on a
# large closure the client dies with `opening directory "/nix/store": Too many
# open files`. modules/core raises it via pam_limits, but only for sessions
# opened after that generation is active, so raise it here too: this makes the
# first switch on a fresh host work and keeps already-open sessions building.
SOFT_NOFILE=$(ulimit -Sn)
HARD_NOFILE=$(ulimit -Hn)
# Both are either an integer or "unlimited"; anything non-numeric is treated as
# "already big enough" so a surprising ulimit output can never abort the switch.
if [[ $SOFT_NOFILE =~ ^[0-9]+$ ]] && [ "$SOFT_NOFILE" -lt 65536 ]; then
  if [[ $HARD_NOFILE =~ ^[0-9]+$ ]] && [ "$HARD_NOFILE" -lt 65536 ]; then
    WANT_NOFILE=$HARD_NOFILE
  else
    WANT_NOFILE=65536
  fi
  if ulimit -Sn "$WANT_NOFILE" 2>/dev/null; then
    echo "  nofile: raised soft limit to $WANT_NOFILE"
  else
    echo "  nofile: warning, could not raise soft limit from $SOFT_NOFILE"
  fi
fi

# Do not abort on rebuild failure (e.g. exit 4 = switched with failed units):
# the prune below must always run, and the exit code is propagated at the end.
REBUILD_RC=0

# Only NixOS has a system to rebuild. Everywhere else (the Seazone Ubuntu
# laptop, Ubuntu WSL) the system layer belongs to the distro and nix owns the
# userland only, so the target is the homeConfiguration of the same name.
if [ -e /etc/NIXOS ]; then
  sudo nixos-rebuild switch --flake "$FLAKE_DIR#$HOST" "${EXTRA_ARGS[@]}" || REBUILD_RC=$?

  echo "  pruning old generations (keeping last 5)..."
  sudo nix-env --profile /nix/var/nix/profiles/system --delete-generations +5
else
  echo "  mode:  home-manager (not NixOS)"

  # home-manager only lands on PATH after the first activation, since it is the
  # profile itself that installs it. Bootstrap through the flake's own input so
  # the version never drifts from the one that built the config.
  HM=(home-manager)
  if ! command -v home-manager >/dev/null 2>&1; then
    echo "  bootstrap: home-manager not on PATH yet, running it from the flake input"
    HM=(nix run --inputs-from "$FLAKE_DIR" home-manager --)
  fi

  # -b: a standalone activation aborts when a real file already sits where a
  # symlink should go, which is the normal state on a distro that shipped its
  # own .zshrc. Renaming it is what makes the first switch survive.
  "${HM[@]}" switch --flake "$FLAKE_DIR#$HOST" -b "backup-$HOST" "${EXTRA_ARGS[@]}" ||
    REBUILD_RC=$?

  # expire-generations takes a timestamp, not a count, so this is by age rather
  # than by the last 5 the NixOS branch keeps. Guarded on PATH again because the
  # very first switch is what puts home-manager there.
  if command -v home-manager >/dev/null 2>&1; then
    echo "  pruning generations older than 5 days..."
    home-manager expire-generations "-5 days" || echo "  warning: expire-generations failed"
  fi
fi

# Refresh runtime-secret MCP tokens in ~/.claude.json. The
# home-manager activation only re-runs when its derivation changes, so a pure
# secret-value change would not propagate; sync explicitly on every switch.
if command -v sync-claude-mcps >/dev/null 2>&1; then
  echo "  syncing claude mcps..."
  sync-claude-mcps || echo "  warning: sync-claude-mcps failed"
fi

if [ "$REBUILD_RC" -ne 0 ]; then
  echo "  warning: nixos-rebuild exited with status $REBUILD_RC (check failed units above)"
fi
exit "$REBUILD_RC"
