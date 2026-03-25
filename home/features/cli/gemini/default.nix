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
        echo "Installing Gemini MCP: $url"
        $DRY_RUN_CMD ${pkgs.gemini-cli}/bin/gemini extensions install "$url"
      else
        echo "Gemini MCP $repo_name is already installed."
      fi
    done
  '';
}
