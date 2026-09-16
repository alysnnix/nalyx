# Android Studio com o SDK gravável em ~/Android/Sdk, gerenciado pela própria
# IDE. O caminho declarativo (SDK composto pelo androidenv, no store) não
# sobrevive ao assistente do Studio: ele exige instalar a system image que vem
# fixada na release, e a 2026.1.4 pede `system-images;android-37.2`, que nem
# existe neste pin do nixpkgs (o repo.json para em 37.1). Sem poder escrever, o
# Studio declara o SDK "missing, out of date or corrupted" e o SDK Manager não
# tem saída. Então o nix entrega os binários e o Studio entrega o conteúdo.
#
# A GPU continua coberta: o `buildFHSEnv` do android-studio exporta
# `XDG_DATA_DIRS` com /run/opengl-driver/share, onde estão o `nvidia_icd.json`
# e o `10_nvidia.json` do glvnd, então o emulador baixado pela IDE acha o driver
# NVIDIA pelos mesmos caminhos que o pacote do nixpkgs usa.
#
# Opt-in, e hosts/desktop é quem liga: é a máquina com KVM e GPU.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.modules.programs.android;

  # Emulador do nixpkgs, fora do SDK e direto no PATH. O que o Studio baixa é um
  # prebuilt FHS: roda dentro do wrapper da IDE e em mais lugar nenhum. Este
  # passa por autoPatchelf e sai apontando para o libglvnd e para o ICD Vulkan
  # da NVIDIA, então também serve para subir um AVD de um terminal comum. As
  # listas vazias são o que evita arrastar plataforma e system image junto: o
  # conteúdo do SDK é do Studio agora.
  emulator =
    (pkgs.androidenv.composeAndroidPackages {
      includeEmulator = true;
      platformVersions = [ ];
      abiVersions = [ ];
      systemImageTypes = [ ];
    }).emulator;

  # Mesmo caminho que o Studio usa por padrão, de propósito: assim a IDE e o
  # tooling de linha de comando nunca discordam de onde o SDK está.
  sdkHome = "${config.home.homeDirectory}/Android/Sdk";
in
{
  options.modules.programs.android.enable =
    lib.mkEnableOption "Android Studio, emulador e ferramentas de linha de comando";

  config = lib.mkIf cfg.enable {
    home.packages = [
      pkgs.android-studio
      # adb e fastboot patchados, para não depender de um shell aberto pela IDE
      # nem do que o SDK Manager baixar.
      pkgs.android-tools
      emulator
    ];

    home.sessionVariables = {
      ANDROID_HOME = sdkHome;
      # Nome antigo, ainda lido pelo Gradle e por parte do tooling Flutter/RN.
      ANDROID_SDK_ROOT = sdkHome;
    };

    # O diretório existe antes do primeiro Studio para que `ANDROID_HOME` nunca
    # aponte para o vazio num shell; o conteúdo quem instala é a IDE.
    home.activation.androidSdkHome = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      $DRY_RUN_CMD mkdir -p ${lib.escapeShellArg sdkHome}
    '';
  };
}
