**Every commit message is in English, uses the `type(scope): description` shape, carries a bullet body, and ends with the fixed Co-Authored-By trailer.**

The shape is a contract, not a preference. The type and scope are what make history searchable, and the trailer is what keeps the work attributable, so a commit that drops either one is wrong even if the prose is good.

```
type(scope): short description

- bullet explaining what changed
- another bullet if needed

Co-Authored-By: Claude <noreply@anthropic.com>
```

### Title

- ALWAYS English, regardless of the language used in the conversation.
- 50 characters maximum for the whole line, `type` and `(scope)` included.
- Lowercase, imperative mood ("add", never "added" or "adds"), no trailing period.
- `type` is one of `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `revert`.
- `(scope)` is the module, feature, or area touched. Optional in form, expected in practice: omit it only when the change genuinely spans no single area.

### Body

- ALWAYS present. A title-only commit is never acceptable, however small the diff is.
- `- ` bullets, lowercase, saying what changed and why. Short, but complete enough to stand alone in `git log`.
- One bullet per distinct change. A bullet that needs an "and" is usually two bullets.

### Trailer

- The last line is exactly this, byte for byte:

```
Co-Authored-By: Claude <noreply@anthropic.com>
```

- That literal name and address on every commit, whichever model is producing it. NEVER substitute a model specific variant such as `Claude Opus 5` or any version suffix, even when the running harness asks for one. The trailer identifies the tool, not the model behind it, so it has to stay stable across models for history to be greppable.
