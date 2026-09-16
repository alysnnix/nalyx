{
  vars,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ../../modules/secureboot
    ./hardware-configuration.nix
    ../../modules/core/default.nix
    ../../modules/drivers/nvidia.nix
    ../../modules/services/nordvpn.nix
    ../../modules/services/syncthing.nix
  ]
  ++ (lib.optional (vars.desktop == "gnome") ../../modules/desktop/gnome.nix)
  ++ (lib.optional (vars.desktop == "hyprland") ../../modules/desktop/hyprland.nix);

  # Lanzaboote owns the signed systemd-boot and NixOS UKIs. rEFInd is only an
  # outer selector, explicitly signed with the same db key and installed under
  # its own path so it cannot replace Lanzaboote's managed EFI files.
  boot.loader.timeout = lib.mkForce 30;

  systemd.services.refind-install = {
    description = "Install signed rEFInd boot selector";
    wantedBy = [ "multi-user.target" ];
    after = [
      "local-fs.target"
      "prepare-sb-auto-enroll.service"
    ];
    path = [
      pkgs.coreutils
      pkgs.efibootmgr
      pkgs.sbctl
      pkgs.util-linux
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      esp_device="$(findmnt -no SOURCE /boot)"
      esp_disk="/dev/$(lsblk -no PKNAME "$esp_device")"
      esp_partition="$(lsblk -no PARTN "$esp_device")"

      install -Dm755 ${pkgs.refind}/share/refind/refind_x64.efi /boot/EFI/refind/refind_x64.efi
      install -d /boot/EFI/refind/icons
      cp -fR ${pkgs.refind}/share/refind/icons/. /boot/EFI/refind/icons/

      cat > /boot/EFI/refind/refind.conf <<'EOF'
      timeout 10
      use_nvram false
      scanfor manual

      menuentry "NixOS" {
        loader \EFI\systemd\systemd-bootx64.efi
      }

      menuentry "Windows Boot Manager" {
        volume 13e610e9-f1ec-4e91-91e9-10f355d0b371
        loader \EFI\Microsoft\Boot\bootmgfw.efi
      }
      EOF

      sbctl sign -s /boot/EFI/refind/refind_x64.efi
      sbctl verify

      case "$(efibootmgr)" in
        *"rEFInd"*) ;;
        *) efibootmgr --create --disk "$esp_disk" --part "$esp_partition" --label rEFInd --loader '\EFI\refind\refind_x64.efi' ;;
      esac
    '';
  };

  programs = {
    steam = {
      enable = true;
      remotePlay.openFirewall = true;
      gamescopeSession.enable = true;
    };
    gamemode.enable = true;
    gamescope.enable = true;
  };

  boot.kernelModules = [ "wireguard" ];
  # Track the newest kernel packaged by this nixpkgs pin.  The NVIDIA driver
  # below follows this same kernel package set, keeping the module ABI aligned.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = "desktop";

  # SSH só acessível via Tailscale: porta 22 fechada nas demais interfaces,
  # mesmo padrão do wsl.
  networking.firewall.trustedInterfaces = [ "tailscale0" ];
  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };
  users.users.${vars.user.name}.openssh.authorizedKeys.keys = [ vars.user.publicKey ];

  home-manager.users.${vars.user.name} = import ../../home;
  home-manager.backupFileExtension = "backup-rev";
}
