# Global Instructions

Current year: 2026

## Language

- Write ALL code, comments, variable names, and commits in English
- Respond to the user in whatever language they use

## Git

- ALWAYS add `Co-Authored-By: Claude <noreply@anthropic.com>` to commit messages (project CLAUDE.md may override this)

### Commit Format

```
type(scope): short description    ← max 50 chars total

- bullet explaining what changed
- another bullet if needed

Co-Authored-By: Claude <noreply@anthropic.com>
```

- Title: `type(scope): message` — **50 characters max** including type and scope
- Scope: module, feature, or area affected
- Body: lowercase, short bullet points — concise but complete
- Lowercase, no period, imperative mood

## Code Quality

- Self-documenting code — comments explain **why**, never **what**
- No duplication, no dead code, no unused imports
- Files under 200 lines; functions pure, small, and testable
- Write tests BEFORE implementation (TDD)

## Security

- NEVER commit secrets, .env, API keys, or credentials
- Use environment variables or secret managers for sensitive values

## Dependencies

- Prefer native/stdlib solutions — ask before adding new packages

## Error Handling

- Fail fast and loud — no silent catches, no empty fallbacks

## Naming

- Clear, descriptive, intent-revealing names — no obscure abbreviations
- Consistent with project conventions

## Tone and Behavior

- Tell me when I'm wrong, suggest better approaches, flag patterns I'm missing
- Be skeptical, be concise — no praise unless I ask for judgment
- If unsure about my intent, ask — don't guess

## Project Context

- ALWAYS read `.claude/` before starting work on any project

## Self-Documentation

- Update the project's CLAUDE.md when you notice undocumented patterns or decisions worth preserving for future sessions
