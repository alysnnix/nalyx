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

  networking.hostName = "desktop";

  # SSH só acessível via Tailscale: porta 22 fechada nas demais interfaces,
  # mesmo padrão do wsl.
  networking.firewall.trustedInterfaces = [ "tailscale0" ];
  # `tailscale serve` e operacao de controle: tailscaled so a aceita de root ou
  # do operador. Declarado aqui em vez de rodado a mao
  # (`paseo-tailnet-operator-setup`) porque este host tem camada NixOS, e sem
  # isso o servico que publica o Paseo na tailnet falha no boot.
  services.tailscale.extraSetFlags = [ "--operator=${vars.user.name}" ];
  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };
  users.users.${vars.user.name}.openssh.authorizedKeys.keys = [ vars.user.publicKey ];

  home-manager.users.${vars.user.name} = {
    imports = [ ../../home ];

    # O app desktop sobe um daemon proprio junto com a janela, sem web UI
    # (`--no-web-ui`) e morto quando a janela fecha: serve para o app e para
    # nada mais. Um celular na tailnet precisa do contrario, um daemon que
    # existe sem janela e que serve a UI na mesma origem da API, entao aqui o
    # daemon vira servico de usuario e o app e apontado para ele (a activation
    # do modulo desliga `manageBuiltInDaemon`, porque duas instancias nao
    # dividem a 6767).
    #
    # `tailnetServe` publica esse loopback em https://<no>.<tailnet>.ts.net com
    # o certificado do proprio tailscaled, e injeta o nome do no em
    # `daemon.hostnames` e `cors.allowedOrigins` em runtime: sem isso o daemon
    # responde `403 Invalid Host header` a qualquer nome que nao seja localhost.
    # Quem alcanca a 443 deste no e decisao da ACL da tailnet, que e a
    # autenticacao aqui, porque o daemon nao tem senha.
    #
    # Um passo manual, uma vez: `paseo-tailnet-operator-setup`.
    modules.cli.paseo = {
      daemon = {
        enable = true;
        settings = {
          # Nasce desligada. Ligada, a UI e servida na mesma origem da API, o
          # que e exatamente o que faz o celular abrir a URL e conectar sem
          # passar pela tela de "Add Host".
          features.webUi.enabled = true;

          daemon = {
            mcp = {
              enabled = true;
              injectIntoAgents = true;
            };
            browserTools.enabled = true;
            autoArchiveAfterMerge = true;
          };
        };
      };
      tailnetServe.enable = true;
    };
  };
  home-manager.backupFileExtension = "backup-rev";
}
