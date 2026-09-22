{
  pkgs,
  ...
}:
{
  home.packages = with pkgs; [
    mangohud
    # O lutris do nixpkgs é um buildFHSEnv: nada do PATH de fora existe lá
    # dentro. Os toggles "Enable Feral GameMode" e "FPS counter (MangoHud)" da
    # UI, então, falham em silêncio a menos que os dois entrem no ambiente.
    #
    # extraPkgs vai para targetPkgs (64 bits, onde o gamemoderun e o JSON da
    # camada Vulkan do MangoHud precisam estar) e extraLibraries vai para
    # multiPkgs, que o FHS instancia nas duas arquiteturas: o LD_PRELOAD do
    # gamemode é libgamemodeauto.so.0 e precisa casar com o bitness do
    # processo, que muda conforme o runner do jogo.
    (lutris.override {
      extraPkgs = pkgs: [
        pkgs.gamemode
        pkgs.mangohud
      ];
      extraLibraries = pkgs: [ pkgs.gamemode.lib ];
    })
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
