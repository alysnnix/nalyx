# Publica o daemon Paseo deste host atras de HTTPS com certificado real, para
# que o app desktop e o browser possam falar com ele de fora do par
# Windows+WSL sem depender de um tunel SSH aberto na mao.
#
# Topologia quando habilitado:
#   <fqdn>:443 (nginx, TLS ACME) -> paseo (127.0.0.1:<services.paseo.port>)
#
# O nginx escuta no loopback e num endereco extra, que na pratica e o IP da
# tailnet: o servico continua sem nenhuma porta publicada na internet, e o
# certificado existe so para que o browser aceite a origem e libere as APIs
# que exigem contexto seguro.
#
# Repo publico, entao aqui so mora a superficie de opcoes. O FQDN, o endereco
# da tailnet e as credenciais sao dado que identifica infraestrutura, entao
# quem preenche e a camada privada.
{
  vars,
  lib,
  config,
  ...
}:
let
  cfg = config.modules.services.paseoProxy;

  # Reservada para o omp-collab quando este proxy esta ligado. Os dois querem
  # a 443 do mesmo no: o `tailscale serve` do omp-collab faz o tailscaled
  # segurar o bind de <ip-tailnet>:443, e a partir dai o nginx nao consegue
  # mais subir nesse endereco. Mover o omp-collab e o caminho barato, porque
  # ele e alcancado por um punhado de convidados que ja recebem a URL pronta,
  # enquanto o Paseo precisa da porta default para que o app desktop e o
  # browser cheguem nele so com o hostname.
  ompCollabFallbackPort = 8443;
in
{
  options.modules.services.paseoProxy = {
    enable = lib.mkEnableOption ''
      um vhost nginx com TLS na frente do daemon Paseo local.

      Default false e nao ligado por nenhum host deste repo: domain e
      bindAddress nascem vazios de proposito, e liga-los sem valor e erro de
      avaliacao pela assertion abaixo. Assim um clone sem camada privada
      continua avaliando, e quem tem os valores e quem liga
    '';

    domain = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "servico.exemplo.invalid";
      description = ''
        FQDN pelo qual o daemon e alcancado. Vira o nome do vhost, o nome do
        certificado ACME e a unica entrada da allowlist de Host do Paseo.

        Sem default utilizavel: um nome de dominio real diria de quem e a
        infraestrutura, e este repo e publico.
      '';
    };

    bindAddress = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "127.0.0.2";
      description = ''
        Endereco extra onde o vhost escuta a 443, alem do loopback. Na pratica
        o IP que o tailscaled atribui a este no.

        Um endereco especifico e nao 0.0.0.0 de proposito: o WSL nao tem
        firewall do NixOS valendo (o modulo e mascarado ali dentro), entao o
        bind e o unico gate que este repo controla. Com 0.0.0.0 o daemon
        apareceria tambem na LAN de casa ou do escritorio.
      '';
    };

    cloudflareCredentialsFile = lib.mkOption {
      type = lib.types.path;
      example = "/run/secrets/cloudflare-dns-api";
      description = ''
        Arquivo de credenciais da API da Cloudflare consumido pelo lego no
        desafio DNS-01 do ACME.

        DNS-01 e nao HTTP-01 porque nada aqui e alcancavel da internet: o
        validador da Let's Encrypt nunca conseguiria buscar o token em
        http://<fqdn>/.well-known/. O desafio por DNS so exige que a zona
        responda, e ela responde.
      '';
    };

    passwordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/secrets/paseo-password";
      description = ''
        EnvironmentFile com `PASEO_PASSWORD=...`, entregue por SOPS.

        Opcional so na forma. Um daemon exposto na tailnet sem senha e um
        shell remoto para qualquer no dela.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.domain != "" && cfg.bindAddress != "";
        message = ''
          modules.services.paseoProxy esta habilitado sem domain ou
          bindAddress. Os dois vem da camada privada, por exemplo
          `modules.services.paseoProxy = { domain = "..."; bindAddress = "..."; };`.
          Erro e nao aviso porque um vhost sem nome pegaria o trafego de
          qualquer Host e um bind vazio derrubaria o nginx no boot.
        '';
      }
    ];

    # O nginx sobe antes de o tailscaled atribuir o IP da tailnet a interface,
    # e um bind num endereco que ainda nao existe falha na hora. Sem isto o
    # servico morre em todo boot e so volta com um restart manual depois que a
    # tailnet converge. Ordenar as unidades nao resolve, porque o endereco
    # aparece bem depois de o tailscaled reportar-se pronto.
    boot.kernel.sysctl."net.ipv4.ip_nonlocal_bind" = 1;

    security.acme = {
      acceptTerms = true;
      defaults.email = vars.user.email;
      certs.${cfg.domain} = {
        dnsProvider = "cloudflare";
        credentialsFile = cfg.cloudflareCredentialsFile;
        # O nginx roda como usuario proprio e precisa ler a chave privada; o
        # default do modulo deixa o material so para o grupo `acme`.
        group = "nginx";
      };
    };

    services.nginx = {
      enable = true;
      recommendedProxySettings = true;
      virtualHosts.${cfg.domain} = {
        useACMEHost = cfg.domain;
        forceSSL = true;
        listen = [
          {
            addr = "127.0.0.1";
            port = 443;
            ssl = true;
          }
          {
            addr = cfg.bindAddress;
            port = 443;
            ssl = true;
          }
        ];
        locations."/" = {
          proxyPass = "http://127.0.0.1:${toString config.services.paseo.port}";
          proxyWebsockets = true;
          # O Paseo streama a saida dos agentes por conexao longa e sem trafego
          # constante. Com os timeouts default (60s) o nginx corta a sessao no
          # meio de um agente pensando, e o cliente so ve a UI congelar. O
          # buffering desligado pela mesma razao: bufferizado, a saida so chega
          # ao browser em blocos, o que desfaz o ponto de ser streaming.
          extraConfig = ''
            proxy_read_timeout 1d;
            proxy_send_timeout 1d;
            proxy_buffering off;
          '';
        };
      };
    };

    services.paseo = {
      # O daemon rejeita com `403 Invalid Host header` todo Host que nao seja
      # localhost ou IP, protecao contra DNS rebinding. Servido por nome, o
      # nome precisa estar nesta allowlist, senao o proxy inteiro responde 403.
      hostnames = [ cfg.domain ];
    };

    # A senha entra por EnvironmentFile e nao por `services.paseo.settings`
    # porque `settings` e renderizado em JSON dentro do /nix/store, que e
    # legivel por qualquer usuario da maquina (e pelo que mais tiver acesso ao
    # store). Segredo em arquivo so aparece em runtime, com dono e modo que o
    # SOPS controla.
    systemd.services.paseo = lib.mkIf (cfg.passwordFile != null) {
      serviceConfig.EnvironmentFile = cfg.passwordFile;
    };

    # Tira o omp-collab da 443 deste no. Ver ompCollabFallbackPort acima para
    # por que e ele que sai, e nao o Paseo.
    modules.services.ompCollab.servePort = lib.mkForce ompCollabFallbackPort;
  };
}
