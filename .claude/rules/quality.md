---
paths:
  - "**/*"
---

# Quality Rules

## CRITICAL: Validation Before Commit

```
EVERY CHANGE MUST BE VALIDATED BEFORE COMMIT
```

- **No exceptions**: Every change must pass the checks
- **Validate first**: Run checks before committing
- **Each commit must be functional**: System must rebuild without errors

## Before Each Commit

```bash
# 1. Format code
nix fmt

# 2. Validate configurations (without building)
nix flake check --no-build

# 3. Test rebuild (optional, but recommended)
sudo nixos-rebuild dry-run --flake .#<host>
```

### Commit Checklist

```
[ ] Code formatted (nix fmt)
[ ] Flake check passes
[ ] No broken imports
[ ] No syntax errors
[ ] Variables used correctly
```

## Requirements by Change Type

| Change Type | Requirement |
|-------------|-------------|
| New module | Verify imports, test with dry-run |
| Host change | Test rebuild of the specific host |
| Change in vars.nix | Verify all hosts |
| New package | Verify it exists in nixpkgs |
| Driver/Hardware | Test in real environment |

## What to Verify

### Nix Modules

```
[ ] Correct imports (paths exist)
[ ] Well-formed attributes
[ ] Defined variables are used
[ ] No dead code (deadnix)
[ ] Correct formatting (nixfmt)
```

### Program Configurations

```
[ ] Package exists in nixpkgs
[ ] Valid configuration for the program
[ ] Correct file paths
[ ] Proper permissions
```

## Forbidden Practices

```nix
# NEVER commit:

# Imports of nonexistent files
imports = [ ./does-not-exist.nix ];

# Undefined variables
programs.${undefined}.enable = true;

# Commented-out code without purpose
# imports = [ ./old ]; # TODO: remove

# Manually edited hardware-configuration.nix
```

## If the Check Fails

1. **DO NOT** commit
2. **DO NOT** use --no-verify
3. **FIX** the problem
4. **VERIFY** again
5. **THEN** commit

## Summary

```
FLAKE CHECK FAILED = DO NOT COMMIT
WRONG FORMAT = DO NOT COMMIT
REBUILD FAILED = DO NOT COMMIT
```
