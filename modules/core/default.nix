{
  pkgs,
  vars,
  lib,
  config,
  hasPrivate ? false,
  private ? null,
  ...
}:

{
  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
    };
    optimise.automatic = true;
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  nixpkgs.config.allowUnfree = true;
  time.timeZone = "America/Sao_Paulo";
  time.hardwareClockInLocalTime = true;
  system.stateVersion = "24.05";

  boot = {
    loader = {
      systemd-boot = {
        enable = lib.mkDefault true;
        editor = false;
      };
      efi.canTouchEfiVariables = true;
      timeout = 10;
    };
    extraModulePackages = with config.boot.kernelPackages; [ v4l2loopback ];
    kernelModules = [
      "v4l2loopback"
      "it87"
      "coretemp"
    ];
    extraModprobeConfig = ''
      # OBS Virtual Camera settings
      options v4l2loopback devices=1 video_nr=10 card_label="OBS Virtual Camera" exclusive_caps=1

      # Gigabyte sensor settings to avoid resource conflicts
      options it87 ignore_resource_conflict=1
    '';
  };

  networking.networkmanager = {
    enable = true;
    plugins = with pkgs; [ networkmanager-openvpn ];
  };
  services = {
    xserver.xkb = {
      layout = "us,br";
      variant = ",abnt2";
    };

    tailscale = {
      enable = true;
      authKeyFile = if hasPrivate then config.sops.secrets.tailscale_auth_key.path else null;
    };

    envfs = {
      enable = true;
    };
  };

  environment.systemPackages = with pkgs; [
    vim
    wget
    git
    curl
    sbctl
    sops
    v4l-utils
  ];

  environment.pathsToLink = [
    "/share/zsh"
    "/share/applications"
    "/share/xdg-desktop-portal"
  ];

  virtualisation.docker.enable = true;

  sops = lib.mkIf hasPrivate {
    defaultSopsFile = "${private}/secrets/secrets.yaml";
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/home/${vars.user.name}/.ssh/id_ed25519" ];
    secrets = {
      password.neededForUsers = true;
      anytype_api_token.owner = vars.user.name;
      slack_bot_token.owner = vars.user.name;
      tailscale_auth_key = { };
    };
  };

  users.users.${vars.user.name} = {
    isNormalUser = true;
    description = "Alysson";
    extraGroups = [
      "networkmanager"
      "wheel"
      "video"
      "audio"
      "docker"
    ];
    shell = pkgs.zsh;
  }
  // (
    if hasPrivate then
      {
        hashedPasswordFile = config.sops.secrets.password.path;
      }
    else
      {
        initialPassword = "changeme";
      }
  );

  programs = {
    zsh.enable = true;

    gnupg = {
      agent = {
        enable = true;
        pinentryPackage = pkgs.pinentry-curses;
      };
    };

    nix-ld = {
      enable = true;
      libraries = with pkgs; [
        stdenv.cc.cc.lib
        zlib
        openssl
      ];
    };

    appimage = {
      enable = true;
      binfmt = true;
    };
  };

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    nerd-fonts.fira-code
    departure-mono
  ];
}
