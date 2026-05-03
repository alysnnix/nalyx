# `/save` Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a user-invocable `/save` skill that captures the active Claude Code conversation into the Obsidian-synced vault, generates a curated summary, commits, and pushes.

**Architecture:** A single SKILL.md file. No helper scripts, no new Nix modules — only one Nix mapping addition. The skill instructs Claude to use its existing tools (`Bash`, `Read`, `Write`, `Edit`) to do all work.

**Tech Stack:** Markdown (SKILL.md), Nix (Home Manager), bash + git in skill instructions. Vault target: `~/nalyx/.private/notes/claude/conversations/`.

**Spec:** [`docs/superpowers/specs/2026-05-03-save-skill-design.md`](../specs/2026-05-03-save-skill-design.md)

---

## File Structure

| Path | Action | Responsibility |
|---|---|---|
| `home/features/cli/claude/skills/global/save/SKILL.md` | create | Skill instructions (the heart of the feature) |
| `home/features/cli/claude/skills/files.nix` | modify | Add the new skill to the Nix-managed mapping |

---

### Task 1: Create the `save` skill file

**Files:**
- Create: `home/features/cli/claude/skills/global/save/SKILL.md`

- [ ] **Step 1: Create directory**

```bash
mkdir -p /home/aly/nalyx/home/features/cli/claude/skills/global/save
```

- [ ] **Step 2: Write SKILL.md with the exact content below**

Path: `home/features/cli/claude/skills/global/save/SKILL.md`

````markdown
---
name: save
description: "Dump the current Claude Code conversation to the Obsidian notes vault. Generates a titled summary, copies the raw transcript, commits and pushes so it syncs across hosts. Triggers: '/save', 'save this conversation', 'archive this session'."
user-invocable: true
---

# `/save` — Archive Conversation to Notes Vault

Save the active Claude Code conversation to `~/nalyx/.private/notes/claude/conversations/` as a self-contained folder with: a curated summary (`summary.md`), a human-readable rendered transcript (`transcript.md`), and the raw JSONL (`transcript.jsonl`). Then commit and push so other hosts pick it up.

## Vault check

Before doing anything else:

```bash
ls ~/nalyx/.private/notes/claude/ 2>/dev/null
```

If the directory does not exist, tell the user **"Vault not found at `~/nalyx/.private/notes/`. Run `switch` to clone it."** and stop. Do not create any files.

## Step 1 — resolve session paths

```bash
CWD="$(pwd)"
ENCODED_CWD="$(echo "$CWD" | tr '/' '-')"          # /home/aly/nalyx → -home-aly-nalyx
JSONL="$(ls -t ~/.claude/projects/$ENCODED_CWD/*.jsonl 2>/dev/null | head -1)"
[ -z "$JSONL" ] && { echo "No active Claude Code session found for cwd $CWD"; exit 1; }
SESSION_ID="$(basename "$JSONL" .jsonl)"
HOST="$(hostname)"
DATE="$(date +%F)"                                  # YYYY-MM-DD
echo "JSONL: $JSONL"
echo "Session: $SESSION_ID  Host: $HOST  Date: $DATE"
```

If the `ls` returns nothing, abort with the printed message — do not invent a path.

## Step 2 — read and analyze the JSONL

Use the `Read` tool on `$JSONL`. From the conversation, derive:

- **`title`** — a human-readable, descriptive title in Portuguese or English matching the conversation language. Aim for something an Obsidian search would surface (e.g. "Design da skill /save", not "Conversa de hoje"). 4–8 words ideal.
- **`slug`** — kebab-case version of the title, lowercase, ASCII only, max 60 characters, no stopwords ("a", "o", "the", "and", "de", "do", "da" — drop them).
- **`tags`** — 3-6 tags inferred from the actual conversation content. Not from `cwd`. Not heuristics. Read the conversation and pick.
- **`summary text`** — the four sections of `summary.md` (see template below), filled from the conversation.

If the conversation is very short (fewer than ~4 user messages), tell the user "this conversation is short, summary will be thin — proceed?" and wait. Otherwise proceed.

## Step 3 — create the conversation folder

```bash
DIR="$HOME/nalyx/.private/notes/claude/conversations/$DATE/$SLUG"
# collision handling
i=2
while [ -e "$DIR" ]; do
  DIR="$HOME/nalyx/.private/notes/claude/conversations/$DATE/$SLUG-$i"
  i=$((i + 1))
done
mkdir -p "$DIR"
echo "DIR: $DIR"
```

Use the actual `$SLUG` you computed.

## Step 4 — copy raw transcript

```bash
cp "$JSONL" "$DIR/transcript.jsonl"
```

This is verbatim. Do not transform.

## Step 5 — render `transcript.md`

Read the JSONL line-by-line (you already have it in context from Step 2) and write a human-readable markdown rendering. Mapping:

