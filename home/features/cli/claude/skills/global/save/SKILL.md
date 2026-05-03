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
