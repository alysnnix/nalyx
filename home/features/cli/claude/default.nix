{
  pkgs,
  lib,
  config,
  ...
}:
let
  claude-notify = pkgs.writeShellScriptBin "claude-notify" ''
    if command -v powershell.exe &>/dev/null; then
      powershell.exe -Command "[console]::beep(330, 60); [console]::beep(250, 60); [console]::beep(330, 60); [console]::beep(250, 60); [console]::beep(440, 90); [console]::beep(520, 110)" &>/dev/null
    elif command -v paplay &>/dev/null; then
      paplay /usr/share/sounds/freedesktop/stereo/complete.oga &>/dev/null
    fi
    exit 0
  '';

  claude-statusline = pkgs.writeShellScript "claude-statusline" ''
    JQ="${pkgs.jq}/bin/jq"
    input=$(cat)

    model=$(echo "$input" | $JQ -r '.model.display_name // "Unknown"' | sed 's/^Claude //')
    used_pct=$(echo "$input" | $JQ -r '.context_window.used_percentage // empty')

    RST="\033[0m"
    GRN="\033[32m"
    YLW="\033[33m"
    RED="\033[31m"
    DIM="\033[2m"
    PAC="\033[1;33m"

    if [ -n "$used_pct" ]; then
      pct_int=$(printf "%.0f" "$used_pct")
      total=15
      filled=$(( pct_int * total / 100 ))
      [ "$filled" -gt "$total" ] && filled=$total
      remaining=$(( total - filled ))

      if [ "$pct_int" -ge 90 ]; then C="$RED"
      elif [ "$pct_int" -ge 70 ]; then C="$YLW"
      else C="$GRN"
      fi

      eaten=""
      for (( i = 0; i < filled; i++ )); do eaten="''${eaten}·"; done
      dots=""
      for (( i = 0; i < remaining; i++ )); do dots="''${dots}●"; done

      bar="''${DIM}''${eaten}''${RST} ''${PAC}ᗧ ''${RST}''${C}''${dots}''${RST}"
      ctx="''${bar} ''${C}''${pct_int}%''${RST}"
    else
      ctx="''${DIM}ᗧ●●●●●●●●●●●●●●● --%''${RST}"
    fi

    # Alternate dance frames on each update
    if (( $(date +%s) % 2 == 0 )); then
      dance="''${DIM}┗(^o^)┛''${RST}"
    else
      dance="''${DIM}┏(^o^)┓''${RST}"
    fi

    printf "%b" "''${ctx}  ''${DIM}''${RST}$model  $dance"
  '';

  claudeSettingsBase = builtins.toJSON {
    enabledPlugins = {
      "figma@claude-plugins-official" = true;
      "impeccable@pbakaus" = true;
    };
    statusLine = {
      type = "command";
      command = "${claude-statusline}";
    };
    hooks = {
      Stop = [
        {
          matcher = "";
          hooks = [
            {
              type = "command";
              command = "claude-notify";
            }
          ];
        }
      ];
    };
    mcpServers = {
      anytype = {
        command = "npx";
        args = [
          "-y"
          "@anyproto/anytype-mcp"
        ];
        env = {
          OPENAPI_MCP_HEADERS = "__ANYTYPE_TOKEN_PLACEHOLDER__";
        };
      };
      slack = {
        command = "npx";
        args = [
          "-y"
          "@modelcontextprotocol/server-slack"
        ];
        env = {
          SLACK_BOT_TOKEN = "__SLACK_TOKEN_PLACEHOLDER__";
          SLACK_TEAM_ID = "";
        };
      };
    };
  };

  # Skills managed by nix: destination (relative to ~/.claude/skills/) -> source
  # Impeccable skills are managed as a plugin (impeccable@pbakaus) via enabledPlugins
  skillFiles = {
    "global-devcontainer/SKILL.md" = ./skills/global/devcontainer/SKILL.md;
    "global-generate-claude-doc/SKILL.md" = ./skills/global/generate-claude-doc/SKILL.md;
    "global-git-workflow/SKILL.md" = ./skills/global/git-workflow/SKILL.md;

    # Templates - Stack specific rules
    "global-generate-claude-doc/templates/stack/testing-vitest/rules/testing.md" =
      ./skills/global/generate-claude-doc/templates/stack/testing-vitest/rules/testing.md;
    "global-generate-claude-doc/templates/stack/typescript/rules/typescript.md" =
      ./skills/global/generate-claude-doc/templates/stack/typescript/rules/typescript.md;

    # Templates - Universal
    "global-generate-claude-doc/templates/universal/skills/git-workflow/SKILL.md" =
      ./skills/global/generate-claude-doc/templates/universal/skills/git-workflow/SKILL.md;
    "global-generate-claude-doc/templates/universal/rules/quality.md" =
      ./skills/global/generate-claude-doc/templates/universal/rules/quality.md;
  };

  # Build a derivation with all skill files collected in one directory tree
  claudeSkillsSrc = pkgs.runCommandLocal "claude-skills" { } (
    "mkdir -p $out\n"
    + lib.concatStringsSep "\n" (
      lib.mapAttrsToList (dest: src: ''
        mkdir -p "$out/$(dirname '${dest}')"
        cp '${src}' "$out/${dest}"
      '') skillFiles
    )
  );
