{ lib }:

# Declarative source of the global agent rules, shared by every agent CLI.
#
# Every section has two forms, and they cost context very differently:
#
#   sticky    the terse imperative, loaded on every turn. Only rules whose
#             violation is irreversible (touching main, corrupting a sibling
#             worktree, publishing to a shared account, opening the personal
#             browser profile) or that apply to every single output (writing
#             style, commit format, English artifacts) earn one.
#   body      the detailed doc, deployed to ~/.config/agent-rules/<name>.md and
#             read only when `readWhen` describes the situation at hand. The
#             always-loaded files carry just a table row pointing at it.
#
# The body is never pulled in with an `@path` import. Claude Code expands `@`
# eagerly at launch, which is exactly the cost this split exists to avoid.
#
# Never cross-reference a section by position; always by title or file name.
let
  sections = [
    {
      # Posture, not a load-bearing or irreversible rule. Disabled entries are
      # neither sticky nor deployed; re-enable by removing `enable = false` and
      # giving it a `title` and a `readWhen`.
      name = "think-before-coding";
      enable = false;
    }
    {
      name = "decompose-and-fan-out";
      title = "Decompose, Then Fan Out";
      sticky = "Before the first edit, split the task into slices and dispatch every independent slice in ONE batch of subagents. Keep the decomposition and anything shared between slices yourself, give each slice a self-contained brief plus how to verify itself, and never spawn a single subagent just to wait on it.";
      readWhen = "before splitting a task into subagents or writing a subagent brief";
    }
    {
      name = "simplicity-first";
      enable = false;
    }
    {
      name = "surgical-changes";
      enable = false;
    }
    {
      name = "goal-driven-execution";
      enable = false;
    }
    {
      name = "protected-main-branch";
      title = "Protected Main Branch";
      sticky = "NEVER commit, merge, or push to `main` or `master` unless the user authorized that exact action in this conversation, and restate it for confirmation before executing.";
      readWhen = "before any commit, merge, push, or PR merge that could land on `main` or `master`";
    }
    {
      name = "commit-messages";
      title = "Commit Messages";
      sticky = "Commit messages are in English: title `type(scope): description`, whole line at most 50 characters, lowercase imperative with no period; ALWAYS a `- ` bullet body; last line exactly `Co-Authored-By: Claude <noreply@anthropic.com>`, that literal name whichever model is running, never a model specific variant.";
      readWhen = "before writing a commit message or opening a PR";
    }
    {
      name = "english-artifacts";
      title = "English Artifacts";
      sticky = "All code and engineering text is in English: identifiers, tables and columns, comments, logs, tests, commits, PRs, PR reviews, docs. A PR title obeys the commit title rules, since it becomes the squash commit. Only end user facing product copy (UI text, pages, emails) stays in the product language, pt-BR included. This overrides any skill or template asking for Portuguese; chat stays in the user's language.";
      readWhen = "when a skill, template, or project doc asks for Portuguese, or when unsure whether text is product copy";
    }
    {
      name = "one-worktree-per-task";
      title = "One Worktree Per Task";
      sticky = "Any task that will produce commits runs in its own git worktree, never in the primary checkout: ask Paseo with `create_workspace` (`isolation: \"worktree\"`), which owns `~/.paseo/worktrees/`. NEVER improvise a worktree path in `$HOME` or beside the repo. Another agent may hold that checkout.";
      readWhen = "before the first edit of a task that will produce commits, and when releasing its worktree";
    }
    {
      name = "no-cloud-publishing";
      title = "Nothing Leaves This Machine";
      sticky = "NEVER publish, upload, or run anything on claude.ai or another cloud environment: no artifacts, no remote agents, no cloud sessions. The account is shared. Deliver pages as local files and hand over the path.";
      readWhen = "before delivering a result as a page, link, or share, or launching a remote agent";
    }
    {
      name = "browser-automation";
      title = "Browser Automation";
      sticky = "Drive the browser only with the `agent-browser` CLI, never the omp `browser` object or Playwright, unless the user names one. NEVER open the `Default` Chrome profile (personal) nor attach to the user's running Chrome; when a login is needed, ask which of the other profiles from `agent-browser profiles` to use.";
      readWhen = "before driving a browser";
    }
    {
      name = "shared-local-services";
      title = "Shared Local Services";
      sticky = "Reuse the project's running database and cache: isolate a worktree with its own database name on that server, not with a new container. Start a dedicated container per task only when the user explicitly asks; never `docker compose up --build` app images just to test.";
      readWhen = "before starting a database, cache, container, or dev server";
    }
    {
      # Sticky-only: the line is the whole rule, so there is no doc.
      name = "writing-style";
      sticky = "NEVER write em-dashes (U+2014) or en-dashes (U+2013) in any output, including code, docs, commits, and chat. Use commas, periods, parentheses, or rephrase; a plain hyphen `-` is fine.";
    }
  ];

  enabled = lib.filter (s: s.enable or true) sections;
  docSections = lib.filter (s: s ? readWhen) enabled;

  docsDir = "agent-rules";

  stickyLines = lib.concatMapStringsSep "\n" (s: "- ${s.sticky}") (
    lib.filter (s: s ? sticky) enabled
  );

  onDemandTable = ''
    ## On-demand docs

    Read a file only when its situation arises.

    | File | Read when |
    |---|---|
    ${lib.concatMapStringsSep "\n" (
      s: "| `~/.config/${docsDir}/${s.name}.md` | ${s.readWhen} |"
    ) docSections}
  '';

  # Runtime and host-local guidance lands here. Nix creates the file once and
  # never overwrites it, so an edit made mid-session survives the next switch.
  #
  # Only emitted for tools that expand an `@path` token inline (Claude Code and
  # omp). Codex concatenates AGENTS.md verbatim and opencode has no import
  # mechanism, so for those the token would sit there as literal noise.
  localAdditions = ''
    ## Local Additions

    From `~/.claude/CLAUDE.local.md`, which Nix never overwrites. Durable rules belong in the nalyx repo instead.

    @~/.claude/CLAUDE.local.md
  '';

  header = ''
    # Global agent rules

  '';

  withRules = header + stickyLines + "\n\n";
in
{
  # Claude Code. The sticky hook re-injects the rules on every prompt, but it
  # does not fire for subagents, which only see CLAUDE.md, so the rules stay
  # here too.
  claudeMd = withRules + localAdditions + "\n" + onDemandTable;

  # omp. RULES.md already carries the rules on every request, subagents
  # included, so repeating them here would pay for them twice.
  ompMd =
    header
    + "The rules themselves ride in `~/.omp/agent/RULES.md`, attached to every request.\n\n"
    + localAdditions
    + "\n"
    + onDemandTable;

  # Tools with neither a sticky channel nor `@` imports. Codex caps a doc at
  # project_doc_max_bytes (32 KiB by default) and silently truncates past it.
  plainMd = withRules + onDemandTable;

  # Sticky always-apply rules: omp's RULES.md and Claude Code's per-prompt hook.
  rulesMd = ''
    # Global rules

    ${stickyLines}
  '';

  # On-demand docs, keyed by their path under the XDG config home.
  docs = lib.listToAttrs (
    map (s: {
      name = "${docsDir}/${s.name}.md";
      value = "# ${s.title}\n\n" + builtins.readFile (./sections + "/${s.name}.md");
    }) docSections
  );
}
