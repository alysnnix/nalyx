# Android Studio com o SDK composto pelo androidenv, em vez do SDK Manager da
# própria IDE. Os pacotes do Google são prebuilts FHS: o `emulator` do nixpkgs
# passa por autoPatchelf e sai com `LD_LIBRARY_PATH` apontando para o libglvnd
# e `VK_ADD_DRIVER_FILES=/run/opengl-driver/share/vulkan/icd.d`, que é onde o
# driver NVIDIA instala o ICD. É isso que faz `-gpu host` e o caminho Vulkan
# enxergarem a GPU; um emulador baixado pela IDE não tem nenhum dos dois.
#
# O que dita a velocidade é o KVM, não a GPU: /dev/kvm já nasce 0666 pela regra
# do systemd, então nada de grupo extra. A GPU só desenha a janela, e sob GNOME
# Wayland ela desenha via XWayland, porque o emulador é Qt/X11.
#
# Opt-in: o fecho passa de alguns GB (emulador mais system image), e só compensa
# num host com KVM e GPU. hosts/desktop liga, e é lá também que mora o
# `nixpkgs.config.android_sdk.accept_license`, sem o qual o androidenv se recusa
# a avaliar.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.modules.programs.android;

  sdk =
    (pkgs.androidenv.composeAndroidPackages {
      platformVersions = [ cfg.platformVersion ];
      abiVersions = [ "x86_64" ];
      systemImageTypes = [ cfg.systemImageType ];
      includeEmulator = true;
      includeSystemImages = true;
      # O `android-studio-full` do nixpkgs traz NDK e as cinco últimas
      # plataformas com as imagens de cada uma, dezenas de GB para usar uma.
      # Aqui é uma plataforma só, e o NDK entra quando existir um projeto nativo
      # que o peça.
      includeNDK = false;
    }).androidsdk;

  androidHome = "${sdk}/libexec/android-sdk";
in
{
  options.modules.programs.android = {
    enable = lib.mkEnableOption "Android Studio com SDK e emulador do androidenv";

    platformVersion = lib.mkOption {
      type = lib.types.str;
      default = "36";
      description = ''
        Nível de API da plataforma e da system image. O SDK vive no store, então
        a IDE não consegue instalar outro por cima: para mudar de API, muda aqui
        e roda o switch.
      '';
    };

    systemImageType = lib.mkOption {
      type = lib.types.str;
      default = "google_apis_playstore";
      description = ''
        Tipo da system image do AVD. `google_apis_playstore` tem a Play Store
        mas não permite `adb root`; `google_apis` troca uma coisa pela outra.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      (pkgs.android-studio.withSdk sdk)
      # adb, fastboot e o resto do platform-tools soltos no PATH, para não
      # depender de um shell aberto pela IDE.
      pkgs.android-tools
    ];

    home.sessionVariables = {
      ANDROID_HOME = androidHome;
      # Nome antigo, ainda lido pelo Gradle e por parte do tooling Flutter/RN.
      ANDROID_SDK_ROOT = androidHome;
    };
  };
}
