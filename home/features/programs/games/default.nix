{
  pkgs,
  ...
}:
{
  home.packages = with pkgs; [
    mangohud
    lutris
    protonup-qt
  ];

  programs.mangohud = {
    enable = true;
    settings = {
      full = true;
      force_ppp = true;
      cpu_temp = true;
      gpu_temp = true;
      ram = true;
      fps = true;
    };
  };
}
