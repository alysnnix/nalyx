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
        if [ ! -f "$HOME/.gemini/settings.json" ] && [ -z "''${GEMINI_API_KEY:-}" ]; then
          echo "Warning: Authentication not found for Gemini CLI. Skipping MCP: $repo_name"
          echo "Please configure ~/.gemini/settings.json or export GEMINI_API_KEY."
          continue
        fi

        echo "Installing Gemini MCP: $url"

        # `--consent` e o que impede o travamento. Sem ele o CLI abre um prompt
        # de confirmacao no tty, e a ativacao roda dentro de
        # home-manager-aly.service, que nao tem tty nenhum: o comando nao falha,
        # ele espera para sempre, o systemd mata a unit no timeout de 5 min e
        # tudo que viria depois desta activation nao roda. `--skip-settings`
        # tira o segundo prompt, o de configuracao.
        #
        # O `timeout` e cinto de seguranca, nao redundancia: `|| echo` cobre
        # comando que FALHA, e nada aqui cobria comando que PENDURA. Se uma
        # versao futura do CLI reintroduzir uma pergunta, isto vira um aviso de
        # dois minutos em vez de uma ativacao quebrada.
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/timeout 120 \
          ${pkgs.gemini-cli}/bin/gemini extensions install "$url" --consent --skip-settings \
          < /dev/null || echo "Failed to install $repo_name, moving on..."
      else
        echo "Gemini MCP $repo_name is already installed."
      fi
    done
  '';
}
