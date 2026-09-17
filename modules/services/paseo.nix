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

  # O prompt de ditado: uma frase de estilo mais, quando houver, a lista de
  # palavras que o whisper erra sozinho. Ver o comentario no env la embaixo
  # para o que este campo faz e por que ele nao pode ser vazio.
  dictationPrompt =
    "Transcrição literal em português do Brasil, com pontuação, incluindo termos técnicos como deploy, rollback, commit, branch, worktree, Nix, NixOS, Paseo, Claude Code."
    + lib.optionalString (cfg.dictationVocabulary != [ ]) (
      " Nomes próprios: " + lib.concatStringsSep ", " cfg.dictationVocabulary + "."
    );

  # O mesmo overlay declarativo da omp que o home-manager entrega ao shell de
  # login. Aqui ele e obrigatorio e nao conveniencia: o daemon e servico de
  # sistema, nao passa por hm-session-vars, e todo agente omp que ele spawna
  # herda este environment. Sem PI_CONFIG_FILES a omp cai no default vazio de
  # `enabledProviders`, ou seja ignora ~/.claude por inteiro: nenhuma skill,
  # nenhum plugin e nenhum MCP server do Claude Code dentro do Paseo, sem erro
  # nenhum na tela. O ~/.omp/agent/config.yml mutavel nao segura isso: a propria
  # omp reescreve o arquivo no setup e a chave desaparece.
  ompConfigOverlay = import ../../home/features/cli/omp/config-overlay.nix { inherit pkgs; };
