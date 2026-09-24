{
  config,
  lib,
  pkgs,
  ...
}:
# Publica o daemon do Paseo na tailnet, e so nela.
#
# Topologia quando habilitado:
#   https://<fqdn>:443 (tailscaled, TLS proprio) -> paseo (127.0.0.1:<port>)
#
# Quem termina o TLS e o proprio tailscaled, com certificado que ele emite para
# o nome MagicDNS do no. Nao ha ACME, nao ha dominio a manter e nao ha porta
# publicada fora da tailnet: `tailscale serve` so atende o endereco 100.x deste
# no. Por isso este e o caminho para um host que quer ser alcancado do celular
# ou de outra maquina sem virar servidor web, e modules/services/paseo-proxy.nix
# (nginx + ACME + dominio proprio) segue existindo para o caso oposto.
#
# Os dois nao coexistem no mesmo host: `tailscale serve` faz o tailscaled
# segurar o bind de <ip-tailnet>:443, que e exatamente onde o vhost do
# paseo-proxy escuta. Assertion abaixo, em vez de um dos dois morrer no boot.
#
# Autenticacao: nenhuma aqui. O daemon nasce sem senha, entao quem decide quem
# alcanca a 443 deste no e a ACL da tailnet, e essa regra E a tranca. Um src a
# mais ali e execucao arbitraria de codigo como o usuario do daemon.
let
  cfg = config.modules.services.paseoTailnet;
  target = "http://127.0.0.1:${toString config.services.paseo.port}";
in
{
  options.modules.services.paseoTailnet = {
    enable = lib.mkEnableOption ''
      publicar o daemon Paseo local na tailnet com `tailscale serve`, em 443.

      Precisa de `modules.services.paseo.enable` (ou de outro `services.paseo`)
      no mesmo host, e de uma regra de ACL liberando a 443 deste no para quem
      deve alcancar: sem ela o cliente recebe timeout, porque o deny e default.
    '';

    fqdn = lib.mkOption {
      type = lib.types.str;
      default = "";
      example = "host.tailnet-name.ts.net";
      description = ''
        Nome MagicDNS deste no, com o sufixo da tailnet.

        Nao e derivavel aqui: o sufixo e um valor da tailnet, que nao entra num
        repo publico, e o nome do no e do control plane, nao do hostname do SO.
        Vem da camada privada, e a unidade compara com o que o `tailscale
        status` reporta no start, entao um no renomeado falha com mensagem em
        vez de servir uma origem que o daemon vai recusar.

        Alimenta as duas checagens que o daemon faz em cada request do
        navegador: `services.paseo.hostnames` (header Host, protecao contra DNS
        rebinding) e `daemon.cors.allowedOrigins` (header Origin, mandado em
        todo handshake de WebSocket, inclusive de mesma origem).
      '';
    };

    extraAllowedOrigins = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ "https://other-host.tailnet-name.ts.net" ];
      description = ''
        Origens alem da propria que o daemon aceita no handshake de WebSocket.

        Uma UI do Paseo servida por outro no (a web UI de outra maquina que
        adiciona este daemon como host) manda o Origin dela, nao o deste no, e
        o daemon fecha o socket com "Rejected connection from origin". O app
        nativo nao passa por isso porque manda `paseo://app`. Mesma opcao que
        `modules.cli.paseo.tailnetServe.extraAllowedOrigins` do lado
        home-manager; os valores nomeiam a tailnet e vem da camada privada.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.fqdn != "";
        message = ''
          modules.services.paseoTailnet esta habilitado sem fqdn. O valor vem
          da camada privada, por exemplo
          `modules.services.paseoTailnet.fqdn = "host.tailnet.ts.net";`.
          Erro e nao aviso porque sem ele o daemon responde 403 a todo request
          que nao venha de localhost, ou seja, a publicacao inteira fica muda.
        '';
      }
      {
        # `or false` porque o modulo do proxy so e importado pelo host que o
        # usa: num host que importa so este, o caminho da opcao nem existe.
        assertion = !(config.modules.services.paseoProxy.enable or false);
        message = ''
          modules.services.paseoTailnet e modules.services.paseoProxy ligados
          no mesmo host: os dois querem a 443. O `tailscale serve` faz o
          tailscaled segurar o bind de <ip-tailnet>:443 e o vhost do nginx nao
          sobe mais nesse endereco. Escolha um.
        '';
      }
    ];

    services.paseo = {
      # Header Host. O daemon recusa com `403 Invalid Host header` tudo que nao
      # seja localhost ou IP, e servido por nome o nome tem que estar aqui.
      hostnames = [ cfg.fqdn ];

      # Header Origin, checagem distinta da de cima e igualmente obrigatoria. O
      # sintoma de faltar engana: a pagina carrega inteira, porque o HTML e
      # estatico e nao passa por checagem de origem, e so o WebSocket e
      # recusado, com "Rejected connection from origin" no daemon.log. Sem
      # WebSocket o app nao completa o autoconnect e cai na tela /welcome, que
      # parece "a publicacao nao funcionou".
      settings.daemon.cors.allowedOrigins = [ "https://${cfg.fqdn}" ] ++ cfg.extraAllowedOrigins;
    };

    systemd.services.paseo-tailnet-serve = {
      description = "Tailscale Serve -> Paseo daemon";
      after = [
        "tailscaled.service"
        "paseo.service"
        "network-online.target"
      ];
      requires = [ "tailscaled.service" ];
      wants = [
        "paseo.service"
        "network-online.target"
      ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      # `serve` e operacao de controle: o tailscaled so aceita de root, e esta
      # unidade roda como root. O `--bg` registra o handler no estado do
      # tailscaled, que o persiste entre boots; rodar de novo e idempotente, e
      # e o que mantem o handler alinhado quando a porta do daemon muda.
      script = ''
        for _ in $(seq 1 60); do
          state="$(${pkgs.tailscale}/bin/tailscale status --json 2>/dev/null \
            | ${pkgs.jq}/bin/jq -r .BackendState)" || state=""
          [ "$state" = "Running" ] && break
          sleep 1
        done
        if [ "$state" != "Running" ]; then
          echo "tailscale nao esta rodando (estado: ''${state:-desconhecido}), nao publicando o paseo" >&2
          exit 1
        fi

        actual="$(${pkgs.tailscale}/bin/tailscale status --json \
          | ${pkgs.jq}/bin/jq -r '.Self.DNSName | rtrimstr(".")')"
        if [ "$actual" != "${cfg.fqdn}" ]; then
          echo "este no se chama '$actual', mas modules.services.paseoTailnet.fqdn diz '${cfg.fqdn}'" >&2
          echo "servir assim daria 403 no daemon; corrija o fqdn na camada privada" >&2
          exit 1
        fi

        echo "publicando o paseo em https://${cfg.fqdn} (-> ${target})"
        ${pkgs.tailscale}/bin/tailscale serve --bg --https=443 ${target}
      '';

      # Remove so o handler desta porta, e nao `serve reset`, para nao derrubar
      # outra coisa que este no esteja servindo.
      preStop = "${pkgs.tailscale}/bin/tailscale serve --https=443 off || true";
    };
  };
}
