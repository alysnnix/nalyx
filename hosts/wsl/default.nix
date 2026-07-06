{
  vars,
  pkgs,
  lib,
  ...
}:

{
  imports = [
    ../../modules/services/syncthing.nix
  ];

  wsl = {
    enable = true;
    defaultUser = vars.user.name;
    startMenuLaunchers = true;
    docker-desktop.enable = true;
    # O Docker Desktop roda seu script de integração como root dentro da distro
    # (wsl -u root -e install ...). O módulo docker-desktop do NixOS-WSL só expõe
    # cat/whoami/groupadd/usermod em /usr/bin; versões novas também chamam
    # `install`, que faltava -> "execvpe(install) failed". Expomos ele aqui.
    extraBin = [
      { src = "${pkgs.coreutils}/bin/install"; }
    ];
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nixpkgs.config.allowUnfree = true;

  networking.hostName = "nixos-wsl";
  system.stateVersion = "24.05";

  environment.systemPackages = with pkgs; [
    git
    vim
    wget
    curl
    sops
    gnome-calculator
    pritunl-client
    (google-chrome.override {
      commandLineArgs = [
        "--profile-directory=Default"
        "--user-data-dir=/home/${vars.user.name}/.chrome-profile"
      ];
    })
    playwright
    wslu
  ];

  systemd.services.pritunl-client = {
    description = "Pritunl Client Daemon";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.pritunl-client}/bin/pritunl-client-service";
      Restart = "always";
    };
  };

  # Create Playwright's expected Chrome path structure
  # Playwright expects /opt/google/chrome/chrome (directory with chrome symlink inside)
  systemd.tmpfiles.rules = [
    "d /opt/google/chrome 0755 root root -"
    "L+ /opt/google/chrome/chrome - - - - ${pkgs.google-chrome}/bin/google-chrome"
  ];

  users.users.${vars.user.name} = {
    isNormalUser = true;
    # The private module (nalyx-private) forces the login password to come from a
    # SOPS secret (hashedPasswordFile) on every host. On a fresh WSL install the
    # SOPS SSH key (~/.ssh/id_ed25519) isn't in place at first activation, so
    # decryption fails and the account is created locked, recoverable only via
    # `wsl -u root`. WSL doesn't need the SOPS-managed password: fall back to a
    # bootstrap password and change it afterwards with `passwd` (mutableUsers is
    # true, so the change persists). mkOverride 49 wins over the private module's
    # mkForce (priority 50).
    hashedPasswordFile = lib.mkOverride 49 null;
    initialPassword = lib.mkOverride 49 "changeme";
    extraGroups = [
      "wheel"
      "networkmanager"
      "docker"
    ];
    shell = pkgs.zsh;
  };

  security.sudo = {
    enable = true;
    wheelNeedsPassword = true;
    extraConfig = ''
      Defaults timestamp_timeout=0
    '';
  };

  # Playwright browser dependencies (X11/GUI libs for WSLg)
  hardware.graphics.enable = true;

  environment.sessionVariables = {
    DISPLAY = ":0";
  };

  programs = {
    zsh.enable = true;
    dconf.enable = true;
    nix-ld.enable = true;
    nix-ld.libraries = with pkgs; [
      # Playwright/Chromium dependencies
      libx11
      libxcomposite
      libxdamage
      libxext
      libxfixes
      libxrandr
      libxcb
      mesa
      libdrm
      libxkbcommon
      libxshmfence
      alsa-lib
      at-spi2-atk
      at-spi2-core
      cairo
      cups
      dbus
      expat
      glib
      gtk3
      nspr
      nss
      pango
      wayland
    ];
  };

  home-manager.users.${vars.user.name} = import ../../home;
  home-manager.backupFileExtension = "backup-wsl";
}
