---
paths:
  - "**/*"
---

# Quality Rules

## CRITICAL: Test Coverage Requirement

```
EVERY FEATURE OR CHANGE MUST HAVE 100% TEST COVERAGE
```

- **No exceptions**: Every new code must have corresponding tests
- **Tests first**: Write or update tests before implementing changes
- **All tests must pass**: Never commit with failing tests
- **Each commit must be complete**: Code must be 100% functional in every commit

## Before Writing Code

1. Identify what needs to be tested
2. Write test cases (or update existing ones)
3. Verify tests fail for the right reason (TDD)
4. Implement the feature/fix
5. Verify all tests pass

## Before Every Commit

```bash
# 1. Run ALL tests
npm run test          # or yarn test, pnpm test, cargo test, go test, pytest

# 2. Verify coverage (if available)
npm run test:coverage

# 3. Run linting
npm run lint

# 4. Verify build works
npm run build
```

### Commit Checklist

```
[ ] All tests passing
[ ] New code has tests
[ ] Test coverage maintained/improved
[ ] No skipped tests (.skip, .only, @skip)
[ ] Linting passes
[ ] Build succeeds
[ ] Code is 100% functional
```

## Test Requirements by Change Type

| Change Type | Test Requirement |
|-------------|------------------|
| New feature | Full test coverage for all new code |
| Bug fix | Test that reproduces the bug + fix verification |
| Refactor | Existing tests still pass + new tests if behavior changes |
| API change | Integration tests + unit tests |
| UI component | Component tests + interaction tests |
| Utility function | Unit tests with edge cases |

## What to Test

### Functions/Methods

```
[ ] Happy path (expected inputs)
[ ] Edge cases (empty, null, undefined, boundaries)
[ ] Error cases (invalid inputs, exceptions)
[ ] Return values
[ ] Side effects
```

### Components (React/Vue/etc)

```
[ ] Renders correctly
[ ] Props work as expected
[ ] User interactions (click, input, etc)
[ ] Loading states
[ ] Error states
[ ] Empty states
[ ] Accessibility (aria labels, roles)
```

### API/Backend

```
[ ] Success responses
[ ] Error responses (400, 401, 403, 404, 500)
[ ] Input validation
[ ] Authentication/Authorization
[ ] Edge cases
```

## Forbidden Practices

```typescript
// NEVER commit these:

test.skip('some test')     // No skipped tests
test.only('some test')     // No isolated tests
it.skip('some test')
describe.skip('some suite')

// @ts-ignore without explanation
// eslint-disable without explanation

console.log() // Remove debug logs before commit
```

## If Tests Are Missing

When working on code without tests:

1. **Before making changes**: Write tests for existing behavior
2. **After writing tests**: Verify they pass with current code
3. **Make your changes**: Update tests as needed
4. **Verify**: All tests pass with new code

## Coverage Enforcement

If the project has coverage tools configured:

```bash
# Check coverage before commit
npm run test:coverage

# Minimum thresholds (configure per project)
# Statements: 80%+
# Branches: 80%+
# Functions: 80%+
# Lines: 80%+
```

## Breaking the Build = Blocking

If tests fail or coverage drops:

1. **DO NOT** commit
2. **DO NOT** push
3. **FIX** the issue first
4. **VERIFY** all tests pass
5. **THEN** commit

## Summary

```
NO TEST = NO COMMIT
FAILING TEST = NO COMMIT
INCOMPLETE CODE = NO COMMIT
```