in
{
  programs.zsh.initContent = ''
    # Root of the nalyx flake — override if you keep the repo elsewhere
    : ''${NALYX_DIR:=$HOME/nalyx}

    # Run Claude Code inside a Nix-built container with full permissions.
    # Mounts the current directory as /workspace plus your ~/.claude settings.
    # On first run (or after cc-rebuild) it builds the image from the flake.
    cc() {
      local image="claude-code-container:latest"

      if ! docker image inspect "$image" >/dev/null 2>&1; then
        echo "🐳 Building claude container from nix (first run)…"
        nix build "$NALYX_DIR#claude-container" --print-out-paths \
          | xargs docker load \
          && echo "✅ Image loaded."
      fi

      docker run --rm -it \
        -v "$(pwd):/workspace" \
        -v "$HOME/.claude:/home/claude/.claude" \
        -v "$HOME/.gitconfig:/home/claude/.gitconfig:ro" \
        -v "$HOME/.ssh:/home/claude/.ssh:ro" \
        -e ANTHROPIC_API_KEY \
        -w /workspace \
        "$image" \
        "$@"
    }

    # Rebuild the container image (run after updating the nix config).
    cc-rebuild() {
      echo "🔨 Rebuilding claude container…"
      docker rmi claude-code-container:latest 2>/dev/null || true
      nix build "$NALYX_DIR#claude-container" --print-out-paths \
        | xargs docker load \
        && echo "✅ Container rebuilt!"
    }
  '';

  home = {
    packages = [
      pkgs.claude-code
      claude-notify
    ];

    # Copy skills as real files so ~/.claude/ stays fully writeable
    # (home.file creates read-only symlinks that break marketplace/plugins)
    activation.claudeSkills = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      SKILLS_DST="$HOME/.claude/skills"
      mkdir -p "$SKILLS_DST"

      # Remove old symlinks from previous home.file approach
      ${pkgs.findutils}/bin/find "$SKILLS_DST" -type l -lname '*/nix/store/*' -delete 2>/dev/null || true

      # Remove stale directories from previous naming schemes
      for old_dir in "$SKILLS_DST"/global "$SKILLS_DST"/impeccable "$SKILLS_DST"/generate-claude-doc; do
        [ -d "$old_dir" ] && rm -rf "$old_dir"
      done

      # Copy managed skills as real writeable files
      cp -rL --no-preserve=mode "${claudeSkillsSrc}/." "$SKILLS_DST/"
    '';

    # Generate settings.json at activation time with sops secret
    # Merges managed keys (plugins, mcpServers) into existing settings
    # so Claude Code can write its own keys (effort, etc.) without being overwritten
    activation.claudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      SETTINGS_FILE="$HOME/.claude/settings.json"
      ANYTYPE_SECRET="/run/secrets/anytype_api_token"
      SLACK_SECRET="/run/secrets/slack_bot_token"
      JQ="${pkgs.jq}/bin/jq"

      mkdir -p "$HOME/.claude"

      # Remove symlink from previous home-manager generation if it exists
      if [ -L "$SETTINGS_FILE" ]; then
        rm "$SETTINGS_FILE"
      fi

      MANAGED=$(echo ${lib.escapeShellArg claudeSettingsBase})

      # Inject Anytype token or remove MCP entry
      if [ -f "$ANYTYPE_SECRET" ]; then
        TOKEN=$(cat "$ANYTYPE_SECRET")
        HEADERS=$($JQ -c -n \
          --arg token "$TOKEN" \
          '{"Authorization": ("Bearer " + $token), "Anytype-Version": "2025-11-08"}')
        MANAGED=$(echo "$MANAGED" | \
          $JQ --arg headers "$HEADERS" \
          '.mcpServers.anytype.env.OPENAPI_MCP_HEADERS = $headers')
      else
        MANAGED=$(echo "$MANAGED" | $JQ 'del(.mcpServers.anytype)')
      fi

      # Inject Slack token or remove MCP entry
      if [ -f "$SLACK_SECRET" ]; then
        SLACK_TOKEN=$(cat "$SLACK_SECRET")
        MANAGED=$(echo "$MANAGED" | \
          $JQ --arg token "$SLACK_TOKEN" \
          '.mcpServers.slack.env.SLACK_BOT_TOKEN = $token')
      else
        MANAGED=$(echo "$MANAGED" | $JQ 'del(.mcpServers.slack)')
      fi

      # Merge: existing settings * managed settings (managed keys win)
      if [ -f "$SETTINGS_FILE" ]; then
        EXISTING=$(cat "$SETTINGS_FILE")
        echo "$EXISTING" | $JQ --argjson managed "$MANAGED" '. * $managed' > "$SETTINGS_FILE.tmp"
        mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
      else
        echo "$MANAGED" > "$SETTINGS_FILE"
      fi
    '';
  };
}
