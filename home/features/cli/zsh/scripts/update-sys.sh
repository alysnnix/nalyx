#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
switch - build the system from the nalyx flake

On NixOS this rebuilds the whole system. Anywhere else it activates the
homeConfiguration of the same name, since the system layer belongs to the
distro (a managed work laptop, Ubuntu WSL) and nix owns the userland only.

Usage:
  switch [target] [--no-main]

Arguments:
  target       a host, a home profile, or a project name (default: hostname)

               A project name is the directory under .private/ with the
               `-private` suffix dropped, so a checkout at
               .private/szn-private is addressed as `szn`. Naming one selects
               the `wrk` profile with that layer plugged in, which is how one
               generic profile serves several jobs without this repo ever
               naming any of them.

               With exactly one project layer cloned the name is optional;
               with several it is required, because a flake takes one layer.

Options:
  --no-main    pull the current branch instead of switching to main
  -h, --help   show this help

Examples:
  switch                 # switch to main, pull, rebuild current host
  switch wsl             # switch to main, pull, rebuild the wsl host
  switch szn             # the wrk profile with the szn layer
  switch wrk             # the wrk profile with whatever single layer is cloned
  switch --no-main       # stay on current branch, pull, rebuild
  switch wsl --no-main
EOF
}

# TARGET is what the user actually typed, kept apart from HOST so the project
# layer resolution below can tell "no argument" from "argument that happens to
# equal the hostname".
TARGET=""
PROJECT=""
NO_MAIN=0
positional=()
for arg in "$@"; do
  case "$arg" in
    --no-main) NO_MAIN=1 ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) positional+=("$arg") ;;
  esac
done
# Two positionals mean "this target, with that project layer", which is the
# only way to be unambiguous when several layers are cloned and the target is
# a NixOS host: those hosts carry the layer too, so the pick matters there.
TARGET="${positional[0]:-}"
PROJECT="${positional[1]:-}"
HOST="${TARGET:-$(hostname)}"

FLAKE_DIR="$HOME/nalyx"
# Personal layer: a fixed name, because there is only ever one of it.
PRIVATE_DIR="$FLAKE_DIR/.private/nalyx-private"

