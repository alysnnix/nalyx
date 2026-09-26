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
      # No auto-optimise-store: it hashes and hard-links every path as it is
      # written, adding IO to each build. optimise.automatic below does the
      # same dedup once, on a timer.

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

      # Fazem o daemon coletar lixo DURANTE o build, quando o livre cai abaixo
      # de 10 GiB, liberando até 50 GiB. É o que impede o store de explodir
      # entre dois ticks do timer. mkDefault porque é um piso da frota, e o
      # desktop levanta o dele (SSD sem DRAM sofre mais perto de cheio).
      min-free = lib.mkDefault (10 * 1024 * 1024 * 1024); # 10 GiB
      max-free = lib.mkDefault (50 * 1024 * 1024 * 1024); # 50 GiB
    };
    # O rollback que se usa de verdade é o de ontem, não o de três semanas
    # atrás, e o store cresce muito mais rápido do que o timer semanal
    # coletava: 138 GiB de paths mortos se acumularam entre dois ticks.
    optimise = {
      automatic = true;
      # Nunca diário: varre o store inteiro fazendo hash e hard link, caro
      # demais para pagar todo dia só pela deduplicação.
      dates = [ "weekly" ];
    };
    gc = {
      automatic = true;
      dates = "daily";
      options = "--delete-older-than 3d";
      # `persistent` é true por default, então um host que fica desligado
      # (wsl, vm) dispara a tarefa perdida assim que sobe. Sem o atraso
      # aleatório, todo start frio começaria com um GC pesado competindo com
      # o shell.
      randomizedDelaySec = "45min";
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
        configurationLimit = 3;
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

  environment = {
    systemPackages = with pkgs; [
      vim
      wget
      git
      curl
      sbctl
      sops
      v4l-utils
    ];

    pathsToLink = [
      "/share/zsh"
      "/share/applications"
      "/share/xdg-desktop-portal"
    ];

    # ~/.local/bin is where tools that install per-user binaries land, and this
    # config ships one that does: `uv tool install` symlinks its shims there.
    #
    # home/features/cli/zsh already puts the directory on PATH through
    # `home.sessionPath`, but that only reaches shells via hm-session-vars.sh,
    # which nothing but ~/.zshenv sources here. So without this the directory is
    # on PATH by accident of the login shell being zsh, and anything that does
    # not go through one never sees it, which is what makes a program that
    # registered a binary there report it as missing.
    #
    # This writes /etc/set-environment instead, read by /etc/zshenv for every
    # shell, interactive or not, and by /etc/profile for login shells.
    #
    # The home-manager line stays regardless: this option is NixOS-only, and off
    # NixOS (the wrk profile, wsl-ubuntu) it is the only thing adding the
    # directory, since home-manager owns ~/.profile there and the distro's own
    # entry for it is gone.
    #
    # Stated again in hosts/wsl, which does not import this module: NixOS-WSL
    # brings its own base, so that host declares its own users, packages and
    # stateVersion. Do not delete either copy as a duplicate; setting it here
    # covers desktop, vm and homelab, and nothing else covers WSL.
    localBinInPath = true;
  };

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