| JSONL entry | Rendering |
|---|---|
| `type: file-history-snapshot` | drop |
| `type: user`, `message.content` is string | `## 👤 User\n\n<content>` |
| `type: user`, `tool_result` blocks | `> **Tool result** (<tool>):` then first ~20 lines of the result, then `... (truncated, N more lines)` if longer |
| `type: assistant`, `text` blocks | `## 🤖 Assistant\n\n<text>` |
| `type: assistant`, `tool_use` blocks | `> **Tool**: <name> <args summary>` (one-line, args truncated to ~120 chars) |
| Embedded base64 images | `_[image elided]_` |
| `<system-reminder>` blocks inside content | `_[system reminder]_` |

Header of the file:

```markdown
# <SESSION_ID short — first 8 chars> — <DATE> <first message HH:MM> → <last message HH:MM>
**cwd**: <CWD> | **branch**: <git branch if available> | **host**: <HOST>

```

Then write the rendered conversation. Use `Write` tool to save `$DIR/transcript.md`.

## Step 6 — write `summary.md`

Use the template below. Fill every field. Use `Write` tool to save `$DIR/summary.md`.

```markdown
---
type: conversation
title: "<TITLE>"
session_id: <SESSION_ID>
cwd: <CWD>
host: <HOST>
date: <DATE>
duration_minutes: <MINUTES>     # last_msg_ts - first_msg_ts, in minutes, integer
tags: [<tag1>, <tag2>, ...]
---

# <TITLE>

## Resumo
<3–5 sentences. What the conversation covered, what problem was tackled, end state.>

## Tópicos principais
- <bullet>
- <bullet>

## Decisões / artefatos produzidos
- <files edited, commands run, PRs opened, decisions made>
- <inline code fences for important snippets when they aid understanding>

## Próximos passos
- <TODO if any; if none, write "Nenhum.">

---
[transcript renderizado](transcript.md) · [transcript bruto](transcript.jsonl)
```

Write in the language of the conversation (PT-BR if user writes in Portuguese, English otherwise).

## Step 7 — update `conversations/index.md`

```bash
INDEX="$HOME/nalyx/.private/notes/claude/conversations/index.md"
[ ! -f "$INDEX" ] && printf '# Conversations\n\n' > "$INDEX"
```

Then prepend a new entry **right after the `# Conversations` heading** (newest first). Use the `Edit` tool to insert this exact line:

```markdown
- [<TITLE>](<DATE>/<SLUG>/summary.md) — <one-line hook, ≤ 80 chars>
```

Where `<one-line hook>` is a single sentence — what the conversation accomplished. Not a duplicate of the title.

## Step 8 — git: pull, commit, push

```bash
cd "$HOME/nalyx/.private/notes" || exit 1

git pull --rebase origin main || {
  echo "rebase failed — resolve manually. Files are saved locally at $DIR";
  exit 1;
}

git add "claude/conversations/$DATE/$(basename "$DIR")/" \
        "claude/conversations/index.md"

git commit -m "$(cat <<EOF
chore(conversations): save "<TITLE>"

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"

git push origin main || {
  echo "push failed (network/auth). Commit is local at $(git rev-parse HEAD). Retry: git push";
  exit 1;
}
```

Substitute `<TITLE>` literally in the commit message.

## Step 9 — report to the user

Print exactly:

```
Saved to claude/conversations/<DATE>/<SLUG>/
Pushed to origin/main.
```

If anything failed (rebase, push), report the failure and where the local files live.

## Notes

- Never force-push. Never `--no-verify`. Never stash other vault edits.
- Never overwrite an existing folder — collision handling in Step 3 is mandatory.
- The skill does not call `/rename`. The Claude Code session title is unchanged. The slug + filename are the durable identifier.
- This skill is the conversation-archive counterpart to the `notes` skill (which curates structural knowledge in `works/`, `personal/`, `meets/`). Don't confuse the two.
````

- [ ] **Step 3: Verify the file exists and frontmatter is correct**

```bash
head -5 /home/aly/nalyx/home/features/cli/claude/skills/global/save/SKILL.md
```

Expected output:
```
---
name: save
description: "Dump the current Claude Code conversation to the Obsidian notes vault. ..."
user-invocable: true
---
```

- [ ] **Step 4: Commit**

