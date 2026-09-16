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
    impression
    k6
    vegeta
    moonlight-qt
    parsec-bin
    postman
    # SQL client GUI, next to the postgresql client tools it complements.
    # `-bin` is upstream's own build, and the only dbeaver attr nixpkgs still
    # carries: a plain `dbeaver` does not resolve on this pin.
    dbeaver-bin
    postgresql
    pritunl-client
  ];
}
