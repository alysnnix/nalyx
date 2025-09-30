{ pkgs, ... }:

{
  home.packages = with pkgs; [
    docker
    docker-compose
  ];

  # virtualisation.docker.enable = true;
  # users.extraGroups.docker.members = [ "aly" ];
}