```bash
cd /home/aly/nalyx
git add home/features/cli/claude/skills/global/save/SKILL.md
git commit -m "$(cat <<'EOF'
feat(save-skill): add /save skill source

- skill instructions for archiving conversations to obsidian vault
- summary.md + transcript.md + transcript.jsonl per conversation
- handles collisions, vault check, git pull --rebase before push

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Wire the skill into Nix

**Files:**
- Modify: `home/features/cli/claude/skills/files.nix:7-12`

- [ ] **Step 1: Read the current `files.nix`**

```bash
cat /home/aly/nalyx/home/features/cli/claude/skills/files.nix
```

You should see a `skillFiles` attribute set with 6 entries (gb-open-pr, gb-check-alfred-review, gb-merge-dev, gb-co-authored, gb-pipefy, gb-coolify).

- [ ] **Step 2: Add the new mapping**

Use `Edit` to change:

```nix
  skillFiles = {
    "gb-open-pr/SKILL.md" = ./global/open-pr/SKILL.md;
    "gb-check-alfred-review/SKILL.md" = ./global/check-review/SKILL.md;
    "gb-merge-dev/SKILL.md" = ./global/merge-dev/SKILL.md;
    "gb-co-authored/SKILL.md" = ./global/co-authored/SKILL.md;
    "gb-pipefy/SKILL.md" = ./global/pipefy/SKILL.md;
    "gb-coolify/SKILL.md" = ./global/gb-coolify/SKILL.md;
  };
```

To:

```nix
  skillFiles = {
    "gb-open-pr/SKILL.md" = ./global/open-pr/SKILL.md;
    "gb-check-alfred-review/SKILL.md" = ./global/check-review/SKILL.md;
    "gb-merge-dev/SKILL.md" = ./global/merge-dev/SKILL.md;
    "gb-co-authored/SKILL.md" = ./global/co-authored/SKILL.md;
    "gb-pipefy/SKILL.md" = ./global/pipefy/SKILL.md;
    "gb-coolify/SKILL.md" = ./global/gb-coolify/SKILL.md;
    "save/SKILL.md" = ./global/save/SKILL.md;
  };
```

(Note: kept all existing entries unchanged. The new entry deliberately has no `gb-` prefix because this skill is not a gb-team skill — it's a personal nalyx skill, and the user invokes it as `/save`, so the destination path matches the slash command name.)

- [ ] **Step 3: Format**

```bash
cd /home/aly/nalyx
nix fmt home/features/cli/claude/skills/files.nix
```

- [ ] **Step 4: Validate the flake**

```bash
cd /home/aly/nalyx
nix flake check --no-build
```

Expected: no errors. If `statix`/`deadnix` complain, fix and re-run.

- [ ] **Step 5: Commit**

```bash
cd /home/aly/nalyx
git add home/features/cli/claude/skills/files.nix
git commit -m "$(cat <<'EOF'
feat(claude): wire /save skill into nix

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Apply the configuration and verify symlink

**Files:** none (rebuilds Home Manager)

- [ ] **Step 1: Rebuild**

```bash
cd /home/aly/nalyx
switch
```

Expected: rebuild completes with no errors. The `switch` script auto-detects the current host.

- [ ] **Step 2: Verify the skill landed in `~/.claude/skills/`**

```bash
ls -la ~/.claude/skills/save/
cat ~/.claude/skills/save/SKILL.md | head -5
```

Expected:
- `save/` directory exists
- `SKILL.md` is a regular file (Home Manager copies skills as real files via `activation/skills.nix:23`)
- Frontmatter shows `name: save`, `user-invocable: true`

- [ ] **Step 3: Confirm it's discoverable as a slash command**

This step is verified by the user in the next Claude Code session. Print to the user:

> Restart your Claude Code session. Run `/save` in a fresh session — autocomplete should list it. Do not run `/save` to verify, because that would actually save and commit. Just confirm autocomplete shows it.

---

### Task 4: Smoke test (manual, by user)

**Files:** none — this is human verification.

- [ ] **Step 1: Print smoke test instructions to the user**

> To smoke test:
>
> 1. Open a fresh Claude Code session in any cwd (e.g. `cd ~/nalyx && claude`).
> 2. Have a brief throwaway conversation (3-4 turns).
> 3. Run `/save`.
> 4. Verify:
>    - `ls ~/nalyx/.private/notes/claude/conversations/$(date +%F)/`
>    - The folder contains `summary.md`, `transcript.md`, `transcript.jsonl`
>    - `cat ~/nalyx/.private/notes/claude/conversations/index.md` shows the new entry on top
>    - `cd ~/nalyx/.private/notes && git log -1` shows the new commit
>    - `git push` already happened (no unpushed commits ahead)
> 5. On a second host with the vault cloned, run `git pull` in the notes repo and confirm the new conversation appears.
>
> If anything is off, report which step failed.

- [ ] **Step 2: Wait for user confirmation before declaring done**

Do not mark the implementation complete until the user reports a successful smoke test or asks for a fix.

---

## Self-review checklist (executed before handoff)

- [x] Spec coverage — all sections of the spec (vault layout, naming, summary template, transcript rendering, index, components, flow, failure handling, Nix integration) are implemented in Tasks 1–3.
- [x] No placeholders — every step has concrete code or commands.
- [x] Type/name consistency — `<SLUG>`, `<TITLE>`, `<DATE>`, `$DIR`, `$JSONL` used identically across steps.
- [x] No tests — explicitly out of scope per spec; smoke test is the verification.
