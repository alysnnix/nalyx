{
  config,
  ...
}:
{
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  services.xserver.videoDrivers = [ "nvidia" ];

  boot.kernelParams = [
    # Improves power management communication
    "nvidia.NVreg_RegistryDwords=RMConnectToPlatformDatapath=1"
    # Enables better sleep/idle states for Ampere cards like your 3060 Ti
    "nvidia.NVreg_EnableS0ixPowerManagement=1"
  ];

  hardware.nvidia = {
    modesetting.enable = true;
    open = false;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    # Required for the GPU to downclock to P8/P12 state in idle
    powerManagement.enable = true;
    # Should be false for desktop builds to avoid instability
    powerManagement.finegrained = false;
  };
}
