# Obsidian Notes Skill — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a global Claude Code skill that saves/reads curated knowledge to an Obsidian vault, plus auto-clone the vault repo on `switch`.

**Architecture:** A single SKILL.md file at `~/.claude/skills/notes/` that instructs Claude how to write/read markdown files in `~/nalyx/.private/notes/claude/`. The vault is cloned by `update-sys.sh` using the same SSH-check pattern as nalyx-private.

**Tech Stack:** Claude Code skills (markdown), Bash (update-sys.sh), Git

---

### Task 1: Add notes vault auto-clone to update-sys.sh

**Files:**
- Modify: `home/features/cli/zsh/scripts/update-sys.sh:25-40`

- [ ] **Step 1: Add notes clone block after the private repo block**

In `home/features/cli/zsh/scripts/update-sys.sh`, add the following block between the `fi` that closes the private repo logic (line 40) and the `sudo nixos-rebuild` line (line 42):

```bash
# Clone notes vault (Obsidian) if SSH is available and not already cloned
NOTES_DIR="$FLAKE_DIR/.private/notes"
if [ ! -d "$NOTES_DIR" ]; then
  if [ -d "$PRIVATE_DIR" ] || ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new git@github.com 2>/dev/null; [ $? -eq 1 ]; then
    echo "  notes: cloning git@github.com:alysnnix/notes.git..."
    git clone git@github.com:alysnnix/notes.git "$NOTES_DIR" || echo "  notes: clone failed, skipping"
  fi
else
  echo "  notes: $NOTES_DIR"
fi
```

This reuses the SSH test result implicitly: if `$PRIVATE_DIR` exists, SSH already worked. Otherwise it re-tests. The `|| echo` ensures a clone failure doesn't abort the script (set -e).

- [ ] **Step 2: Verify the script is syntactically valid**

Run:
```bash
bash -n ~/nalyx/home/features/cli/zsh/scripts/update-sys.sh
```

Expected: no output (no syntax errors).

- [ ] **Step 3: Commit**

```bash
cd ~/nalyx
git add home/features/cli/zsh/scripts/update-sys.sh
git commit -m "feat(cli): auto-clone notes vault on switch"
```

---

### Task 2: Create the notes skill directory

**Files:**
- Create: `~/.claude/skills/notes/SKILL.md`

- [ ] **Step 1: Create the skill file**

```bash
mkdir -p ~/.claude/skills/notes
```

Write `~/.claude/skills/notes/SKILL.md` with the following content:

```markdown
---
name: notes
description: "Save and retrieve curated knowledge to the Obsidian vault. Use proactively when learning important project info, or when user asks to save/query notes. Triggers: 'save to notes', 'what do I know about X', meeting transcripts, architectural discoveries."
user-invocable: true
---

# Notes — Obsidian Knowledge Vault

Save and retrieve curated knowledge from the Obsidian vault at `~/nalyx/.private/notes/claude/`.

## Vault Check

Before any read or write, verify the vault exists:

```bash
ls ~/nalyx/.private/notes/claude/ 2>/dev/null
```

If it does not exist, tell the user: **"Vault not found at ~/nalyx/.private/notes/. Run `switch` to clone it."** and stop.

## Directory Structure

```
~/nalyx/.private/notes/claude/
├── works/                   # work projects (seazone, goniche, etc.)
│   └── {project}/
│       └── {topic}.md
├── personal/                # personal projects (nalyx, etc.)
│   └── {project}/
│       └── {topic}.md
├── meets/                   # global meetings, organized by day
│   └── YYYY-MM-DD/
│       └── {meeting-name}.md
└── index.md                 # general index (auto-maintained)
```

### Naming Rules

- All file/folder names: `kebab-case`, English
- Meets: `meets/YYYY-MM-DD/descriptive-name.md`
- Works: `works/company-or-project/topic.md`
- Personal: `personal/project/topic.md`

## Frontmatter

**Every file MUST have this YAML frontmatter:**

```yaml
---
type: knowledge          # knowledge | meet | decision | reference
project: project-name
created: YYYY-MM-DD
updated: YYYY-MM-DD
tags: [tag1, tag2]
---
```

Types:
- `knowledge` — architectural info, patterns, how things work
- `meet` — meeting notes, transcriptions, action items
- `decision` — recorded decisions with context and rationale
- `reference` — URLs, credentials, environment info, quick-reference

## Saving (Write)

### When to save proactively

Save automatically and notify the user ("Saved X to notes") when you:
- Learn structural info about a project (architecture, patterns, service topology)
- Receive a meeting transcript or summary
- Discover important reference info (URLs, staging envs, API flows, credentials)
- Learn about decisions and their rationale

### When NOT to save

- Ephemeral implementation details (one-off bugs, temporary values)
- Information already in code or git history
- Duplicates of existing notes — check first

### Update vs Create

Before creating a new file, check if a note for the same topic already exists:

```bash
ls ~/nalyx/.private/notes/claude/works/{project}/ 2>/dev/null
```

- **If exists:** Read the existing file, merge/append new information, update the `updated` frontmatter field
- **If new:** Create the file with full frontmatter

### Writing procedure

1. Determine the category: `works/`, `personal/`, or `meets/`
2. Determine the project name (kebab-case)
3. Determine the topic or meeting name (kebab-case)
4. Check if the file exists (update vs create)
5. Write the file with proper frontmatter
6. Notify the user what was saved and where

### Meeting transcription

When the user pastes a meeting transcript:

1. Ask for meeting name if not obvious from context (or infer it)
2. Process the transcript into structured notes:
   - **Attendees** (if identifiable)
   - **Summary** (2-3 sentences)
   - **Key Points** (bulleted)
   - **Decisions** (if any)
   - **Action Items** (if any, with owners)
   - **Raw Transcript** (collapsed in a `<details>` block)
3. Save to `meets/YYYY-MM-DD/meeting-name.md` with `type: meet`
4. Notify the user

## Reading (Consult)

### Explicit queries

When the user asks about saved knowledge ("what do I know about X", "notes about seazone"):

1. Search the relevant directory:
   ```bash
   find ~/nalyx/.private/notes/claude/ -name "*.md" | head -50
   ```
2. Read matching files
3. Summarize the knowledge found

### Project context lookup

When starting work on a project, check if notes exist:

```bash
ls ~/nalyx/.private/notes/claude/works/{project}/ 2>/dev/null
```

If notes exist, briefly review them for relevant context.

### Meeting history

When asked about recent meetings:

```bash
ls -d ~/nalyx/.private/notes/claude/meets/*/ 2>/dev/null | sort -r | head -10
```

List the dates and meeting names found.

## Index Maintenance

After saving a new file, update `~/nalyx/.private/notes/claude/index.md`. The index is a simple list of all notes organized by category:

```markdown
# Claude Notes Index

## Works

### Seazone
- [Architecture](works/seazone/architecture.md)
- [Decisions](works/seazone/decisions.md)

### Goniche
- [Overview](works/goniche/overview.md)

## Personal

### Nalyx
- [Config Patterns](personal/nalyx/config-patterns.md)

## Meets

### 2026-04-13
- [Seazone Daily](meets/2026-04-13/seazone-daily.md)
```

Rebuild the index by scanning all files under `claude/`. Use Obsidian-compatible relative links.

## Example: Saving Architecture Knowledge

If you discover that Seazone's Sapron service uses JWT auth with CloudFlare Access headers:

1. Check: `ls ~/nalyx/.private/notes/claude/works/seazone/` — does `sapron.md` or `architecture.md` exist?
2. If `architecture.md` exists, read it and append the new info
3. If not, create `works/seazone/architecture.md`:

```markdown
---
type: knowledge
project: seazone
created: 2026-04-13
updated: 2026-04-13
tags: [architecture, auth, sapron]
---

# Seazone Architecture

## Sapron

- Backend service at sapron.com.br
- Uses JWT authentication
- CloudFlare Access headers required for API access
- MCP server configured for Claude Code access
```

4. Update `index.md`
5. Tell the user: *"Saved Sapron architecture details to notes (works/seazone/architecture.md)"*
```

- [ ] **Step 2: Verify the skill file is well-formed**

```bash
head -5 ~/.claude/skills/notes/SKILL.md
```

Expected:
```
---
name: notes
description: "Save and retrieve curated knowledge to the Obsidian vault..."
user-invocable: true
---
```

- [ ] **Step 3: Verify the skill appears in Claude Code**

Run `claude --help` or start a new session and check that the `notes` skill appears in the skill list. The skill should be listed as user-invocable.

- [ ] **Step 4: Commit** (not in nalyx — this is in ~/.claude which is not a git repo, so skip this commit)

No commit needed. The skill lives in `~/.claude/skills/notes/` which is local user data, not part of nalyx.

---

### Task 3: Create the vault scaffold

**Files:**
- Create: `~/nalyx/.private/notes/claude/index.md`
- Create: `~/nalyx/.private/notes/claude/works/.gitkeep`
- Create: `~/nalyx/.private/notes/claude/personal/.gitkeep`
- Create: `~/nalyx/.private/notes/claude/meets/.gitkeep`

**Prerequisite:** The notes repo must be cloned at `~/nalyx/.private/notes/`. If it's not there yet, clone it first:

```bash
git clone git@github.com:alysnnix/notes.git ~/nalyx/.private/notes
```

- [ ] **Step 1: Create the claude directory structure**

```bash
mkdir -p ~/nalyx/.private/notes/claude/works
mkdir -p ~/nalyx/.private/notes/claude/personal
mkdir -p ~/nalyx/.private/notes/claude/meets
```

- [ ] **Step 2: Create .gitkeep files so empty dirs are tracked**

```bash
touch ~/nalyx/.private/notes/claude/works/.gitkeep
touch ~/nalyx/.private/notes/claude/personal/.gitkeep
touch ~/nalyx/.private/notes/claude/meets/.gitkeep
```

- [ ] **Step 3: Create the initial index.md**

Write `~/nalyx/.private/notes/claude/index.md`:

```markdown
# Claude Notes Index

## Works

_No notes yet._

## Personal

_No notes yet._

## Meets

_No notes yet._
```

- [ ] **Step 4: Commit and push to notes repo**

```bash
cd ~/nalyx/.private/notes
git add claude/
git commit -m "feat: add claude knowledge vault scaffold"
git push
```

---

### Task 4: End-to-end test — save a note

- [ ] **Step 1: Use the skill to save a test note**

In a Claude Code session (any profile), say: "save to notes: nalyx uses a public/private split architecture with hasPrivate detection"

Claude should:
1. Detect the vault at `~/nalyx/.private/notes/claude/`
2. Create `personal/nalyx/architecture.md` with proper frontmatter
3. Update `index.md`
4. Notify: "Saved nalyx architecture to notes"

- [ ] **Step 2: Verify the file was created**

```bash
cat ~/nalyx/.private/notes/claude/personal/nalyx/architecture.md
```

Expected: file exists with YAML frontmatter (`type: knowledge`, `project: nalyx`, today's date) and the content about public/private split.

- [ ] **Step 3: Verify the index was updated**

```bash
cat ~/nalyx/.private/notes/claude/index.md
```

Expected: `index.md` now has a "Nalyx" entry under "Personal" linking to the new file.

- [ ] **Step 4: Use the skill to read back**

Say: "what do I know about nalyx?"

Claude should read `personal/nalyx/` and summarize the saved knowledge.

- [ ] **Step 5: Verify from a different context**

Open Claude Code in a different project directory (e.g., `cd ~/wrk/seazone-tech && claude`). Ask: "check my notes about nalyx"

Claude should find and read the same file — confirming cross-profile access works.

---

### Task 5: End-to-end test — meeting transcription

- [ ] **Step 1: Simulate a meeting transcript save**

Paste a short test transcript and say "save this meeting":

```
Meeting: test sync check
Date: 2026-04-13

Aly: let's test if the notes skill works
Claude: saving this to the vault
Aly: looks good, ship it
```

Claude should:
1. Process into structured notes (summary, key points)
2. Save to `meets/2026-04-13/test-sync-check.md`
3. Update `index.md`

- [ ] **Step 2: Verify the meeting note**

```bash
cat ~/nalyx/.private/notes/claude/meets/2026-04-13/test-sync-check.md
```

Expected: frontmatter with `type: meet`, structured content with summary and key points.

- [ ] **Step 3: Query meeting history**

Say: "what meetings did I have today?"

Claude should list the test meeting from `meets/2026-04-13/`.

- [ ] **Step 4: Clean up test data**

```bash
rm ~/nalyx/.private/notes/claude/personal/nalyx/architecture.md
rm -rf ~/nalyx/.private/notes/claude/meets/2026-04-13/
```

Rebuild index.md to reflect the cleanup.

- [ ] **Step 5: Clean up complete**

All test data removed. The vault is ready for real use.
