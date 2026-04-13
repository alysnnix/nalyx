# Obsidian Notes Skill — Design Spec

**Date:** 2026-04-13
**Status:** Approved

## Goal

Create a global Claude Code skill that saves and retrieves curated knowledge to/from an Obsidian vault (git repo), organized by project and context. All Claude Code profiles must access the same vault.

## Vault Location

```
~/nalyx/.private/notes/          # git@github.com:alysnnix/notes.git
```

- Cloned automatically by `switch` (update-sys.sh)
- `.private/` is gitignored by nalyx
- Obsidian Git plugin handles commit/push/pull
- Path hardcoded in skill: `~/nalyx/.private/notes/claude/`

## Directory Structure

```
notes/
└── claude/
    ├── works/                   # work projects
    │   ├── seazone/
    │   │   ├── architecture.md
    │   │   └── decisions.md
    │   └── goniche/
    │       └── ...
    ├── personal/                # personal projects
    │   └── nalyx/
    │       └── ...
    ├── meets/                   # global meetings, by day
    │   └── YYYY-MM-DD/
    │       ├── seazone-daily.md
    │       └── goniche-kickoff.md
    └── index.md                 # general index for Obsidian navigation
```

### Naming Conventions

- File names: `kebab-case`, English
- Meets: `meets/YYYY-MM-DD/meeting-name.md`
- Works: `works/company-or-project/topic.md`
- Personal: `personal/project/topic.md`

### Frontmatter

Every file has YAML frontmatter:

```yaml
---
type: knowledge          # knowledge | meet | decision | reference
project: seazone
created: 2026-04-13
updated: 2026-04-13
tags: [architecture, backend]
---
```

## Skill Design

### Installation

Global skill at `~/.claude/skills/notes/` — accessible by all profiles (work, personal, minimax, etc.).

### Modes

#### Save (write)

The skill writes structured markdown to the vault. Three trigger types:

1. **Proactive** — Claude detects important knowledge while working (architecture, patterns, decisions) and saves it automatically. Always notifies the user: *"Saved Sapron auth pattern to notes"*.
2. **Explicit** — User asks: "save this to notes", "record this meeting". Claude infers context or asks for minimal details.
3. **Transcription** — User pastes a meeting transcript. Claude processes, structures, and saves to `meets/YYYY-MM-DD/name.md`.

#### Read (consult)

The skill reads from the vault for context:

1. **Explicit** — "What do I know about seazone?" → reads `works/seazone/`
2. **Implicit** — Before working on a project, Claude can check for saved context
3. **Search** — "What meetings did I have this week?" → lists recent `meets/` folders

### Proactive Save Rules

**Save automatically when:**
- Learning structural info about a project (architecture, decisions, patterns)
- Receiving a meeting transcript or summary
- Discovering important reference info (URLs, staging credentials, flows)

**Do NOT save:**
- Ephemeral implementation details (one-off bugs, temporary values)
- Information already in code or git history
- Duplicates of existing notes

**Always notify** when saving proactively.

### Update vs Create

When saving, if a note for the same topic already exists (e.g., `works/seazone/architecture.md`), **update it** by appending or merging new information. Update the `updated` field in frontmatter. Only create a new file when the topic is genuinely new.

### Vault Not Found

If `~/nalyx/.private/notes/claude/` doesn't exist, the skill warns: *"Vault not found. Run `switch` to clone."*

## Auto-Clone in `switch`

Modification to `update-sys.sh` — after the nalyx-private clone block:

```bash
NOTES_DIR="$FLAKE_DIR/.private/notes"
if [ ! -d "$NOTES_DIR" ]; then
    echo "Cloning notes vault..."
    git clone git@github.com:alysnnix/notes.git "$NOTES_DIR"
fi
```

- Only runs if SSH is available (already tested for nalyx-private)
- Only clones if directory doesn't exist — no pull (Obsidian Git handles sync)
- No impact if clone fails (system works without vault)

## Cross-Profile Access

All profiles share `~/.claude/skills/` → same skill, same vault path. No per-profile configuration needed.

## Future Enhancements

- Obsidian CLI integration when installed (richer queries, template support)
- Auto-index generation (`index.md`) with links to all notes
- Wikilink support for cross-referencing between notes
