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
  };

  services.thermald.enable = true;
}
