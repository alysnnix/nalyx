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
    ../../modules/services/syncthing.nix
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
      sapron_cf_client_id.owner = vars.user.name;
      sapron_cf_client_secret.owner = vars.user.name;
      seazone_mcp_api_key.owner = vars.user.name;
      minimax_api_key.owner = vars.user.name;
      openrouter_api_key.owner = vars.user.name;
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

  security.sudo = {
    enable = true;
    wheelNeedsPassword = true;
    extraConfig = ''
      Defaults timestamp_timeout=0
    '';
  };

  programs = {
    zsh.enable = true;
    dconf.enable = true;
    nix-ld.enable = true;
  };

  home-manager.users.${vars.user.name} = import ../../home;
  home-manager.backupFileExtension = "backup-wsl";
}
