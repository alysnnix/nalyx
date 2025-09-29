{ pkgs, ... }:

{
  home.packages = with pkgs; [
    wget
    httpie
    bind
    killall
    acpi
    unzip
    file
    zip
  ];
}
