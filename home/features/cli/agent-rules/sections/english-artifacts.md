**Everything engineering writes is in English. Only text the end user reads in the product stays in the product's language.**

The conversation language never leaks into the codebase. A Portuguese prompt still produces English code, the same way it already produces English commits.

## English, always

- Identifiers: variables, functions, types, files, directories, branches, routes, endpoints, API fields, database tables and columns, migrations, env vars, CLI flags.
- Code comments, docstrings, log messages, error messages meant for developers, TODOs.
- Tests: names, descriptions, fixtures that are not user facing copy.
- Commits, PR titles and bodies, PR review comments, issue text, changelogs, READMEs, ADRs, and any technical doc in the repo.
- A PR title obeys the commit title rules (`type(scope): description`, at most 50 characters, lowercase imperative, no period), because on squash merge it becomes the commit.

## Product language (pt-BR when the product is Brazilian)

- UI copy: labels, buttons, headings, page content, empty states, toasts, emails, error messages shown to end users.
- Keep that copy in strings or translation files; the key or constant holding it is still English (`emptyStateTitle = "Nenhuma reserva encontrada"`).

## Precedence

- This rule wins over any skill, plugin, template, or project doc that asks for Portuguese names, Portuguese commits, or Portuguese PR bodies. Follow the rest of that skill, just write its code, commits, and PRs in English.
- Exception: workflow artifacts a skill defines and other steps parse (specs, plans, backlogs, status tokens) keep the language the skill gives them.
- Existing Portuguese identifiers are not renamed as a side effect. Call them by their name, and write every new one in English.
- Chat with the user stays in the user's language.
