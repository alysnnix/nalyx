{
  pkgs,
  vars,
  lib,
  config,
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

      # llm-agents.nix builds codex, omp and gemini-cli from source and pushes
      # them to its own cache daily. Its flake declares this substituter under
      # `nixConfig`, but a flake's nixConfig only applies while it IS the
      # top-level flake, never when it is consumed as an input, so every host
      # recompiled the codex Rust workspace and omp on each pin bump.
      # Verified: codex and omp resolve on cache.numtide.com and 404 on
      # cache.nixos.org.
      extra-substituters = [ "https://cache.numtide.com" ];
      extra-trusted-public-keys = [
        "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      ];
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
        configurationLimit = 5;
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

  users.users.${vars.user.name} = {
    isNormalUser = true;
    description = "Alysson";
    initialPassword = lib.mkDefault "changeme";
    extraGroups = [
      "networkmanager"
      "wheel"
      "video"
      "audio"
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

  # NixOS ships a 1024 soft nofile limit (systemd DefaultLimitNOFILE=1024:524288).
  # `switch` runs `sudo nixos-rebuild`, which inherits that soft limit and spawns
  # `nix build`; on a closure this size the client exhausts its descriptors and
  # dies with `error: opening directory "/nix/store": Too many open files`.
  # Raise the soft limit and leave the hard limit at the systemd default.
  security.pam.loginLimits = [
    {
      domain = "*";
      item = "nofile";
      type = "soft";
      value = "65536";
    }
    {
      domain = "*";
      item = "nofile";
      type = "hard";
      value = "524288";
    }
  ];

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
