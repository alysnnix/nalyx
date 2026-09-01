{ pkgs, lib }:

# The commit message convention, enforced instead of merely documented.
#
# The rule text lives in the agent rules and in .claude/CLAUDE.md, and agent
# CLIs still forget it: a rule read once at the top of a session is a rule that
# fades. A git hook does not fade. It runs on every commit, in every repo, for
# every tool that shells out to `git commit`, which is all of them.
#
# The logic lives in two binaries and the hook files are thin wrappers around
# them. That is not indirection for its own sake. A global `core.hooksPath`
# covers every repo right up to the first repo that sets its own
# core.hooksPath, which git gives precedence: husky does exactly that, pointing
# at `.husky/_`, and from that moment our hooks are silently gone. With the
# logic exposed on PATH, adopting the checks in such a repo is one line in its
# own hook (`exec git-commit-lint "$1"`) rather than a fork of this file.
#
# `git-hooks-doctor` exists so that the shadowing is loud rather than silent.
#
# The work splits deliberately between the two:
#
#   git-commit-trailer  adds the trailer, and NEVER fails a commit
#   git-commit-lint     validates the shape, and DOES fail a commit
#
# Fixing what can be fixed silently, and rejecting only what needs a human or
# a model to rewrite it, keeps the rejections meaningful. A hook that blocks a
# commit over something it could have repaired itself just trains people to
# reach for --no-verify.
let
  # Absolute store paths everywhere, because a hook runs in whatever PATH the
  # caller happened to have, and an agent shelling out to `git commit` may have
  # almost none of one.
  #
  # pkgs.git and not pkgs.gitMinimal: the hooks need `interpret-trailers` and
  # `stripspace`, which the minimal build does not ship.
  bin = {
    basename = "${pkgs.coreutils}/bin/basename";
    cut = "${pkgs.coreutils}/bin/cut";
    dirname = "${pkgs.coreutils}/bin/dirname";
    git = "${pkgs.git}/bin/git";
    grep = "${pkgs.gnugrep}/bin/grep";
    head = "${pkgs.coreutils}/bin/head";
    realpath = "${pkgs.coreutils}/bin/realpath";
    sed = "${pkgs.gnused}/bin/sed";
    tail = "${pkgs.coreutils}/bin/tail";
  };

  # The one place the allowed types are written down. The lint regex is
  # generated from this list, so extending the convention is a one line edit.
  commitTypes = [
    "feat"
    "fix"
    "docs"
    "style"
    "refactor"
    "perf"
    "test"
    "build"
    "ci"
    "chore"
    "revert"
  ];

  # An optional `!` before the colon marks a breaking change. Scope characters
  # are deliberately narrow: lowercase, digits, and the separators a module or
  # path name needs.
  titlePattern = "^(${lib.concatStringsSep "|" commitTypes})(\\([a-z0-9._/-]+\\))?!?: .+$";

  maxTitleLength = 50;

  trailer = "Co-Authored-By: Claude <noreply@anthropic.com>";

  # `git-commit-trailer <msgfile> [source]`, the same arguments git hands to
  # prepare-commit-msg, so a repo forced onto its own hooksPath can call this
  # directly with "$@" and get identical behaviour.
  commitTrailer = pkgs.writeShellScriptBin "git-commit-trailer" ''
    set -u

    msg_file="''${1-}"
    source="''${2-}"

    if [ -z "$msg_file" ]; then
      echo "usage: git-commit-trailer <commit-msg-file> [source]" >&2
      exit 2
    fi

    # A merge or squash message is composed by git in the middle of an
    # operation, and the lint skips validating those for the same reason.
    # Editing a message we are not going to check is pure risk.
    case "$source" in
      merge | squash)
        exit 0
        ;;
    esac

    # `interpret-trailers` and not an append, because a commit message file is
    # not just the message: for editor driven commits it also carries the
    # "# Please enter the commit message" block, and sometimes a scissors line.
    # git knows where the trailer block actually is; a `>>` does not, and would
    # bury the trailer below the comments where it never reaches the commit.
    #
    # --if-exists doNothing compares the trailer token case insensitively, so
    # an existing `Co-authored-by:` (the spelling GitHub itself generates) is
    # left alone rather than duplicated with our capitalisation.
    #
    # Failing here is not an option. This exists so that forgetting the trailer
    # is impossible, and a helper that can block a commit while doing someone a
    # favour is worse than no helper. Rejection is git-commit-lint's job.
    if ! ${bin.git} interpret-trailers --in-place --if-exists doNothing \
      --trailer "${trailer}" "$msg_file"; then
      echo "git-commit-trailer: could not add the Co-Authored-By trailer, continuing" >&2
    fi

    exit 0
  '';

  # `git-commit-lint <msgfile>`, the same argument git hands to commit-msg.
  commitLint = pkgs.writeShellScriptBin "git-commit-lint" ''
    set -u

    msg_file="''${1-}"

    if [ -z "$msg_file" ]; then
      echo "usage: git-commit-lint <commit-msg-file>" >&2
      exit 2
    fi

    # Documented escape hatch. There is always a commit that has to happen now,
    # and an unavoidable check with no way out is a check people disable
    # globally.
    if [ -n "''${SKIP_COMMIT_LINT-}" ]; then
      exit 0
    fi

    # Mid merge the message belongs to git, not to the author. Rejecting it
    # would strand the working tree in a conflicted, uncommittable state. The
    # rev-parse is allowed to fail so that this stays usable on a bare message
    # file outside any repository.
    merge_head="$(${bin.git} rev-parse --git-path MERGE_HEAD 2>/dev/null || true)"
    if [ -n "$merge_head" ] && [ -f "$merge_head" ]; then
      exit 0
    fi

    # Comments are stripped by git AFTER commit-msg runs, so the raw file still
    # holds the whole "# Please enter..." block for editor driven commits.
    # Validating that text would mean validating git's boilerplate.
    message="$(${bin.git} stripspace --strip-comments < "$msg_file")"
    title="$(printf '%s\n' "$message" | ${bin.head} -n 1)"

    # Titles git generates for itself. `fixup!`, `squash!` and `amend!` are
    # consumed by an autosquash rebase and must keep their exact prefix, and a
    # revert title is git's own wording. None of them can take our shape.
    case "$title" in
      "fixup!"* | "squash!"* | "amend!"* | "Revert "*)
        exit 0
        ;;
    esac

    fail() {
      {
        echo "git-commit-lint: rejected, $1"
        echo
        echo "  title  : $title"
        echo "  length : ''${#title} characters (limit ${toString maxTitleLength})"
        echo
        echo "Required format:"
        echo
        echo "  type(scope): short description"
        echo
        echo "  - bullet explaining what changed"
        echo "  - another bullet if needed"
        echo
        echo "  ${trailer}"
        echo
        echo "Rules:"
        echo "  - English, title at most ${toString maxTitleLength} characters including type and scope"
        echo "  - title lowercase, imperative, no trailing period"
        echo "  - type is one of: ${lib.concatStringsSep " " commitTypes} (a trailing ! marks a breaking change)"
        echo "  - scope is optional, lowercase letters, digits, . _ / -"
        echo "  - body has at least one line starting with '- '"
        echo "  - last line is exactly the Co-Authored-By trailer above"
        echo
        echo "To bypass this check for one commit: SKIP_COMMIT_LINT=1 git commit ..."
      } >&2
      exit 1
    }

    if [ -z "$message" ]; then
      fail "the commit message is empty"
    fi

    if ! printf '%s\n' "$title" | ${bin.grep} -Eq '${titlePattern}'; then
      fail "the title does not match 'type(scope): description' with an allowed type"
    fi

    if [ "''${#title}" -gt ${toString maxTitleLength} ]; then
      fail "the title is too long"
    fi

    case "$title" in
      *.)
        fail "the title ends with a period"
        ;;
    esac

    # From the second line on: the title itself is never a bullet, and counting
    # it would let a body-less commit pass.
    if ! printf '%s\n' "$message" | ${bin.tail} -n +2 | ${bin.grep} -q '^- '; then
      fail "the body has no line starting with '- '"
    fi

    # Matched in two steps so the token is case insensitive (GitHub writes
    # `Co-authored-by:`) while the value stays exact. A single `grep -i` on the
    # whole line would also accept a mangled address.
    if ! printf '%s\n' "$message" \
      | ${bin.grep} -i '^co-authored-by:' \
      | ${bin.sed} 's/^[^:]*:[[:space:]]*//' \
      | ${bin.grep} -qxF 'Claude <noreply@anthropic.com>'; then
      fail "the Co-Authored-By trailer is missing (git-commit-trailer normally adds it, so it was probably stripped afterwards)"
    fi

    exit 0
  '';

  # Chaining, and why every single hook file needs it.
  #
  # Setting core.hooksPath makes git stop looking at a repo's own .git/hooks
  # completely. Without this delegation, installing these hooks would silently
  # disable every per repo hook on the machine, including the pre-commit hook
  # this repo installs through `nix develop`. So each file here is a dispatcher
  # first and a hook second.
  #
  # NOT `rev-parse --git-path hooks`, which looks like the obvious answer and
  # is a trap: --git-path resolves "hooks" through core.hooksPath, so with
  # these hooks installed it hands back this very store directory and the
  # dispatcher execs itself until bash gives up at shell level 1000.
  # --git-common-dir is the honest question, and it is also the path
  # git-hooks.nix writes into core.hooksPath, so the two agree. `common`
  # rather than plain --git-dir because a linked worktree and a submodule keep
  # their hooks in the shared git dir, not in their own.
  #
  # The realpath comparison is the second lock on the same door: if a repo
  # local hook is itself a symlink back into this directory, delegating to it
  # would recurse just the same.
  chainLocal = name: ''
    local_hook="$(${bin.git} rev-parse --path-format=absolute --git-common-dir)/hooks/${name}"
    if [ ! -x "$local_hook" ] || [ "$(${bin.realpath} -m "$local_hook")" = "$(${bin.realpath} -m "$0")" ]; then
      local_hook=""
    fi
  '';

  # Hooks with no logic of our own. They exist only so that setting
  # core.hooksPath does not shadow the repo local hook of the same name.
  #
  # `exec` rather than a call: some of these (pre-push, pre-rebase) read stdin
  # and all of them signal through their exit code. exec hands over the process
  # untouched, so stdin, stdout and the exit status pass straight through with
  # nothing of ours in the middle.
  passthroughHooks = [
    "pre-commit"
    "pre-merge-commit"
    "pre-push"
    "pre-rebase"
    "post-commit"
    "post-checkout"
    "post-merge"
    "post-rewrite"
    "applypatch-msg"
    "pre-applypatch"
    "post-applypatch"
  ];

  # Every hook file has the same shape: delegate to the repo local hook of the
  # same name, then hand over to `command`, or just exit 0 when there is no
  # work of our own. Keeping the wrappers this thin is what stops the logic
  # from existing twice, once for core.hooksPath and once for PATH.
  mkHook =
    name: command:
    pkgs.writeShellScript "git-hook-${name}" ''
      set -u

      ${chainLocal name}
      if [ -n "$local_hook" ]; then
        ${if command == null then ''exec "$local_hook" "$@"'' else ''"$local_hook" "$@" || exit $?''}
      fi

      ${if command == null then "exit 0" else ''exec ${command} "$@"''}
    '';

  hooks = {
    prepare-commit-msg = mkHook "prepare-commit-msg" "${commitTrailer}/bin/git-commit-trailer";
    commit-msg = mkHook "commit-msg" "${commitLint}/bin/git-commit-lint";
  }
  // lib.genAttrs passthroughHooks (name: mkHook name null);

  # Real files rather than symlinks into the store: git only cares that each
  # entry is executable, but a plain directory of scripts is what every `ls -l`
  # of a hooks path is expected to look like.
  hooksDir = pkgs.runCommand "git-hooks" { } (
    ''
      mkdir -p "$out"
    ''
    + lib.concatStrings (
      lib.mapAttrsToList (name: script: ''
        install -m 755 ${script} "$out/${name}"
      '') hooks
    )
  );

  # The whole point of this one: a repo that sets its own core.hooksPath wins,
  # and until you go looking there is nothing to see. `git commit` keeps
  # working, the trailer quietly stops appearing, and a bad title sails
  # through. This turns that into a question anyone can ask out loud.
  #
  # A report, never a gate, so it always exits 0.
  doctor = pkgs.writeShellScriptBin "git-hooks-doctor" ''
    set -u

    ours="${hooksDir}"

    repo_root="$(${bin.git} rev-parse --show-toplevel 2>/dev/null || true)"
    if [ -z "$repo_root" ]; then
      echo "git-hooks-doctor: not inside a git repository, nothing to check."
      exit 0
    fi

    configured="$(${bin.git} config --get core.hooksPath || true)"

    # --show-origin prints "origin<TAB>value", and cut splits on tab by default.
    origin="$(${bin.git} config --show-origin --get core.hooksPath 2>/dev/null | ${bin.cut} -f1 || true)"

    if [ -n "$configured" ]; then
      # A relative core.hooksPath is resolved against the top level directory.
      case "$configured" in
        /*) effective="$configured" ;;
        *) effective="$repo_root/$configured" ;;
      esac
    else
      effective="$(${bin.git} rev-parse --path-format=absolute --git-common-dir)/hooks"
      origin="unset, so git uses the repository's own hooks directory"
    fi

    echo "repository       : $repo_root"
    echo "core.hooksPath   : ''${configured:-<unset>}"
    echo "  set in         : $origin"
    echo "effective hooks  : $effective"
    echo

    if [ "$(${bin.realpath} -m "$effective")" = "$(${bin.realpath} -m "$ours")" ]; then
      echo "commit format hooks: ACTIVE"
      echo
      echo "Commits here get the Co-Authored-By trailer added automatically and"
      echo "the title and body checked. This repository's own hooks in"
      echo "$(${bin.git} rev-parse --path-format=absolute --git-common-dir)/hooks still run:"
      echo "every dispatcher delegates to them first."
      exit 0
    fi

    echo "commit format hooks: SHADOWED, they are NOT running here"
    echo
    echo "git gives repository local config precedence over the global value,"
    echo "so the path above wins over ours:"
    echo
    echo "  ours : $ours"
    echo
    echo "husky does this (it points core.hooksPath at .husky/_), and so does"
    echo "anything else that installs its own hook runner."
    echo

    # Point at the file a human is meant to edit. Under husky, everything in
    # `.husky/_` is generated and `husky install` overwrites it, so advising an
    # edit there would be advice that quietly undoes itself. The runner in `_`
    # invokes the same-named file one level up, and that one is committed.
    target_dir="$effective"
    if [ "$(${bin.basename} "$effective")" = "_" ] && [ "$(${bin.basename} "$(${bin.dirname} "$effective")")" = ".husky" ]; then
      target_dir="$(${bin.dirname} "$effective")"
      echo "This looks like husky. Everything under .husky/_ is generated and"
      echo "husky install overwrites it, so edit the committed hooks one level"
      echo "up instead. The runner in _ calls them for you."
      echo
    fi

    echo "To get the checks back, have those hooks call the binaries directly."
    echo "Both take exactly the arguments git passes:"
    echo
    echo "  $target_dir/prepare-commit-msg"
    echo '    exec git-commit-trailer "$@"'
    echo
    echo "  $target_dir/commit-msg"
    echo '    exec git-commit-lint "$1"'
    echo
    echo "Remember to keep whatever those hooks already do, and to chmod +x any"
    echo "file you create."

    if command -v git-commit-lint > /dev/null 2>&1; then
      echo
      echo "git-commit-lint is on PATH at $(command -v git-commit-lint)"
    else
      echo
      echo "warning: git-commit-lint is not on PATH, so the lines above would"
      echo "warning: fail. It ships in home.packages from the nalyx git module."
    fi

    exit 0
  '';
in
{
  inherit
    hooksDir
    commitTrailer
    commitLint
    doctor
    ;
}
