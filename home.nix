# home.nix (versão mínima de teste)
{ pkgs, ... }:

{
  # Apenas o essencial para o teste
  home.stateVersion = "24.05";

  # Esta opção deve instalar o comando 'home-manager'
  programs.home-manager.enable = true;

  # Vamos adicionar um único pacote bem pequeno para testar a instalação
  home.packages = [ pkgs.hello ];
}