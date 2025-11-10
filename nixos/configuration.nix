{ config, pkgs, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
    ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  
  networking.hostName = "nixos";
  networking.networkmanager.enable = true;
  time.timeZone = "America/Sao_Paulo";
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

  services.xserver.xkb = {
    layout = "br";
    variant = "";
  };

  services.displayManager.sddm.wayland.enable = true;
  services.gnome.gnome-keyring.enable = true;
  security.pam.services = {
    greetd.enableGnomeKeyring = true;
    login.enableGnomeKeyring = true;
  };
  services.dbus.packages = [ pkgs.gnome-keyring pkgs.gcr ];

  # Garbage colector
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };

  # --- Sound settings ---
  hardware.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Configure console keymap
  console.keyMap = "br-abnt2";

  # Define environment variables
  environment.variables={
   NIXOS_OZONE_WL = "1";
   PATH = [
     "\${HOME}/.local/bin"
     "\${HOME}/.config/rofi/scripts"
   ];
   NIXPKGS_ALLOW_UNFREE = "1";
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.szn = {
    isNormalUser = true;
    description = "szn";
    extraGroups = [ "networkmanager" "wheel" "uinput" "docker" ];
    packages = with pkgs; [];
  };

  # Enable automatic login for the user.
  services.getty.autologinUser = "szn";
  services.tailscale.enable = true;

  # Sunshine
  services.udev.extraRules = ''
  	KERNEL=="uinput", MODE="0660", GROUP="uinput"
  '';
  services.sunshine.enable = true;

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;

  #programs.wayland.enable = true;
  programs.hyprland.enable = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    # lang
    go
    bun
    # nvm
    # vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
    # wget
    vim
    kitty
    wofi
    firefox
    deskflow
    parsec-bin
    tailscale
    moonlight-qt
    vscode
    waybar
    font-awesome
    entr
    psmisc
    xdg-desktop-portal-wlr
    xdg-desktop-portal-gtk
    input-leap
    git
    gh
    spotify
    blueberry
  ];

  hardware.graphics.enable = true;
  hardware.graphics.extraPackages = with pkgs; [
    intel-media-driver
  ];

  # --- System --- 
  system.autoUpgrade = {
   enable = true;
   channel = "https://nixos.org/channels/nixos-23.05";
  };
  system.stateVersion = "25.05"; 
}
