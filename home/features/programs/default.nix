{ pkgs, ... }:
{
  imports = [
    ./vscode
    ./zed
    ./docker
    ./obs
    ./firefox
    ./games
  ];

  home.packages = with pkgs; [
    discord
    k6
    vegeta
    moonlight-qt
    parsec-bin
    postman
    postgresql
    pritunl-client
  ];
}
