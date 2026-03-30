{
  config,
  lib,
  pkgs,
  ...
}:

let
  mcpList = [
    "https://github.com/ChromeDevTools/chrome-devtools-mcp"
  ];
in
{
  home.packages = with pkgs; [
    gemini-cli
  ];

  home.activation.installGeminiMCPs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    # Convert the Nix list into a bash array string
    mcp_urls=(${builtins.concatStringsSep " " mcpList})

    for url in "''${mcp_urls[@]}"; do
      # Extract the last part of the URL to guess the folder name
      # Example: https://.../chrome-devtools-mcp becomes chrome-devtools-mcp
      repo_name=$(basename "$url")
      
      # Check if the extension directory already exists
      if [ ! -d "$HOME/.gemini/extensions/$repo_name" ]; then
        
        # Verify if authentication exists before attempting installation.
        # This prevents the Home Manager activation from crashing.
        if [ ! -f "$HOME/.gemini/settings.json" ] && [ -z "$GEMINI_API_KEY" ]; then
          echo "Warning: Authentication not found for Gemini CLI. Skipping MCP: $repo_name"
          echo "Please configure ~/.gemini/settings.json or export GEMINI_API_KEY."
          continue
        fi

        echo "Installing Gemini MCP: $url"
        
        # The '|| true' ensures that even if the CLI fails (e.g., network issue),
        # it won't break the entire system rebuild.
        $DRY_RUN_CMD ${pkgs.gemini-cli}/bin/gemini extensions install "$url" || echo "Failed to install $repo_name, moving on..."
      else
        echo "Gemini MCP $repo_name is already installed."
      fi
    done
  '';
}