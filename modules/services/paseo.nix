{
  inputs,
  config,
  lib,
  pkgs,
  vars,
  ...
}:
# O daemon do Paseo, na forma que os hosts pessoais compartilham.
#
# O daemon roda do lado que tem o codigo: ele executa os agentes no filesystem
# local e nada e sincronizado do cliente para ele (`--cwd` e um path no host do
# daemon). Entao cada host que guarda repos hospeda o seu, e o cliente (browser
# ou app) e que vai atras. Este modulo e so o daemon; publicar na rede e
# decisao separada, em modules/services/paseo-proxy.nix (nginx + ACME, dominio
# proprio) ou modules/services/paseo-tailnet.nix (`tailscale serve`).
#
# O bloco nasceu dentro de hosts/wsl/default.nix e saiu de la quando o desktop
# passou a rodar o seu: as duas copias seriam identicas, menos por qual
# publicacao cada host usa, e o que interessa aqui (settings do daemon, quais
# providers de agente existem, voz em portugues) nao tem nada de host.
let
  cfg = config.modules.services.paseo;
in
{
  imports = [ inputs.paseo.nixosModules.paseo ];

  options.modules.services.paseo.enable = lib.mkEnableOption ''
    o daemon do Paseo neste host, em 127.0.0.1, com as settings pessoais.

    Traz o modulo do flake do proprio Paseo e preenche `services.paseo`. Sem
    nenhuma porta publicada: quem expoe o daemon e `modules.services.paseoProxy`
    ou `modules.services.paseoTailnet`.
  '';

  config = lib.mkIf cfg.enable {
    services.paseo = {
      enable = true;

      # O modulo do upstream aponta o servico para o package output do proprio
      # flake do Paseo (`services.paseo.package = lib.mkDefault
      # self.packages.<system>.default`), e nao para `pkgs.paseo`. Isso passa
      # por fora de qualquer overlay: o `fixPtyNode` do flake.nix consertava o
      # CLI do perfil do usuario e deixava o daemon com o pacote sem o addon
      # nativo do node-pty, ou seja, sem terminal e sem agente. Como la e
      # mkDefault, uma atribuicao simples ganha e realinha os dois.
      package = pkgs.paseo;

      # `user` aponta para a conta real em vez do usuario de sistema `paseo`, e
      # isso decide duas coisas de uma vez: `dataDir` passa a ser ~/.paseo, e
      # `inheritUserEnvironment` liga sozinho, pondo os perfis do NixOS e do
      # home-manager no PATH do servico. Sem ele os agentes que o daemon spawna
      # nao enxergariam claude, opencode nem git.
      user = vars.user.name;
      # Casa com o grupo real da conta; o default do modulo e o grupo `paseo`,
      # que so existe quando o servico roda como usuario de sistema e deixaria
      # ~/.paseo com dono aly:paseo.
      group = "users";
      listenAddress = "127.0.0.1";
      port = 6767;

      # Os clientes deste daemon chegam pelo loopback ou pela tailnet, entao
      # nao ha motivo para discar para o relay hospedado em app.paseo.sh so
      # para alcancar uma maquina que ja esta do outro lado do WireGuard.
      # Menos superficie e menos dependencia externa.
      relay.enable = false;

      # A web UI embutida, ligada pela variavel de ambiente e nao so pelo
      # `settings` abaixo, porque em 0.8.0-beta.1 a settings sozinha e inerte:
      # `resolveWebUiConfig` decide por
      # `cli?.webUiEnabled ?? env.PASEO_WEB_UI_ENABLED ?? persisted...`, e o
      # parser de `paseo-server` entrega `webUiEnabled = false` em vez de
      # undefined quando a flag `--web-ui` nao vem, entao o valor persistido
      # nunca e alcancado. Medido com o pacote desta geracao: sem isto `GET /`
      # e 404 ("web UI disabled or missing dist directory") e o browser do
      # celular nao acha nada, so a API. O `cfg.environment` do modulo do
      # upstream e aplicado por ultimo, entao ganha de tudo.
      #
      # As duas ficam: o env e o que liga, a settings e o que documenta (e o
      # que volta a valer quando o upstream consertar a precedencia).
      environment.PASEO_WEB_UI_ENABLED = "true";

      # `settings` reescreve ~/.paseo/config.json a cada start, entao a
      # configuracao do daemon passa a ser declarativa aqui e mudancas via
      # `paseo daemon set-password` ou pelo app nao sobrevivem. E uma escolha
      # ou outra, nao as duas.
      settings = {
        features = {
          webUi.enabled = true;

          # Voz pela OpenAI, e nao pelos modelos locais, por um motivo que
          # nao e qualidade sozinha: no provider local a chave `language` e
          # inerte (sherpa-parakeet-stt.ts recebe e nunca usa), entao o idioma
          # fica por conta de deteccao automatica e nao ha como fixar. Aqui
          # ela e enviada de verdade na request (openai/stt.ts:208), que e o
          # que torna o reconhecimento em portugues deterministico.
          #
          # `gpt-4o-transcribe` no lugar de `whisper-1`: supera o whisper em
          # multilingue e e o unico par com `gpt-4o-mini-transcribe` que
          # retorna logprobs, o que alimenta o `confidenceThreshold` e permite
          # descartar transcricao ruim em vez de entregar lixo.
          #
          # `tts-1-hd` e nao `gpt-4o-mini-tts`: o segundo provavelmente
          # funcionaria, porque o schema aceita string livre e o codigo
          # repassa o modelo direto para o SDK, mas openai/tts.ts:11 declara
          # so `tts-1` e `tts-1-hd`. Ficar dentro do que o upstream declara.
          #
          # O custo real disto nao e dinheiro (cerca de US$ 0,006 por minuto),
          # e o audio sair da maquina. Decisao consciente, nao default.
          #
          # A credencial NAO vem daqui: `providers.openai.apiKey` existiria no
          # schema, mas `settings` vira JSON no /nix/store, legivel por
          # qualquer usuario. A chave entra por OPENAI_API_KEY num
          # EnvironmentFile do SOPS, na camada privada.
          dictation.stt = {
            provider = "openai";
            model = "gpt-4o-transcribe";
            language = "pt";
          };
          voiceMode = {
            stt = {
              provider = "openai";
              model = "gpt-4o-transcribe";
              language = "pt";
            };
            # `voice` fica no default (`alloy`). O schema aceita alloy, echo,
            # fable, onyx, nova e shimmer.
            tts = {
              provider = "openai";
              model = "tts-1-hd";
            };
          };
        };

        daemon = {
          # As ferramentas MCP do proprio Paseo. `enabled` ja vem true de
          # fabrica; o que muda o comportamento e `injectIntoAgents`, que
          # nasce false e e o que de fato entrega as tools ao agente.
          mcp = {
            enabled = true;
            injectIntoAgents = true;
          };

          # Ferramentas de browser para os agentes. Depende de
          # `mcp.injectIntoAgents` acima e de um host desktop conectado, senao
          # as tools respondem `browser_disabled` / `browser_no_host`. O
          # browser em si e do app Electron, nao do daemon, e por isso nao ha
          # o que declarar aqui para "ligar o browser": so o acesso a ele.
          browserTools.enabled = true;

          autoArchiveAfterMerge = true;

          # `enableTerminalAgentHooks` fica de fora de proposito. Ele nao e
          # config do Paseo sozinho: o daemon passa a escrever hooks nos
          # arquivos de config dos agentes, ou seja no ~/.claude/settings.json,
          # que aqui e gerado por activation em
          # home/features/cli/claude/activation/settings.nix. Os dois
          # escrevendo no mesmo arquivo e briga garantida, e o Nix ganha no
          # proximo switch. Manter o Paseo fora do territorio do Claude.
        };

        pluginsEnabled = true;

        # Nao existe allowlist de provider: o modelo e opt-out por id, entao
        # calar os outros exige `enabled = false` em cada um. Os builtin sao
        # claude, codex, copilot, opencode, pi e omp.
        #
        # `omp` e o unico que nasce desligado (enabledByDefault = false no
        # manifest), por isso precisa ser ligado explicitamente mesmo sendo um
        # dos dois que queremos.
        agents.providers = {
          claude.enabled = true;
          omp.enabled = true;
          codex.enabled = false;
          copilot.enabled = false;
          opencode.enabled = false;
          pi.enabled = false;
        };

        # O overlay so define `paseo-github-integration` quando o input do repo
        # esta acessivel: a CI avalia os hosts com o placeholder vazio no lugar
        # do repo privado, e la nao ha plugin para declarar. `pluginsEnabled`
        # fica como esta, porque ligar o sistema de plugins e uma decisao
        # separada de qual plugin roda.
        #
        # O plugin em si roda sem sandbox: o lado servidor e um subprocesso Node
        # com o acesso do usuario do daemon (arquivos, processos, o token do
        # `gh`, as chaves ssh) e o lado cliente roda dentro do app. Vale so
        # porque o repo e nosso, com o codigo auditado antes de entrar.
      }
      // lib.optionalAttrs (pkgs ? paseo-github-integration) {
        plugins.github-integration = {
          # `directory` com um path do store em vez de `git`: a fonte git faz o
          # daemon clonar e seguir a branch, ou seja, codigo sem sandbox que se
          # atualiza sozinho pelas costas da geracao. Com o store path, a versao
          # do plugin e o rev do input no flake.lock, muda quando o lock muda, e
          # o rollback e o mesmo da geracao do sistema.
          source = "directory";
          path = "${pkgs.paseo-github-integration}";
          enabled = true;
        };
      };
    };
  };
}
