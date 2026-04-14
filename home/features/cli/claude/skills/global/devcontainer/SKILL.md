---
name: gb-devcontainer
description: "Generate a .devcontainer/devcontainer.json with Claude Code pre-installed. Use to quickly set up a dev container in any repository."
user-invocable: true
---

# Dev Container with Claude Code

Generate a `.devcontainer/devcontainer.json` in the current project root.

## Steps

1. Create `.devcontainer/` directory if it doesn't exist
2. Write the following `devcontainer.json`:

```json
{
  "name": "Claude code dev container",
  "image": "mcr.microsoft.com/devcontainers/typescript-node:1-22-bookworm",
  "features": {
    "ghcr.io/anthropics/devcontainer-features/claude-code:1.0": {}
  },
  "mounts": [
    "source=${localEnv:HOME}/.claude,target=/home/vscode/.claude,type=bind"
  ],
  "postCreateCommand": "echo 'alias cc=\"claude --dangerously-skip-permissions\"' >> ~/.bashrc",
  "customizations": {
    "vscode": {
      "extensions": ["ms-vscode-remote.remote-containers"]
    }
  }
}
```

3. If a `devcontainer.json` already exists, ask the user before overwriting.
