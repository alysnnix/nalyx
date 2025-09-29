{ pkgs, ... }:

{
  home.packages = with pkgs; [
    wget
    pciutils
    httpie
    bind
    killall
    acpi
    unzip
    file
    zip
    gptfdisk

    neofetch
    bat
    eza

    silver-searcher
    nix-index
  ];
}
