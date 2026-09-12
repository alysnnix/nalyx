{
  inputs,
  vars,
  pkgs,
  lib,
  ...
}:

{
  imports = [
    inputs.paseo.nixosModules.paseo
    ../../modules/services/syncthing.nix
    ../../modules/services/omp-collab.nix
    ../../modules/services/ollama.nix
    # So opcoes, desligado: o vhost TLS na frente do daemon Paseo precisa de um
    # FQDN, do IP da tailnet deste no e de credenciais de DNS, e nenhum dos tres
    # pode morar num repo publico sem dizer de quem e a infraestrutura. A camada
    # privada e que preenche os valores e liga
    # `modules.services.paseoProxy.enable`. Enquanto isso este host segue
    # exatamente como antes, com o Paseo so no loopback.
    ../../modules/services/paseo-proxy.nix
    # Options only: the private layer owns the repository password, so it is
    # also what sets `enable`. This host is the fleet's single backup source,
    # since Syncthing converges the other peers anyway.
    ../../modules/services/restic.nix
  ];

  wsl = {
    enable = true;
    defaultUser = vars.user.name;
    startMenuLaunchers = true;
    docker-desktop.enable = true;
    # O Docker Desktop roda seu script de integração como root dentro da distro
    # (wsl -u root -e <cmd> ...). O módulo docker-desktop do NixOS-WSL só expõe
    # cat/whoami/groupadd/usermod em /usr/bin; versões novas também chamam
    # coreutils extras p/ instalar o proxy binary (install/mv/... ->
    # "execvpe(<cmd>) failed"). Expomos o conjunto necessário aqui.
    extraBin = map (name: { src = "${pkgs.coreutils}/bin/${name}"; }) [
      "install"
      "mv"
      "cp"
      "rm"
      "mkdir"
      "chmod"
      "chown"
      "ln"
    ];
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  nixpkgs.config.allowUnfree = true;

  # O hostname do SO NAO pode mudar: modules/services/syncthing.nix usa
  # `config.networking.hostName == "nixos-wsl"` para decidir o tipo de cada
  # pasta. Renomear aqui faria a pasta wrk virar sendreceive e anunciar o
  # ~/wrk local (possivelmente incompleto) como deleção para os peers.
  networking.hostName = "nixos-wsl";
  system.stateVersion = "24.05";

  # O WSL herda o MTU do host Windows e sobe o eth0 com 1280, o mesmo valor que
  # o Tailscale usa no tailscale0. Sem folga para o overhead do WireGuard (~60
  # bytes), todo pacote grande morre em silêncio: o handshake SSH trava exato em
  # `expecting SSH2_MSG_KEX_ECDH_REPLY`, que é o primeiro pacote grande, e o
  # Syncthing fica reconectando sem nunca transferir. Buraco negro de MTU
  # clássico, sem ICMP de volta.
  #
  # Medido no caminho para o laptop, com as duas interfaces em 1280:
  # passa até 1208 bytes, bloqueia a partir de 1228.
  #
  # 1420 em vez de 1500 de propósito. Os adaptadores do host são:
  #   vEthernet (WSL) 1500 | Ethernet 1500 | NordLynx 1420 | Tailscale 1280
  # Parte do tráfego sai pelo NordLynx quando a VPN do Windows está conectada,
  # então 1420 é o menor MTU real de saída e não depende de PMTU discovery.
  # Ainda sobra folga: 1280 do tailscale0 + 60 de overhead = 1340 < 1420.
  #
  # Feito em unidade explícita, e não com `networking.interfaces.eth0.mtu`:
  # nesse host essa opção é no-op. Em modo scripted ela vira um `.link` de udev
  # (`systemd.network.links."40-eth0"`), mas os `.link` só são escritos em
  # /etc/systemd/network quando networkd está ligado, e aqui
  # `networking.useNetworkd = false` e o diretório nem existe. Além disso o WSL
  # cria o eth0 fora do udev, então um `.link` não seria aplicado de qualquer
  # forma. `ip link set` é determinístico e independe de qual stack de rede está
  # ativo.
  systemd.services.wsl-eth0-mtu = {
    description = "Set eth0 MTU to leave room for WireGuard encapsulation";
    wantedBy = [ "multi-user.target" ];
    before = [ "tailscaled.service" ];
    after = [ "network.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      # O WSL configura o eth0 por conta própria e o timing não é garantido.
      for _ in $(seq 1 30); do
        [ -e /sys/class/net/eth0 ] && break
        sleep 1
      done
      if [ ! -e /sys/class/net/eth0 ]; then
        echo "eth0 never appeared, nothing to do"
        exit 0
      fi
      current="$(cat /sys/class/net/eth0/mtu)"
      if [ "$current" = "1420" ]; then
        echo "eth0 already at MTU 1420"
        exit 0
      fi
      ${pkgs.iproute2}/bin/ip link set dev eth0 mtu 1420
      echo "eth0 MTU $current -> $(cat /sys/class/net/eth0/mtu)"
    '';
  };

  # Tailscale roda dentro do WSL como nó próprio na tailnet (independente do
  # daemon do Windows). Assim dá pra dar SSH direto no WSL sem passar pelo host
  # Windows. O WSL só fica online enquanto a distro estiver rodando.
  #
  # O nome do nó é fixado em `wsl-nix` (desacoplado do hostname do SO acima),
  # porque o FQDN resultante `wsl-nix.<tailnet>.ts.net` é o endereço que o
  # Syncthing dos peers disca. Nome derivado do hostname sobrevive a reinstall,
  # mas só se o registro antigo não estiver segurando o nome; a identidade do
  # nó é preservada pelo seed de tailscaled.state (repo privado).
  #
  # Os dois flags são necessários e não são redundantes:
  #   extraUpFlags  -> só roda no registro (tailscaled-autoconnect, quando o
  #                    backend está em NeedsLogin/NeedsMachineAuth/Stopped)
  #   extraSetFlags -> unidade tailscaled-set, roda `tailscale set` em todo
  #                    boot, então reafirma o nome em nó já registrado
  services = {
    tailscale = {
      enable = true;
      extraUpFlags = [ "--hostname=wsl-nix" ];
      extraSetFlags = [ "--hostname=wsl-nix" ];
    };
    # Só chave, sem senha. O login aqui nasce com o `initialPassword` de
    # bootstrap (ver users.users abaixo), e o firewall do NixOS não roda dentro
    # do WSL: quem filtra o tráfego de entrada é o do Windows. Então a chave é
    # a única tranca que este repo controla de fato, e `openFirewall = false`
    # (o que laptop e desktop usam) aqui não faria nada.
    # Paseo roda do lado que tem o codigo: o daemon executa os agentes no
    # filesystem local e nada e sincronizado do cliente para ele (`--cwd` e um
    # path no host do daemon). Como os repos moram aqui, o daemon e daqui e o
    # cliente e sempre remoto, pelos dois caminhos que o par Windows+WSL ja
    # oferece: o browser do Windows em http://localhost:6767 (loopback
    # compartilhado pelo networkingMode=mirrored) ou o build Windows do app
    # desktop tunelando com `ssh -W`, o mesmo desenho que o Orca ja usa (ver a
    # chave orca-windows em authorizedKeys abaixo).
    #
    # `user` aponta para a conta real em vez do usuario de sistema `paseo`, e
    # isso decide duas coisas de uma vez: `dataDir` passa a ser ~/.paseo, e
    # `inheritUserEnvironment` liga sozinho, pondo os perfis do NixOS e do
    # home-manager no PATH do servico. Sem ele os agentes que o daemon spawna
    # nao enxergariam claude, opencode nem git.
    paseo = {
      enable = true;
      # O modulo do upstream aponta o servico para o package output do proprio
      # flake do Paseo (`services.paseo.package = lib.mkDefault
      # self.packages.<system>.default`), e nao para `pkgs.paseo`. Isso passa
      # por fora de qualquer overlay: o `fixPtyNode` do flake.nix consertava o
      # CLI do perfil do usuario e deixava o daemon com o pacote sem o addon
      # nativo do node-pty, ou seja, sem terminal e sem agente. Como la e
      # mkDefault, uma atribuicao simples ganha e realinha os dois.
      package = pkgs.paseo;
      user = vars.user.name;
      # Casa com o grupo real da conta; o default do modulo e o grupo `paseo`,
      # que so existe quando o servico roda como usuario de sistema e deixaria
      # ~/.paseo com dono aly:paseo.
      group = "users";
      listenAddress = "127.0.0.1";
      port = 6767;
      # Os dois clientes que este host atende sao locais ao par Windows+WSL,
      # entao nao ha motivo para o daemon discar para o relay hospedado em
      # app.paseo.sh so para alcancar uma maquina que ja esta no mesmo
      # loopback. Menos superficie e menos dependencia externa.
      relay.enable = false;
      # A web UI vem embutida no daemon mas nasce desligada. Ligada, ela e
      # servida na mesma origem da API, entao o browser em localhost:6767
      # conecta sozinho e pula a tela de "Add Host".
      #
      # `settings` reescreve ~/.paseo/config.json a cada start, entao a
      # configuracao do daemon passa a ser declarativa aqui e mudancas via
      # `paseo daemon set-password` ou pelo app nao sobrevivem. E uma escolha
      # ou outra, nao as duas.
      settings.features.webUi.enabled = true;
    };
    openssh = {
      enable = true;
      settings = {
        PermitRootLogin = "no";
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
      };
    };
  };

  networking.firewall.trustedInterfaces = [ "tailscale0" ];

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

    # Este era o único host pessoal sem authorizedKeys, ou seja, só entrava por
    # senha. A chave pessoal não é acessório: sem ela, o PasswordAuthentication
    # desligado acima trancaria o SSH no `wsl-nix` via Tailscale a partir do
    # desktop e do laptop.
    openssh.authorizedKeys.keys = [
      vars.user.publicKey

      # Cliente do Orca. A GUI roda no Windows e disca em localhost:22 (modo
      # espelhado), então a chave privada tem que morar do lado NTFS e não pode
      # ser a de ~/.ssh daqui de dentro. Chave da máquina cliente, não uma
      # segunda identidade, e por isso fora de vars.user.publicKey, que é a
      # identidade pessoal sozinha.
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIUOLPiN4yf7aJVczDZwLdWm3jz/QJHspofbuewxL4/5 orca-windows"
    ];
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

  # Link the Windows-side WSL driver libs (/usr/lib/wsl/lib) into
  # /run/opengl-driver so nvidia-smi, CUDA and OpenGL-over-D3D12 work
  wsl.useWindowsDriver = true;

  environment = {
    sessionVariables = {
      DISPLAY = ":0";
    };

    # Repetido de modules/core, que este host não importa (o NixOS-WSL traz base
    # própria, então aqui se declara usuário, pacotes e stateVersion na mão).
    # Ligar lá cobre desktop, laptop, vm e homelab, e não alcança este. Nenhuma
    # das duas cópias é redundante.
    #
    # O motivo está em modules/core; aqui o gatilho concreto é o Orca, que
    # registra um launcher em ~/.local/bin quando conecta neste host (wrapper
    # que atravessa a interop até o orca.exe do Windows) e avisa que o diretório
    # não está no PATH em NixOS. Está certo: quem o põe lá hoje é o
    # `home.sessionPath` do home-manager, que só chega via hm-session-vars.sh,
    # carregado apenas pelo ~/.zshenv.
    localBinInPath = true;
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
