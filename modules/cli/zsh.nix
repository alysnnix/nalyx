{ pkgs, ... }:

{
  programs.zsh = {
    enable = true;
    enableAutosuggestions = true;
    enableSyntaxHighlighting = true;
    autocd = true;
    shellAliases = {
      ll = "ls -lha";
      update = "cd ~/nix-config && home-manager switch --flake .#aly";
      zshrc = "code ~/.zshrc";
      bashrc = "code ~/.bashrc";
    };
    oh-my-zsh = {
      enable = true;
      theme = "robbyrussell";
      plugins = [ "git" ];
    };
    history = {
      expireDuplicatesFirst = true;
      extended = true;
      ignoreAllDups = true;
      ignoreDups = true;
      ignoreSpace = true;
    };
    initExtra = ''
      # --- ADICIONE ESTE BLOCO ---
      # Garante que o ambiente Nix seja carregado no shell
      if [ -e "$HOME/.nix-profile/etc/profile.d/nix-daemon.sh" ]; then
        . "$HOME/.nix-profile/etc/profile.d/nix-daemon.sh"
      fi
      # --- FIM DO BLOCO ---

      # --- ADICIONE ESTA LINHA ---
      # Ativa o corepack manualmente ao iniciar o shell
      corepack enable

      # Script do Tab inteligente (que já estava aqui)
      zle -N autosuggest-accept-or-complete _autosuggest-accept-or-complete
      _autosuggest-accept-or-complete() {
        if [[ -n "''${ZSH_AUTOSUGGEST_SUGGESTION-}" ]]; then
          zle autosuggest-accept
        else
          zle expand-or-complete
        fi
      }
      bindkey '^I' autosuggest-accept-or-complete
    '';
  };
}