# Project layer: discovered rather than named, because its name is an
# employer's and this script lives in a public repo. Any flake under .private/
# that is not the personal one qualifies, so plugging a job in means cloning
# its repo and nothing else, and unplugging means deleting the clone. Which
# layers a machine gets is therefore a property of the machine, which is the
# point: the work laptop simply never clones the personal one.
#
# The .private/notes vault is skipped for free, since it carries no flake.nix.
WRK_DIR=""
wrk_found=()
wrk_names=()
for candidate in "$FLAKE_DIR"/.private/*/; do
  candidate="${candidate%/}"
  [ -f "$candidate/flake.nix" ] || continue
  [ "$candidate" = "$PRIVATE_DIR" ] && continue
  wrk_found+=("$candidate")
  # `szn-private` is addressed as `szn`, so the target you type is the job, not
  # the repo. The suffix is a naming convention, not something this has to know.
  wrk_names+=("$(basename "${candidate%-private}")")
done

# Resolve the target the user asked for against those names, so `switch szn`
# means "the wrk profile, with the szn layer plugged in".
#
# The name is matched here rather than being a flake output on purpose. An
# output called `szn` would put an employer's name back into the public flake,
# which is the one thing this whole layout exists to avoid. A string the user
# types and a directory on their own disk carry no such cost, so the naming
# lives entirely on the machine.
# Look up a project name among the cloned layers. Prints the path, or nothing.
find_layer() {
  local want="$1" i
  for i in "${!wrk_names[@]}"; do
    if [ "${wrk_names[$i]}" = "$want" ]; then
      printf '%s' "${wrk_found[$i]}"
      return 0
    fi
  done
  return 1
}

layer_list() {
  local i
  for i in "${!wrk_found[@]}"; do
    echo "             ${wrk_names[$i]}  (${wrk_found[$i]})" >&2
  done
}

if [ -n "$PROJECT" ]; then
  # `switch <target> <project>`: explicit on both axes.
  if ! WRK_DIR="$(find_layer "$PROJECT")"; then
    echo "  wrk:     ERROR no project layer named '$PROJECT' under .private/" >&2
    if [ "${#wrk_found[@]}" -gt 0 ]; then
      echo "  wrk:     cloned layers are:" >&2
      layer_list
    else
      echo "  wrk:     nothing is cloned there yet" >&2
    fi
    exit 1
  fi
elif [ -n "$TARGET" ] && WRK_DIR="$(find_layer "$TARGET")"; then
  # `switch <project>`: the target names a layer, so it means the generic work
  # profile with that layer. The flake only ever has the one such profile.
  HOST="wrk"
elif [ "${#wrk_found[@]}" -gt 1 ]; then
  # Refuse rather than guess. A flake takes one `wrk` input, and a NixOS host
  # carries the layer as well, so with several cloned there is no correct pick
  # and choosing silently would build the wrong job's secrets and identity.
  WRK_DIR=""
  echo "  wrk:     ERROR more than one project layer is cloned:" >&2
  layer_list
  echo "  wrk:     name it, e.g. switch ${wrk_names[0]}, or switch $HOST ${wrk_names[0]}" >&2
  exit 1
elif [ "${#wrk_found[@]}" -eq 1 ]; then
  WRK_DIR="${wrk_found[0]}"
else
  WRK_DIR=""
fi

echo "Rodando update do sistema..."
echo "  flake: $FLAKE_DIR"
echo "  host:  $HOST"

# Per-repo state, keyed by path so adding a layer needs no new variables. The
# ordered arrays exist only so the reporting comes out in a stable order.
declare -A REPO_BRANCH=() REPO_STASHED=()
declare -a REPO_PATHS=() REPO_LABELS=()

track_repo() {
  local dir="$1" label="$2"
  [ -d "$dir/.git" ] || return 0
  REPO_PATHS+=("$dir")
  REPO_LABELS+=("$label")
  REPO_BRANCH["$dir"]=""
  REPO_STASHED["$dir"]=0
}

# Every repo whose checkout feeds the build. All of them get the same handling,
# for the same reason: each is injected by path, so a feature branch or a stale
# tree silently builds a revision nobody asked for.
track_repo "$FLAKE_DIR" nalyx
track_repo "$PRIVATE_DIR" private
if [ -n "$WRK_DIR" ]; then
  track_repo "$WRK_DIR" wrk
fi

# Restore one repo: branch first, then the stash, so the pop lands on the same
# tree it was taken from. Clears its own state afterwards, because this also
# runs from the EXIT trap and a second `stash pop` would take an unrelated
# entry off the stack.
# shellcheck disable=SC2329  # invoked from restore_state, which the EXIT trap calls
restore_repo() {
  local dir="$1" label="$2"
  [ -d "$dir/.git" ] || return 0
  local branch="${REPO_BRANCH[$dir]:-}" stashed="${REPO_STASHED[$dir]:-0}"
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
  REPO_BRANCH["$dir"]=""
  REPO_STASHED["$dir"]=0
}

# shellcheck disable=SC2329  # invoked indirectly via `trap restore_state EXIT`
restore_state() {
  local i
  for i in "${!REPO_PATHS[@]}"; do
    restore_repo "${REPO_PATHS[$i]}" "${REPO_LABELS[$i]}"
  done
}

# Move a repo to main so the build uses the shared revision, recording what had
# to be changed so the EXIT trap can undo exactly that.
enter_main() {
  local dir="$1" label="$2"
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
      REPO_STASHED["$dir"]=1
      echo "  $label: stashed local changes from $current"
    else
      echo "  $label: stash failed, staying on $current"
      return 0
    fi
  fi
  if git -C "$dir" checkout --quiet main; then
    REPO_BRANCH["$dir"]="$current"
    echo "  $label: switched to main (from $current)"
  else
    echo "  $label: checkout main failed, staying on $current"
    if [ "${REPO_STASHED[$dir]}" -eq 1 ]; then
      git -C "$dir" stash pop --quiet && REPO_STASHED["$dir"]=0
      echo "  $label: restored local changes"
    fi
  fi
}

# A layer injected by path silently builds its previous revision when the pull
# fails, and that drift is invisible until something downstream breaks (a peer
# that no longer resolves, a rotated secret that never lands). Fail loudly, but
# only when the checkout is actually behind: a dirty tree with nothing incoming
# is the normal state right after editing secrets locally.
require_current() {
  local dir="$1" label="$2" behind
  git -C "$dir" fetch --quiet origin 2>/dev/null || true
  behind="$(git -C "$dir" rev-list --count 'HEAD..@{upstream}' 2>/dev/null || echo 0)"
  if [ "$behind" -gt 0 ]; then
    echo "  $label: ERROR pull failed and the checkout is $behind commit(s) behind" >&2
    echo "  $label: building now would use a stale layer; aborting." >&2
    echo "  $label: resolve it in $dir (commit, stash or reset), then rerun" >&2
    # No explicit restore_state here: exit fires the EXIT trap, which does it.
    exit 1
  fi
  echo "  $label: warning, pull failed but nothing to pull (dirty tree?), using local"
}

if [ "$NO_MAIN" -eq 0 ]; then
  # Armed before touching anything so a failure halfway through still restores.
  trap restore_state EXIT
  for i in "${!REPO_PATHS[@]}"; do
    enter_main "${REPO_PATHS[$i]}" "${REPO_LABELS[$i]}"
  done
else
  branches=""
  for i in "${!REPO_PATHS[@]}"; do
    branches+=" ${REPO_LABELS[$i]}=$(git -C "${REPO_PATHS[$i]}" branch --show-current)"
  done
  echo "  branch: --no-main, staying on$branches"
fi

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

echo "  pulling repos in parallel..."
# Keep stderr: a swallowed git error is what makes a stale build look like a
# successful one.
declare -A PULL_PID=()
for i in "${!REPO_PATHS[@]}"; do
  git -C "${REPO_PATHS[$i]}" pull --ff-only >/dev/null &
  PULL_PID["${REPO_PATHS[$i]}"]=$!
done

# nalyx itself only warns: it holds no secret, and a stale public tree shows up
# in `git log` the moment anyone looks.
if [ -n "${PULL_PID[$FLAKE_DIR]:-}" ]; then
  wait "${PULL_PID[$FLAKE_DIR]}" || echo "  nalyx: pull failed, using local version"
fi

if [ -n "${PULL_PID[$PRIVATE_DIR]:-}" ]; then
  echo "  private: $PRIVATE_DIR"
  wait "${PULL_PID[$PRIVATE_DIR]}" || require_current "$PRIVATE_DIR" private
  EXTRA_ARGS+=(--override-input private "path:$PRIVATE_DIR")
else
  # Override with the placeholder rather than leaving the input alone. The
  # input is declared as git+ssh to the personal private repo, so without an
  # override nix tries to fetch it, and on a host that has no business holding
  # that key (a managed work laptop) the build dies on "Permission denied
  # (publickey)" instead of falling back to public defaults. Same placeholder
  # CI uses, and it outputs {} so privateHmModules resolves to an empty list.
  echo "  private: (not found, using ci/empty-private placeholder)"
  EXTRA_ARGS+=(--override-input private "path:$FLAKE_DIR/ci/empty-private")
fi

# The override is the only place the project repo is ever mentioned, and it is
# computed on the machine, so the public flake keeps its placeholder default and
# never records a company name in flake.nix or flake.lock.
# `-n "$WRK_DIR"` first, and not just for tidiness: with no project layer
# cloned, WRK_DIR is the empty string, and bash treats an empty subscript on an
# associative array as an error rather than a miss ("bad array subscript"),
# which `set -u` at the top turns into an abort. The `:-` default does not help,
# because the failure is the subscript itself, not the lookup.
#
# Only this one of the three needs the guard: FLAKE_DIR and PRIVATE_DIR are
# always path strings, even when the directory is absent. And it went unseen
# because every host that gets switched often has exactly one layer cloned; the
# homelab is the only one with none, so it was the only one that could hit it.
# `track_repo` above already guards the same variable the same way.
if [ -n "$WRK_DIR" ] && [ -n "${PULL_PID[$WRK_DIR]:-}" ]; then
  echo "  wrk:     $WRK_DIR"
  wait "${PULL_PID[$WRK_DIR]}" || require_current "$WRK_DIR" wrk
  EXTRA_ARGS+=(--override-input wrk "path:$WRK_DIR")
else
  echo "  wrk:     (none cloned, no project layer)"
fi

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

# Only NixOS has a system to rebuild. Everywhere else (a managed Ubuntu work
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

# Grant the nix-built bwrap the AppArmor permission to unshare a user namespace,
# without which every buildFHSEnv package (composio) dies on "setting up uid
# map: Permission denied". It writes to /etc/apparmor.d, so home-manager cannot
# do it from an activation script: that runs unprivileged, and a sudo prompt
# mid-activation would hang a non-interactive rebuild.
#
# Here instead, where a prompt is expected anyway, and only ever on the hosts
# that carry the helper (the work profile). It returns early without touching
# sudo unless the profile is actually missing or stale, so the usual switch
# stays silent. Never fatal: the grant only gates the FHS packages, so a switch
# that could not install it is still a good generation.
if command -v wrk-bwrap-apparmor-setup >/dev/null 2>&1; then
  wrk-bwrap-apparmor-setup || echo "  warning: wrk-bwrap-apparmor-setup failed"
fi

# Point /run/opengl-driver at the drivers home-manager built, without which no
# nix-built GL app can open a window off NixOS. Same reasoning as the grant
# above: root-only, so activation can only warn about it, and this returns
# without sudo unless the link is missing or stale. Never fatal, a generation
# with no GL is still a good generation for everything headless.
if command -v wrk-gpu-setup >/dev/null 2>&1; then
  wrk-gpu-setup || echo "  warning: wrk-gpu-setup failed"
fi

if [ "$REBUILD_RC" -ne 0 ]; then
  echo "  warning: nixos-rebuild exited with status $REBUILD_RC (check failed units above)"
fi
exit "$REBUILD_RC"
