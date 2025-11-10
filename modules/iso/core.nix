{
  pkgs,
  lib,
  modulesPath,
  ...
}: {
  system.stateVersion = "21.11";

  nix = {
    extraOptions = "experimental-features = nix-command flakes";
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };
    package = pkgs.nixFlakes;
  };

  imports = ["${modulesPath}/installer/cd-dvd/iso-image.nix"];

  networking.hostName = "nixos";
  networking.networkmanager.enable = true;

  services.displayManager.sddm.wayland.enable = true;
  services.gnome.gnome-keyring.enable = true;
  services.dbus.packages = [ pkgs.gnome-keyring pkgs.gcr ];
  services.xserver.xkb = {
    layout = "br";
    variant = "";
  };

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  powerManagement.cpuFreqGovernor = lib.mkDefault "performance";
  hardware.enableRedistributableFirmware = true;

  time.timeZone = "America/Sao_Paulo";
  console.keyMap = "br-abnt2";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "pt_BR.UTF-8";
    LC_IDENTIFICATION = "pt_BR.UTF-8";
    LC_MEASUREMENT = "pt_BR.UTF-8";
    LC_MONETARY = "pt_BR.UTF-8";
    LC_NAME = "pt_BR.UTF-8";
    LC_NUMERIC = "pt_BR.UTF-8";
    LC_PAPER = "pt_BR.UTF-8";
    LC_TELEPHONE = "pt_BR.UTF-8";
    LC_TIME = "pt_BR.UTF-8";
  };

  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    wget
    bat
    zip
    git
    unzip
    killall
    nix-index
  ];
}