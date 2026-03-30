{
  vars,
  pkgs,
  config,
  lib,
  hasPrivate ? false,
  private ? null,
  ...
}:

{
  imports = [
    # Import home-manager configuration to keep dotfiles synced
    # Note: Assuming 'nixos-wsl' module is injected via flake.nix
  ];

  wsl = {
    enable = true;
    defaultUser = vars.user.name;
    startMenuLaunchers = true;
    docker-desktop.enable = true;
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
    gnome-calculator
    pritunl-client
    firefox
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

  sops = lib.mkIf hasPrivate {
    defaultSopsFile = "${private}/secrets/secrets.yaml";
    defaultSopsFormat = "yaml";
    age.sshKeyPaths = [ "/home/${vars.user.name}/.ssh/id_ed25519" ];
    secrets = {
      password.neededForUsers = true;
      anytype_api_token.owner = vars.user.name;
      slack_bot_token.owner = vars.user.name;
    };
  };

  users.users.${vars.user.name} = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
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
    dconf.enable = true;
    nix-ld.enable = true;
  };

  home-manager.users.${vars.user.name} = import ../../home;
  home-manager.backupFileExtension = "backup-wsl";
}
