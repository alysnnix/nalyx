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
# (touching main, corrupting a sibling worktree, merging unreviewed) or that
# apply to every single output (writing style, commit format) earn a sticky
# line. Posture and advice stay in the long form only, since RULES.md pays its
# context cost on every turn rather than once.
let
  sections = [
    {
      title = "Think Before Coding";
      body = ./sections/think-before-coding.md;
    }
    {
      title = "Simplicity First";
      body = ./sections/simplicity-first.md;
    }
    {
      title = "Surgical Changes";
      body = ./sections/surgical-changes.md;
    }
    {
      title = "Goal-Driven Execution";
      body = ./sections/goal-driven-execution.md;
    }
    {
      title = "Protected Main Branch";
      body = ./sections/protected-main-branch.md;
      sticky = "NEVER commit, merge, or push to `main` or `master` unless the user authorized that exact action in this conversation, and restate it for confirmation before executing.";
    }
    {
      title = "Commit Messages";
      body = ./sections/commit-messages.md;
      sticky = "Commit messages are in English, title at most 50 characters, always with a bullet-point body.";
    }
    {
      title = "One Worktree Per Task";
      body = ./sections/one-worktree-per-task.md;
      sticky = "Any task that will produce commits runs in its own git worktree, never in the primary checkout. Another agent may hold that checkout.";
    }
    {
      title = "Draft PR, Then Close The Review Loop";
      body = ./sections/draft-pr-review-loop.md;
      sticky = "Open every PR as a draft. Only the review loop marks it ready, and NEVER run `gh pr ready` to get around a blocked merge.";
    }
    {
      title = "Writing Style";
      body = ./sections/writing-style.md;
      sticky = "NEVER write em-dashes or en-dashes in any output, including code, docs, commits, and chat. Use commas, periods, parentheses, or rephrase.";
    }
  ];

  enabled = lib.filter (s: s.enable or true) sections;

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

  body = lib.concatStringsSep "\n" (lib.imap1 renderSection enabled);

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
