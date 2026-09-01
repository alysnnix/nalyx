{ lib }:

# Declarative source of the global agent rules, shared by Claude Code and omp.
#
# Sections are numbered by their position in the list, so a number is never
# written into a body file: reordering, adding, or disabling a section
# renumbers the rest for free. The corollary is a hard rule of its own, never
# cross-reference a section by number, always by title.
#
# `sticky` is the terse imperative form of a section. omp loads RULES.md as an
# always-apply rule and re-attaches it near the current turn, so a sticky rule
# keeps its hold deep into a long session instead of scrolling out of attention
# along with the opening context. Only rules whose violation is irreversible
# (touching main, corrupting a sibling worktree, merging unreviewed, burning the
# orchestrator's context on work a subagent should have read) or that apply to
# every single output (writing style, commit format) earn a sticky line.
# Posture and advice stay in the long form only, since RULES.md pays its
# context cost on every turn rather than once.
let
  sections = [
    {
      title = "Think Before Coding";
      body = ./sections/think-before-coding.md;
      # Posture, not a load-bearing or irreversible rule. Dropped from the
      # always-on context; re-enable by removing this line.
      enable = false;
    }
    {
      title = "Decompose, Then Fan Out";
      body = ./sections/decompose-and-fan-out.md;
      sticky = "Before the first edit, split the task into slices and dispatch every independent slice in ONE batch of subagents. Keep the decomposition and anything shared between slices yourself, give each slice a self-contained brief plus how to verify itself, and never spawn a single subagent just to wait on it.";
    }
    {
      title = "Simplicity First";
      body = ./sections/simplicity-first.md;
      enable = false;
    }
    {
      title = "Surgical Changes";
      body = ./sections/surgical-changes.md;
      enable = false;
    }
    {
      title = "Goal-Driven Execution";
      body = ./sections/goal-driven-execution.md;
      enable = false;
    }
    {
      title = "Protected Main Branch";
      body = ./sections/protected-main-branch.md;
      sticky = "NEVER commit, merge, or push to `main` or `master` unless the user authorized that exact action in this conversation, and restate it for confirmation before executing.";
      # Sticky-only: the one-line imperative is the whole rule; the body just
      # restated it. Kept re-attaching every turn, dropped from the long form.
      longForm = false;
    }
    {
      title = "Commit Messages";
      body = ./sections/commit-messages.md;
      sticky = "Commit messages are in English: title `type(scope): description`, whole line at most 50 characters, lowercase imperative with no period; ALWAYS a `- ` bullet body; last line exactly `Co-Authored-By: Claude <noreply@anthropic.com>`, that literal name whichever model is running, never a model specific variant.";
      # Both channels: the sticky line carries the full shape because it is
      # violated on every commit otherwise, and the body spells out the type
      # list and the trailer rationale, which do not fit on one line.
    }
    {
      title = "Proportionality";
      body = ./sections/proportionality.md;
      sticky = "Scale review to blast radius, not diff size. A diff that cannot change behavior gets no reviewer; anything touching a public signature, auth, data, money, or concurrency gets the full fan-out. Worktree and draft PR are never skipped, they cost nothing.";
      # Sticky-only: the tier table is reference material, consulted when
      # reviewing, not needed on every turn.
      longForm = false;
    }
    {
      title = "One Worktree Per Task";
      body = ./sections/one-worktree-per-task.md;
      sticky = "Any task that will produce commits runs in its own git worktree, never in the primary checkout. Another agent may hold that checkout.";
      # Sticky-only: the step-by-step is a procedure invoked when starting a
      # task; the `wt` command and the gb worktree skills carry the detail.
      longForm = false;
    }
    {
      title = "Draft PR, Then Close The Review Loop";
      body = ./sections/draft-pr-review-loop.md;
      sticky = "Open every PR as a draft. Only the review loop marks it ready, and NEVER run `gh pr ready` to get around a blocked merge.";
      # Sticky-only: the 6-step loop is a procedure, and the gb-review-loop
      # skill already implements it more richly than this prose.
      longForm = false;
    }
    {
      title = "Nothing Leaves This Machine";
      body = ./sections/no-cloud-publishing.md;
      sticky = "NEVER publish, upload, or run anything on claude.ai or another cloud environment: no artifacts, no remote agents, no cloud sessions. The account is shared. Deliver pages as local files and hand over the path.";
      # Sticky-only: the settings.json keys do the enforcing, so the body is
      # background. The imperative has to keep re-attaching because the failure
      # is irreversible, someone else has already seen it.
      longForm = false;
    }
    {
      title = "Writing Style";
      body = ./sections/writing-style.md;
      sticky = "NEVER write em-dashes or en-dashes in any output, including code, docs, commits, and chat. Use commas, periods, parentheses, or rephrase.";
      longForm = false;
    }
  ];

  enabled = lib.filter (s: s.enable or true) sections;

  # `longForm` (default true) controls whether a section's body is rendered into
  # the long-form context file. A section with `longForm = false` is dropped
  # from the body but still contributes its `sticky` line, so a load-bearing
  # imperative keeps re-attaching every turn (cheap) while its detailed prose no
  # longer rides on every request. The body file stays on disk, so flipping this
  # back to true is a one-line change.
  longFormSections = lib.filter (s: s.longForm or true) enabled;

  renderSection =
    i: s:
    ''
      ## ${toString i}. ${s.title}

    ''
    + builtins.readFile s.body;

  stickyLines = lib.concatMapStringsSep "\n" (s: "- ${s.sticky}") (
    lib.filter (s: s ? sticky) enabled
  );

  # Runtime and host-local guidance lands here. Nix creates the file once and
  # never overwrites it, so an edit made mid-session survives the next switch.
  #
  # Only emitted for tools that actually expand an `@path` token inline: Claude
  # Code does it natively and omp documents it. Codex concatenates AGENTS.md
  # files verbatim and opencode has no import mechanism, so for those the token
  # would just sit there as literal noise. Local additions are therefore a
  # Claude Code and omp affordance, which is fine, they exist for the tool you
  # are editing in.
  localAdditions = ''
    ## Local Additions

    Anything below comes from `~/.claude/CLAUDE.local.md`, which Nix creates once and never overwrites. Durable rules belong in the nalyx repo instead, so every host gets them.

    @~/.claude/CLAUDE.local.md
  '';

  body = lib.concatStringsSep "\n" (lib.imap1 renderSection longFormSections);

  render =
    tail:
    builtins.readFile ./sections/preamble.md
    + "\n"
    + body
    + "\n"
    + tail
    + builtins.readFile ./sections/closing.md;
in
{
  # Long-form context for tools that expand `@` imports (Claude Code, omp).
  globalMd = render (localAdditions + "\n");

  # Same content for tools that do not, so the import token is left out rather
  # than shown as dead text. Codex caps a doc at project_doc_max_bytes (32 KiB
  # by default) and silently truncates past it, so keep an eye on the size if
  # many more sections get added.
  globalMdPlain = render "";

  # Sticky always-apply rules, deployed to ~/.omp/agent/RULES.md. omp is the
  # only one of these tools with a re-attached always-apply rule channel.
  rulesMd = ''
    # Global rules

    ${stickyLines}
  '';
}
