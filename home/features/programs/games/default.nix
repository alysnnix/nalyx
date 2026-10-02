{
  pkgs,
  ...
}:
let
  # Battle.net treats a game whose folder is missing as uninstalled and drops
  # it from its database; "Locate game" then fails with BLZBNTAGT00000AF0 even
  # once the folder is back. Set as the Lutris "Command prefix" of a game
  # ("require-mount /path/to/disk"), it refuses to start the game while that
  # disk is not mounted.
  requireMount = pkgs.writeShellApplication {
    name = "require-mount";
    runtimeInputs = [
      pkgs.util-linux
      pkgs.libnotify
    ];
    text = ''
      if [ "$#" -lt 2 ]; then
        echo "usage: require-mount <mountpoint> <command> [args...]" >&2
        exit 2
      fi
      target=$1
      shift
      if ! mountpoint -q -- "$target"; then
        msg="$target is not mounted, so the game was not started."
        echo "require-mount: $msg" >&2
        notify-send --app-name=Lutris --urgency=critical "Disk not mounted" "$msg" || true
        exit 1
      fi
      exec "$@"
    '';
  };
in
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
    #
    # vulkan-tools entra pelo mesmo motivo, com uma consequência pior: o lutris
    # chama o caminho absoluto /usr/bin/vulkaninfo (gpu.py:125), e sem ele nunca
    # preenche gpu.device_uuid, que é a única coisa que faz runner.py:276
    # exportar DXVK_FILTER_DEVICE_UUID. Nesta máquina, com a UHD 770 do i5 ao
    # lado da 3060 Ti, é esse env var que prende o DXVK na NVIDIA.
    (lutris.override {
      extraPkgs = pkgs: [
        pkgs.gamemode
        pkgs.mangohud
        pkgs.vulkan-tools
        # Inside the FHS env, so the Lutris "Command prefix" can find it.
        requireMount
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
