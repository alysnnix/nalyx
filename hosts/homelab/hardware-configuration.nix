# PLACEHOLDER - Replace with actual hardware configuration
# Generate on the homelab laptop:
#   sudo nixos-generate-config --show-hardware-config > hosts/homelab/hardware-configuration.nix
{
  lib,
  ...
}:
{
  boot.initrd.availableKernelModules = [ ];
  boot.kernelModules = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };

  swapDevices = [ ];
  networking.useDHCP = lib.mkDefault true;
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
