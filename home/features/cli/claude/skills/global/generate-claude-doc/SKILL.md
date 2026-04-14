---
name: gb-generate-claude-doc
description: Generate a complete .claude folder structure for any project, including CLAUDE.md, rules, and custom skills. Use when setting up a new project or adding Claude Code support to an existing codebase.
argument-hint: "[project-name or description]"
user-invocable: true
---

# Generate Complete .claude Structure

Create a comprehensive `.claude/` folder structure for this project that includes:

1. **CLAUDE.md** - Main project documentation
2. **rules/** - Context-specific coding rules (from templates + custom)
3. **skills/** - Custom exploration skills for project domains

## Templates Location

This skill includes pre-built templates at:

```
~/.claude/skills/generate-claude-doc/templates/
├── universal/                    # ALWAYS copy these
│   ├── rules/
│   │   └── quality.md            # Test coverage & commit quality rules
└── stack/                        # Copy if stack detected
    ├── typescript/rules/typescript.md
    └── testing-vitest/rules/testing.md
```

---

## Phase 1: Exploration

Before generating anything, explore the codebase:

### 1.1 Identify Stack

```bash
# Check for package manager and configs
ls package.json Cargo.toml go.mod pyproject.toml 2>/dev/null
```

Read the main config to identify:

| Detection | Template to Copy |
|-----------|------------------|
| `*.ts`, `*.tsx` files | `stack/typescript/rules/typescript.md` |
| `vitest` in package.json | `stack/testing-vitest/rules/testing.md` |
| `jest` in package.json | Adapt testing template for Jest |

### 1.2 Analyze Project Structure

Glob for `src/**/*`, `app/**/*`, `lib/**/*` to understand the architecture.

### 1.3 Identify Main Domains

Look at the code to identify 3-5 main features/domains that need exploration skills.

---

## Phase 2: Copy Universal Templates

**ALWAYS** copy these to the project (non-negotiable):

### Quality Rules (MANDATORY)

```bash
# Copy from:
~/.claude/skills/generate-claude-doc/templates/universal/rules/quality.md

# To:
.claude/rules/quality.md
```

This file enforces:
- **100% test coverage** for all new code
- **All tests must pass** before any commit
- **Each commit must be complete** - code 100% functional
- **No exceptions** - every feature/change needs tests

Read each template file and write it to the project. Adapt if the project has specific conventions.

---

## Phase 3: Copy Stack Templates

Based on detected stack, copy relevant templates:

### TypeScript Project

```bash
# If *.ts or *.tsx files exist
# Copy templates/stack/typescript/rules/typescript.md
# To: .claude/rules/typescript.md
```

### Vitest/Jest Testing

```bash
# If vitest or jest in package.json
# Copy templates/stack/testing-vitest/rules/testing.md
# To: .claude/rules/testing.md
# Adapt imports if using Jest instead of Vitest
```

**Important:** Read each template file and write to the target location. Adapt paths and conventions to match the specific project.

---

## Phase 4: Generate CLAUDE.md

Create `.claude/CLAUDE.md` with project-specific content:

```markdown
# Project Name

One-line description of what the project does.

## Quick Start

\`\`\`bash
npm install     # or detected package manager
npm run dev     # detected dev command
npm run build   # detected build command
npm run test    # detected test command
npm run lint    # detected lint command
\`\`\`

## Critical Rules (if any)

\`\`\`
CRITICAL SECURITY/BUSINESS RULE
\`\`\`

- Explanation
- What to do / what NOT to do

## Stack

| Layer | Technologies |
|-------|--------------|
| Frontend | Detected frontend stack |
| Backend | Detected backend stack |
| Database | Detected database |
| Infrastructure | Detected infra |

## Architecture

\`\`\`
src/
├── detected/
│   └── structure/
\`\`\`

## Key Tables/Models

| Table | Description |
|-------|-------------|
| Detected tables from schema |

## Roles & Routes (if applicable)

| Role | Access |
|------|--------|
| Detected roles and routes |

## Coding Conventions

- Detected conventions from configs and existing code

## Quality Rules (MANDATORY)

@.claude/rules/quality.md

## Additional Rules

@.claude/rules/typescript.md
@.claude/rules/testing.md
@.claude/rules/[other-detected-rules].md
```

---

## Phase 5: Generate Domain Skills

Create exploration skills for each main domain identified:

### Skill Template

For each domain, create `.claude/skills/explore-[domain]/SKILL.md`:

```markdown
---
name: explore-[domain]
description: "Explore [domain]. Use when debugging [X], fixing [Y], or understanding how [Z] works."
user-invocable: true
---

# Domain Name

## Overview

| Aspect | Value |
|--------|-------|
| Main Route | `/detected-route` |
| Entry Point | `src/detected/path.tsx` |
| Access | Detected access level |

## Flow

1. Detected flow step 1
2. Step 2
3. Step 3

## Key Files

\`\`\`
src/detected/files.tsx
src/components/Related.tsx
\`\`\`

## Related Tables

- `detected_table` - description

## Important Patterns

\`\`\`typescript
// Detected patterns from the codebase
\`\`\`
```

---

## Phase 6: Optional settings.local.json

Only create if project needs specific permissions:

```json
{
  "permissions": {
    "allow": [
      "Bash(npm run:*)",
      "Bash(git add:*)",
      "Bash(git commit:*)",
      "Bash(git push:*)"
    ]
  }
}
```

---

## Output Checklist

| File | Source | Required |
|------|--------|----------|
| `.claude/CLAUDE.md` | Generated | **Yes** |
| `.claude/rules/quality.md` | Universal template | **Yes (MANDATORY)** |
| `.claude/rules/typescript.md` | Stack template | If TypeScript |
| `.claude/rules/testing.md` | Stack template | If Vitest/Jest |
| `.claude/skills/explore-*/SKILL.md` | Generated | 3-5 domains |
| `.claude/settings.local.json` | Generated | Optional |

---

## Execution Steps

1. **Explore** codebase structure and dependencies
2. **Read** universal templates from `~/.claude/skills/generate-claude-doc/templates/universal/`
3. **Read** relevant stack templates from `~/.claude/skills/generate-claude-doc/templates/stack/`
4. **Create** `.claude/` folder structure
5. **Write** CLAUDE.md with project-specific content
6. **Write** copied templates (adapted to project)
7. **Write** domain exploration skills
8. **Verify** all files are linked correctly in CLAUDE.md

---

## Guidelines

1. **Read templates first**: Always read the template files before writing
2. **Adapt to project**: Modify templates to match project conventions
3. **Match language**: Use same language as project (Portuguese/English)
4. **Be specific**: Use actual paths, tables, patterns from the codebase
5. **Stay concise**: Every line should be useful
6. **Don't duplicate**: If project already has rules, merge instead of overwrite

---

Start by exploring the codebase, then read the templates, then generate the complete structure.