in
{
  imports = [ inputs.paseo.nixosModules.paseo ];

  options.modules.services.paseo.enable = lib.mkEnableOption ''
    o daemon do Paseo neste host, em 127.0.0.1, com as settings pessoais.

    Traz o modulo do flake do proprio Paseo e preenche `services.paseo`. Sem
    nenhuma porta publicada: quem expoe o daemon e `modules.services.paseoProxy`
    ou `modules.services.paseoTailnet`.
  '';

  options.modules.services.paseo.dictationVocabulary = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    example = [ "Nalyx" ];
    description = ''
      Nomes proprios a ensinar ao ditado, anexados ao prompt que acompanha cada
      audio. No whisper esse campo e bias de vocabulario, entao uma palavra
      listada aqui passa a ser reconhecida: medido, o nome de uma empresa volta
      como outra palavra sem ele na lista e correto com ele.

      Fica vazio no repo publico de proposito. Nome de empresa, cliente ou
      produto de trabalho identifica infraestrutura e pertence a uma camada
      privada, que e quem preenche esta lista.
    '';
  };

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

      # Herdado por todo agente omp que o daemon spawna. Ver o comentario do
      # `ompConfigOverlay` no let, que e onde o motivo esta escrito.
      environment.PI_CONFIG_FILES = "${ompConfigOverlay}";

      # O prompt que vai junto de todo audio de ditado. O default do daemon e
      # uma instrucao em ingles ("Transcribe only what the speaker says...",
      # dictation/dictation-stream-manager.ts:175), e ele e ruim duas vezes:
      # num modelo que segue instrucao a fala passa a ser lida como pedido, e
      # no whisper, onde `prompt` e bias de estilo e nao instrucao, um texto em
      # ingles enxerta ingles na transcricao de quem fala portugues. Nao ha
      # chave em `settings` para isto, so este env.
      #
      # Um prompt em portugues e nao string vazia: `Environment="FOO="` no
      # systemd deixa a variavel AUSENTE, nao vazia (verificado com unit de
      # teste), e ausente cai no `env ?? default`, ou seja traria a instrucao
      # em ingles de volta. Como precisa ser um valor definido, entao que seja
      # um valor util: estilo, pontuacao e os nomes proprios que o whisper
      # erra sozinho, que e o que `dictationVocabulary` acrescenta.
      environment.PASEO_DICTATION_TRANSCRIPTION_PROMPT = dictationPrompt;

      # A janela de commit do ditado, de 15s (default) para 5 minutos, e esta
      # e a causa real do ditado sair errado.
      #
      # O daemon nao manda a gravacao numa request: ele corta o audio a cada
      # `autoCommitSeconds`, transcreve cada pedaco separado e concatena os
      # textos (dictation-stream-manager.ts:605 e :758). O corte e cego, cai no
      # meio da frase, e o que fica em cima da emenda se perde. Medido contra
      # um daemon de teste com 46s de fala (778 chars): com 15s voltaram 710
      # chars, sem "subir a migracao do banco" e sem "do time consegue ler",
      # exatamente as duas emendas; com esta janela voltaram 781, completo.
      #
      # Pior quando os chunks chegam atrasados e em rajada, que e o caso do
      # celular pela tailnet: `commit()` em openai/stt.ts le o buffer e so o
      # zera no `finally`, depois da resposta. Dois commits sobrepostos
      # remandam o mesmo audio, e o mesmo teste com os chunks em rajada
      # devolveu os primeiros 15s repetidos quatro vezes, 967 chars. Com uma
      # janela que nao fecha antes do fim nao ha segundo commit para correr
      # contra o primeiro.
      #
      # 300s e nao 0 (que desligaria o fatiamento): o corpo e PCM 24 kHz mono
      # s16, ou seja 48 KB/s, e o limite de upload da API e 25 MB. 300s da
      # ~14 MB, entao qualquer ditado de tamanho humano vira uma unica request
      # e ainda sobra margem, em vez de trocar a emenda por um erro de tamanho
      # no ditado longo.
      environment.PASEO_DICTATION_AUTO_COMMIT_SECONDS = "300";

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
          # `whisper-1` e nao `gpt-4o-transcribe`: o segundo e um LLM
          # multimodal, e o daemon manda um prompt junto do audio em todo
          # ditado (o env acima). Modelo que segue instrucao pode ler a fala
          # como pedido e devolver resposta ou resumo no lugar da transcricao;
          # o `whisper-1` e ASR puro, onde prompt e so bias de vocabulario.
          # Exige `whisper-1` liberado no projeto da chave: fora da allowlist
          # a API responde 403 e o ditado vira `STT transcription failed`.
          #
          # O preco e o `confidenceThreshold`, que depende de logprobs que so
          # os modelos gpt-4o retornam (openai/stt.ts:187) e portanto fica
          # inerte aqui. Ou seja, transcricao ruim chega em vez de ser
          # descartada, o que e melhor que receber um resumo do que se falou.
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
            model = "whisper-1";
            language = "pt";
          };
          voiceMode = {
            stt = {
              provider = "openai";
              model = "whisper-1";
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

          # Os perfis que o seletor de modelo oferece em um clique, e que o
          # `list_profiles` do MCP entrega a um agente orquestrador antes de
          # ele lancar um worker. O campo que faz o trabalho e `notes`: a skill
          # `paseo` manda ler as notas e escolher, entao uma nota vaga devolve
          # escolha vaga. Sem perfil nenhum a alternativa e o orquestrador
          # listar os 89 modelos do provider e chutar, que foi o que aconteceu
          # antes disto existir.
          #
          # Revisao usa outra familia de modelo de proposito, e nao por gosto:
          # revisor da mesma familia de quem escreveu herda o mesmo ponto cego.
          agentProfiles = [
            {
              id = "planejamento";
              name = "Planejamento";
              provider = "omp";
              model = "anthropic/claude-opus-5";
              modeId = "ask";
              thinkingOptionId = "high";
              notes = "Arquitetura, investigacao de causa raiz, comparacao de abordagens e refinamento de demanda. Use quando a decisao ainda nao esta tomada e o custo de errar e alto. Nao implementa: o modo pede aprovacao pra escrever, de proposito, porque plano que ja comecou a editar deixou de ser plano.";
            }
            {
              id = "implementacao";
              name = "Implementacao";
              provider = "omp";
              model = "anthropic/claude-opus-5";
              modeId = "full";
              thinkingOptionId = "medium";
              notes = "Escrever codigo com contrato ja fechado: fatia de backlog, bug com causa conhecida, migracao mecanica de callsites. Roda sem pedir permissao, entao lance sempre em workspace com isolamento de worktree, nunca no checkout principal.";
            }
            {
              id = "revisao";
              name = "Revisao";
              provider = "omp";
              model = "anthropic/claude-opus-4-8";
              modeId = "ask";
              thinkingOptionId = "high";
              notes = "Revisao independente de diff: correcao, caso de borda faltando, teste ausente, complexidade sem funcao. Nao edita. Use SEMPRE um modelo diferente do que implementou: revisor igual ao autor herda o mesmo ponto cego. Aqui isso e geracao diferente (4.8 revisa o que o 5 escreveu), e nao familia diferente: o unico outro provider configurado autentica com a chave pessoal do usuario, e trabalho nao se paga com ela.";
            }
            {
              id = "triagem";
              name = "Triagem";
              provider = "omp";
              model = "anthropic/claude-haiku-4-5";
              modeId = "full";
              thinkingOptionId = "low";
              notes = "Trabalho de volume e pouca decisao: triagem de fila, varredura de logs, coleta de dados, atualizacao mecanica de registro. Rapido e barato, e e isso que se paga aqui. NAO use pra decidir arquitetura nem pra revisar codigo.";
            }
          ];

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

        # Quem escreve mensagem de commit, nome de branch e titulo de
        # workspace nao e o agente da conversa: e uma chamada unica, em
        # background, com um modelo proprio. Sem esta lista o daemon escolhe
        # sozinho, por substring, na ordem `haiku`, `gpt-5.4-mini`,
        # `minimax-m3`, `nemotron-3-super`, e o primeiro provider habilitado
        # que tenha um match ganha: hoje isso cai no provider `claude`, que
        # nao e por onde este usuario fala com os modelos.
        #
        # Os entries daqui sao tentados ANTES dos defaults, e o proximo so
        # roda se o anterior falhar, entao esta lista fixa o provider (omp,
        # que ja concentra todos os backends) e mantem a tarefa em modelos
        # pequenos, que e o tamanho certo para escrever uma linha.
        #
        # Haiku primeiro por seguir formato apertado melhor que um nano; o
        # mini da OpenAI como rede. `thinkingOptionId` fica de fora de
        # proposito: um valor invalido para o modelo cai no default dele
        # (`resolveThinkingOptionId`), e nao ha ganho em raciocinio longo
        # para uma frase.
        #
        # O mini autentica com OPENAI_API_KEY, que e a chave pessoal do usuario
        # vinda do SOPS da camada pessoal, e isso esta certo aqui: e a mesma
        # chave que ele ja usa para ditado e voz, e a tarefa e uma linha de
        # texto que so roda quando o Haiku falha. O que NAO pode usar essa
        # chave e trabalho de volume, tipo um perfil de revisao lendo diff
        # inteiro em thinking high: por isso o perfil de revisao e anthropic e
        # esta rede nao.
        agents.metadataGeneration.providers = [
          {
            provider = "omp";
            model = "anthropic/claude-haiku-4-5";
          }
          {
            provider = "omp";
            model = "openai/gpt-5.4-mini";
          }
        ];

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

    # `Restart=always`, e nao o `on-failure` do upstream. O daemon morre com
    # exit 0 quando alguem pede shutdown pela API, e o app desktop pede
    # exatamente isso ao fechar a janela (`keepRunningAfterQuit`, tratado na
    # activation em home/features/cli/paseo). Com `on-failure` esse exit limpo
    # nao religa nada: o servico fica morto e todo cliente remoto passa a ver
    # conexao recusada, que foi como o acesso pelo celular caiu na primeira
    # vez. Um daemon que existe para ser alcancado de fora nao pode depender de
    # ninguem ter deixado a janela aberta.
    #
    # `systemctl stop` continua parando de verdade: uma parada pedida ao
    # systemd nao dispara restart. O que volta e so a saida do proprio
    # processo.
    systemd.services.paseo.serviceConfig.Restart = lib.mkForce "always";
  };
}
