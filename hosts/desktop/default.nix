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
    # O daemon do Paseo, com as settings compartilhadas com o wsl, e a
    # publicacao dele na tailnet. Ligados mais abaixo.
    ../../modules/services/paseo.nix
    ../../modules/services/paseo-tailnet.nix
    # Daemon do cooler Corsair (iCUE LINK), consumido pelo gearhub via HTTP.
    ../../modules/services/openlinkhub.nix
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
    # Descoberta e transferência usam a porta 53317 (TCP e UDP); sem
    # openFirewall o app abre mas nenhum peer enxerga esta máquina.
    localsend = {
      enable = true;
      openFirewall = true;
    };
  };

  boot.kernelModules = [ "wireguard" ];
  # Track the newest kernel packaged by this nixpkgs pin.  The NVIDIA driver
  # below follows this same kernel package set, keeping the module ABI aligned.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Quando a GPU trava, o caminho de reset do driver fica preso segurando o
  # lock do RM e tudo que toca a GPU cai em D-state, inclusive o `systemctl
  # reboot`. Só sobra SysRq, e o padrão do NixOS (16) libera apenas o sync,
  # então as outras teclas respondem "operation is disabled" e sobra cortar a
  # energia no botão. Com 1 o REISUB completo funciona: Alt+SysRq+R E I S U B
  # desmonta os filesystems antes de reiniciar, em vez de arriscar o journal.
  boot.kernel.sysctl."kernel.sysrq" = 1;

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
  users.users.${vars.user.name} = {
    openssh.authorizedKeys.keys = [ vars.user.publicKey ];
    # ddcutil fala DDC/CI com os monitores AOC pelos nos /dev/i2c-*; o grupo
    # vem do hardware.i2c.enable mais abaixo.
    #
    # Nada de adbusers: `programs.adb` saiu deste nixpkgs porque o systemd 258
    # ja aplica as regras uaccess do dispositivo Android sozinho, e o binario
    # vem pelo home-manager (home/features/programs/android).
    extraGroups = [ "i2c" ];
  };

  # Paseo roda do lado que tem o codigo, e uma boa parte dos repos mora aqui.
  # O daemon fica no loopback e a publicacao e so na tailnet, com o TLS que o
  # proprio tailscaled emite para o nome MagicDNS deste no: assim o celular e
  # um laptop abrem a UI no navegador, sem porta publicada em nenhuma outra
  # interface e sem dominio a manter (o outro caminho, nginx com ACME, e o que
  # o wsl usa).
  #
  # `paseoTailnet` entra importado e desligado, mesmo padrao do `paseoProxy` no
  # wsl: ligar exige o nome MagicDNS deste no, que nomeia a tailnet e nao pode
  # aparecer aqui, e a assertion do modulo (de proposito, senao a publicacao
  # ficaria muda) derrubaria a avaliacao da CI, que roda sem camada privada.
  # Entao a camada privada e que liga e preenche:
  #   modules.services.paseoTailnet = { enable = true; fqdn = "..."; };
  #
  # Duas coisas alem disso ficam fora deste repo pelo mesmo motivo: a regra de
  # ACL liberando a 443 deste no para quem deve alcancar, que e a unica
  # autenticacao que existe (o daemon nasce sem senha), e a OPENAI_API_KEY num
  # EnvironmentFile, para a voz.
  #
  # O app Electron deste host e cliente deste daemon, nao dono de outro: a
  # activation em home/features/cli/paseo desliga o "Manage built-in daemon"
  # dele, porque dois daemons nao dividem a porta 6767. Depois do primeiro
  # switch o app precisa ser reiniciado uma vez para largar a porta.
  modules.services.paseo.enable = true;

  # Perifericos do gearhub (home/features/programs/gearhub). O daemon do
  # cooler liga aqui; o resto e acesso a hardware que os CLIs precisam.
  modules.services.openlinkhub.enable = true;

  # Acesso i2c para o ddcutil: cria o grupo i2c e a regra de udev dos nos.
  hardware.i2c.enable = true;

  # O teclado Keychron K2 HE e configurado pelo Keychron Launcher (WebHID no
  # navegador), que precisa de acesso ao hidraw do dispositivo sem root.
  services.udev.extraRules = ''
    KERNEL=="hidraw*", ATTRS{idVendor}=="3434", TAG+="uaccess"
  '';

  # O androidenv se recusa a avaliar sem aceitação explícita da licença do SDK
  # (`allowUnfree` sozinho não cobre), e o emulador do PATH vem dele. Fica neste
  # host porque é o único que liga `modules.programs.android`: a avaliação é
  # preguiçosa e nunca acontece nos outros.
  nixpkgs.config.android_sdk.accept_license = true;

  # Android Studio e emulador: este host tem KVM (kvm-intel) e a NVIDIA que o
  # emulador usa para `-gpu host`. O conteúdo do SDK é gerenciado pela IDE, em
  # ~/Android/Sdk; ver home/features/programs/android.
  home-manager.users.${vars.user.name} = {
    imports = [ ../../home ];

    modules.programs.android.enable = true;
  };
  home-manager.backupFileExtension = "backup-rev";
}
