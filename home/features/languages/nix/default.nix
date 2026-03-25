{ pkgs, ... }:

{
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    config.global.hide_env_diff = true;
  };

  home.packages = with pkgs; [
    nixd
    nil
    nixfmt

    nix-output-monitor
    nix-index
    nvd

    comma
    nh
  ];

  programs.nix-index = {
    enable = true;
    enableBashIntegration = true;
    enableZshIntegration = true;
  };
}
