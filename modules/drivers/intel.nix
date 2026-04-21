{ pkgs, ... }:
{
  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver
      intel-vaapi-driver
      libva-vdpau-driver
      libvdpau-va-gl
    ];
  };

  environment.sessionVariables = {
    # Force Intel Iris Xe to use the correct Mesa driver
    MESA_LOADER_DRIVER_OVERRIDE = "iris";
    # Persistent shader cache for Mesa and Qt (reduces first-render stutter)
    MESA_SHADER_CACHE_DIR = "$HOME/.cache/mesa_shader_cache";
    MESA_SHADER_CACHE_MAX_SIZE = "1G";
    QSG_SHADER_CACHE_DIR = "$HOME/.cache/qt_shader_cache";
  };

  services.thermald.enable = true;
}
