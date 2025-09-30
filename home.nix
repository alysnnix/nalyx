# home.nix (versão mínima CORRIGIDA)
{ pkgs, ... }:

{
  # --- ADICIONE ESTAS LINHAS ---
  home.username = "aly";
  home.homeDirectory = "/home/aly";
  # ---------------------------

  home.stateVersion = "24.05";

  # Esta opção deve instalar o comando 'home-manager'
  programs.home-manager.enable = true;

  # Pacote de teste
  home.packages = [ pkgs.hello ];
}