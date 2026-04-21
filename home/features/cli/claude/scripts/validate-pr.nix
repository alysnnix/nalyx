{ pkgs }:

pkgs.writeShellScriptBin "claude-validate-pr" ''
  # Reads tool input from stdin, blocks `gh pr create --base main` when develop exists
  INPUT=$(cat)
  COMMAND=$(echo "$INPUT" | ${pkgs.jq}/bin/jq -r '.command // empty' 2>/dev/null)

  # Only check commands that create PRs
  if echo "$COMMAND" | grep -q "gh pr create"; then
    # If --base main is explicitly used, check if develop exists
    if echo "$COMMAND" | grep -qE '\-\-base\s+main'; then
      if git ls-remote --heads origin develop &>/dev/null | grep -q develop; then
        echo "BLOCKED: This repo has a develop branch. Use --base develop instead of --base main."
        exit 2
      fi
    fi
  fi

  exit 0
''
