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
    # Trava o áudio Bluetooth em A2DP: sem isto o fone cai para HSP/HFP e o som
    # fica mono em 8-16 kHz, com o nó de saída morrendo e renascendo em loop.
    ../../modules/services/bluetooth-audio.nix
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

  # Host de streaming para o Moonlight. No GNOME Wayland a captura sai pelo KMS
  # grab, que exige CAP_SYS_ADMIN: sem capSysAdmin o serviço sobe e o cliente
  # conecta, mas a tela chega preta. openFirewall abre a faixa derivada da porta
  # base 47989 (47984, 47989, 47990 e 48010 em TCP; 47998-48000, 48002 e 48010
  # em UDP).
  #
  # Sem `settings` nem `applications` de propósito: qualquer um dos dois gera um
  # arquivo de config no store e tranca a web UI (https://localhost:47990), que
  # é por onde o pareamento e os apps são configurados.
  services.sunshine = {
    enable = true;
    openFirewall = true;
    capSysAdmin = true;
  };

  boot.kernelModules = [ "wireguard" ];
  # Track the newest kernel packaged by this nixpkgs pin.  The NVIDIA driver
  # below follows this same kernel package set, keeping the module ABI aligned.
  boot.kernelPackages = pkgs.linuxPackages_latest;

  # Esta máquina tem 62 GiB de RAM e nenhuma swap, e a raiz mora num Kingston
  # A400, um SSD SATA sem cache DRAM. A combinação trava o desktop inteiro por
  # dois caminhos distintos, e os dois são de kernel, não de aplicação.
  #
  # 1. Sem swap, o reclaim não tem para onde despejar página anônima. Quando o
  #    cache cresce (medido: 51 GiB de page cache contra 1,3 GiB livres), o
  #    kworker de mm_percpu_wq passa a girar em reclaim síncrono. Medido preso
  #    em ~60% de um core de forma contínua, não em pico.
  #
  #    zram em vez de swap em disco: comprime na RAM e não joga escrita extra
  #    justamente no disco que já é o gargalo. page-cluster=0 porque readahead
  #    de swap não faz sentido quando o "disco" é memória, e swappiness alto é
  #    o certo aqui pelo mesmo motivo: trocar por zram custa menos que descartar
  #    page cache e reler do A400.
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 25;
  };

  boot.kernel.sysctl = {
    # Quando a GPU trava, o caminho de reset do driver fica preso segurando o
    # lock do RM e tudo que toca a GPU cai em D-state, inclusive o `systemctl
    # reboot`. Só sobra SysRq, e o padrão do NixOS (16) libera apenas o sync,
    # então as outras teclas respondem "operation is disabled" e sobra cortar a
    # energia no botão. Com 1 o REISUB completo funciona: Alt+SysRq+R E I S U B
    # desmonta os filesystems antes de reiniciar, em vez de arriscar o journal.
    "kernel.sysrq" = 1;

    "vm.swappiness" = 180;
    "vm.page-cluster" = 0;

    # 2. O outro caminho é o writeback. Os defaults são percentuais da RAM, e
    #    num host de 62 GiB isso vira um teto absurdo: dirty_background_ratio=10
    #    deixa 6,3 GiB sujarem antes do flusher sequer acordar, e dirty_ratio=20
    #    deixa 12,5 GiB antes de bloquear quem escreve. Escoar vários GiB de
    #    escrita pequena e aleatória num A400 é justamente o pior caso dele, e o
    #    resultado medido foi kworker/u81-flush-8:32 preso em ~43% de um core
    #    sustentado para drenar só 1,1 MB/s.
    #
    #    dirty_bytes e dirty_background_bytes sobrescrevem os percentuais e
    #    fixam o teto em valor absoluto, então o lote volta a caber no disco e o
    #    flusher termina em vez de acumular. Áudio é o primeiro a quebrar quando
    #    um core some assim, porque tem prazo em milissegundos, e o vídeo engasga
    #    junto por sincronizar no relógio do áudio.
    "vm.dirty_background_bytes" = 256 * 1024 * 1024;
    "vm.dirty_bytes" = 1024 * 1024 * 1024;
  };

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

  # Teto de memoria do daemon, e nao do sistema: cada agente sobe a sua propria
  # copia inteira dos MCP servers (firebase, sapron, posthog, nekt, growthbook,
  # grafana, composio), sem nada compartilhado entre eles. Medido nesta maquina:
  # 12 a 16 processos e 1,4 a 2,5 GiB por agente, e o cgroup do `paseo.service`
  # em 16,4 GiB com uma duzia de agentes vivos depois de 35 minutos de uptime.
  #
  # Sem teto isso enche a RAM, e nada corta. `oomctl` lista zero cgroups
  # monitorados, porque o systemd-oomd do NixOS so cobre as user slices e o
  # daemon e servico de sistema. O OOM killer do kernel tambem nao entra: o zram
  # absorve a pressao dentro da propria RAM, entao a alocacao nunca chega a
  # falhar, o reclaim gira, e a maquina trava viva em vez de perder um processo.
  #
  # MemoryHigh e o freio: o reclaim fica agressivo dentro do cgroup do Paseo e
  # quem estala e ele, nao o desktop. MemoryMax e o fusivel: estourou, o kernel
  # mata um agente ali dentro.
  #
  # Os valores saem da reserva, nao do teto: medido em uso normal, tudo que nao
  # e Paseo (Chrome, traycer, a stack de containers, o GNOME) ocupa 18,6 GiB.
  # Reservar 22 GiB cobre isso com folga para pico e page cache, e o que sobra
  # dos 62,6 GiB e o que o daemon pode tomar: 40 GiB, uns vinte e quatro agentes
  # no custo medido de 1,7 GiB cada. O freio entra 6 GiB antes do fusivel, que e
  # espaco de sobra para o reclaim trabalhar sem nunca chegar a matar ninguem.
  systemd.services.paseo.serviceConfig = {
    MemoryHigh = "34G";
    MemoryMax = "40G";
  };

  # Perifericos do gearhub (home/features/programs/gearhub). O daemon do
  # cooler liga aqui; o resto e acesso a hardware que os CLIs precisam.
  modules.services.openlinkhub.enable = true;

  modules.services.bluetoothAudio.enable = true;

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
