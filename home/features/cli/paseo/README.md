# Paseo

Daemon self-hosted para agentes de código. Este documento é sobre **operar** o
Paseo nesta config: adicionar projetos, escolher cliente, e publicar o daemon
fora do loopback, num domínio próprio ou na tailnet. Para o porquê de cada
decisão de empacotamento, os comentários em prosa nos arquivos `.nix` citados
abaixo são a fonte.

## A regra que explica todo o resto

O daemon executa os agentes **no filesystem da máquina onde ele roda**, e não
sincroniza nada do cliente para o daemon. O `--cwd` de qualquer comando é um
caminho no host do daemon.

Consequência prática: o daemon mora onde os repositórios moram, e nesta config
isso são três máquinas, cada uma com o seu daemon em `127.0.0.1:6767`: o WSL, o
desktop e o laptop de trabalho. No WSL o cliente é sempre remoto, e é só uma
janela; no desktop a janela é local, e mesmo ali o app Electron é apontado para
o daemon do host em vez de subir o próprio.

Nenhuma das três abre o daemon na rede. O que muda entre elas é quem publica a
porta 443 do nó:

```
WSL (nixos-wsl)              desktop (NixOS)         laptop sem NixOS
  daemon :6767                 daemon :6767            daemon :6767
   ^ browser do Windows          ^ app Electron local    ^ browser local
   ^ app desktop, ssh -W         |                       |
  nginx :443, TLS ACME         tailscale serve :443    tailscale serve :443
   ^                             ^                       ^
   +-----------------------------+-----------------------+
             celular e os outros nós, pela tailnet
```

## Onde a configuração vive

| Arquivo | O que declara |
|---|---|
| `flake.nix` | o input `paseo`, e o overlay `fixPtyNode` que conserta os pacotes |
| `modules/services/paseo.nix` | `services.paseo`: o daemon como serviço systemd em `127.0.0.1:6767` e todo o bloco `settings`, na forma que wsl e desktop compartilham |
| `modules/services/paseo-tailnet.nix` | publica esse daemon na tailnet com `tailscale serve`, desligado por padrão |
| `modules/services/paseo-proxy.nix` | o nginx com TLS para um domínio próprio, desligado por padrão |
| `hosts/wsl/default.nix` | liga o daemon compartilhado e importa o `paseoProxy`, que quem liga é a camada privada, dona dos valores |
| `hosts/desktop/default.nix` | liga o daemon compartilhado e importa o `paseoTailnet`, que quem liga é a camada privada, dona do FQDN |
| `home/features/cli/paseo/` | o CLI em todo host, o app desktop só onde há janela, e `modules.cli.paseo.daemon` / `tailnetServe` para um host sem NixOS |

O bloco `services.paseo` morava em `hosts/wsl/default.nix`. Ele saiu de lá para
`modules/services/paseo.nix` quando o desktop passou a querer o mesmo daemon:
são dois hosts com os mesmos repositórios em disco e a mesma resposta, então a
forma do serviço é uma só, e cada host decide apenas quem publica a porta.

## Projetos e workspaces

São dois níveis, e a distinção importa:

- **project**: um diretório registrado. É só o "esse repositório existe".
- **workspace**: onde o agente realmente trabalha, criado a partir de um project.
  Um project tem vários workspaces, e cada workspace hospeda agentes, terminais
  e browsers como abas.

### Adicionar um diretório

```bash
paseo project create ~/nalyx     # caminho explícito
paseo project create             # ou o diretório atual
paseo project ls
```

Ele detecta se é git sozinho (o `kind` vira `git` em vez de `non_git`). Para um
repositório que ainda não está em disco, `paseo clone <repo>` clona e registra
numa tacada.

Remover: `paseo project delete <project-id>`, que leva junto os workspaces dele.

### Isolamento: `local` ou `worktree`

```bash
# trabalha direto no seu checkout
paseo workspace create --isolation local --path ~/nalyx --title main

# cria um git worktree gerenciado, em branch própria
paseo workspace create --isolation worktree --path ~/nalyx \
  --mode branch-off --new-branch feat/algo --base origin/main
```

Os três modos de worktree:

| `--mode` | Para quê | Flags |
|---|---|---|
| `branch-off` (default) | começar do zero numa branch nova | `--new-branch`, `--base` |
| `checkout-branch` | retomar uma branch existente | `--branch` |
| `checkout-pr` | abrir um PR no próprio workspace | `--pr-number` |

Os worktrees nascem em `$PASEO_HOME/worktrees` (ou seja `~/.paseo/worktrees`),
organizados por hash do caminho do checkout de origem. Para mudar isso, use
`worktrees.root`, e leia a seção "config declarativa" antes.

`--isolation worktree` é o que casa com a regra de "uma tarefa, um worktree"
das regras globais de agente. Vale como padrão para qualquer trabalho que vá
gerar commits.

### `paseo.json` no repositório

O Paseo lê um `paseo.json` da raiz do projeto. É onde se declara o que rodar
depois de criar um worktree, e os serviços de longa duração:

```json
{
  "worktree": {
    "setup": "npm ci",
    "teardown": "rm -rf .cache"
  }
}
```

`setup` roda uma vez, logo após a criação do worktree; `teardown` roda no
archive. Também dá para declarar `scripts` nomeados e `services` com porta, que
ficam acessíveis por um proxy interno em hostnames determinísticos no formato
`http://<script>--<branch>--<project>.localhost`.

## Clientes

### Web UI, no navegador do Windows

Já está ligada, mas não por `settings.features.webUi.enabled`: em
0.8.0-beta.1 essa chave é inerte. `resolveWebUiConfig` decide por
`cli?.webUiEnabled ?? env.PASEO_WEB_UI_ENABLED ?? persisted...`, e o parser do
`paseo-server` entrega `webUiEnabled = false` em vez de undefined quando a
flag `--web-ui` não vem, então o valor persistido nunca é alcançado. Quem liga
de fato é `services.paseo.environment.PASEO_WEB_UI_ENABLED = "true"`, em
`modules/services/paseo.nix`; a settings fica ao lado, documentando a
intenção. Sem o env, `GET /` responde 404 com
"web UI disabled or missing dist directory" no log, e só a API atende. Abra:

```
http://localhost:6767
```

Funciona sem port forward porque o `.wslconfig` está em
`networkingMode=mirrored`, que compartilha o loopback entre Windows e WSL. A web
UI é servida pelo próprio daemon, então ela conecta na própria origem e pula a
tela de "Add Host". Não existe seletor de host aqui, e não é bug: só existe um
daemon, o que está servindo a página.

Instalando como PWA pelo Edge ou Chrome, você ganha janela própria sem barra de
navegador.

### App desktop no Windows

O app embute um daemon próprio. Esse **não** é o que você quer: ele enxergaria o
filesystem do Windows, não os seus repositórios. Adicione o daemon do WSL como
host remoto:

`Settings` → `Add host` → `Remote SSH` → `ssh://aly@localhost`

Funciona porque o modo espelhado faz `localhost:22` do Windows chegar no sshd do
WSL, e porque `hosts/wsl/default.nix` já autoriza a chave da máquina Windows nas
`authorizedKeys` (a mesma que o Orca usa).

O transporte é `ssh -T -o BatchMode=yes ... -W 127.0.0.1:6767`. O `BatchMode=yes`
é a pegadinha: **não existe prompt de senha**. A chave precisa estar sem
passphrase ou carregada no ssh-agent, e apontada por `IdentityFile` no
`~/.ssh/config` do Windows. Teste antes, no PowerShell:

```powershell
ssh -o BatchMode=yes aly@localhost echo ok
```

Se isso não imprimir `ok`, o Paseo também não conecta, e a mensagem de erro dele
não vai deixar claro que a causa foi essa.

### Celular

`Settings` → `Add host` → `Direct connection`, com a URL publicada do host, não
com `100.x:6767`: o daemon nunca escuta fora do loopback. Quem publica é o
nginx do `paseoProxy` no wsl e o `tailscale serve` do `paseoTailnet` no
desktop, as duas seções logo abaixo. Nos dois casos o endereço é `https://`, e
o certificado existe justamente para isso: sem contexto seguro o navegador
recusa parte das APIs que a UI usa.

## Fora do NixOS: o daemon no perfil `wrk`

Num host sem camada NixOS não existe `services.paseo`. O perfil `wrk` liga
`modules.cli.paseo.daemon`, que roda o mesmo `paseo-server` como serviço
systemd **de usuário**, em `127.0.0.1:6767`, com a parte gerenciada do
`config.json` mesclada por cima da existente a cada start (gerenciado vence, o
resto sobrevive, ao contrário dos hosts NixOS, onde o Nix reescreve o arquivo
inteiro).

`modules.cli.paseo.tailnetServe` publica esse daemon com `tailscale serve` em
`https://<nó>.<tailnet>.ts.net`, com o certificado que o próprio tailscaled
emite. O nome do nó é lido de `tailscale status` na hora, então nem o nome nem
a tailnet aparecem no repositório, e as duas checagens do daemon (`hostnames`
e `cors.allowedOrigins`) são preenchidas a partir dele. Quem alcança a 443 é a
ACL da tailnet, como no wsl e no desktop.

É a mesma forma do `modules.services.paseoTailnet` do desktop, um nível abaixo:
lá a unidade é de sistema e o FQDN é declarado pela camada privada; aqui é
serviço de usuário e o FQDN é descoberto em runtime.

Um passo manual, uma vez só: `paseo-tailnet-operator-setup`. `tailscale serve`
só aceita ordem de root ou do operador, e isso é
`sudo tailscale set --operator=$USER`.

O outro passo, desligar "Manage built-in daemon" no app desktop, é feito pela
activation: ela vira `manageBuiltInDaemon` para `false` em
`~/.config/Paseo/desktop-settings.json`, e sem isso o app sobe um segundo
daemon na mesma porta. Quem ganha o bind costuma ser o do app, que é lançado
com `--no-web-ui`: a tailnet então alcança a API e recebe 404 em toda rota de
UI. O app precisa ser reiniciado para largar o daemon que já subiu.

`systemctl --user status paseo paseo-tailnet-serve` mostra os dois; o segundo
imprime a URL final no log.

## Domínio próprio

`modules/services/paseo-proxy.nix` põe um nginx com TLS na frente do daemon, que
continua em `127.0.0.1:6767`. Só o proxy fica exposto, o que é bem melhor do que
abrir o daemon.

O módulo nasce **desligado**, e o repositório público não carrega nenhum valor:
o FQDN, o IP da tailnet e as credenciais de DNS são dados pessoais e vêm da
camada privada, seguindo a regra de "o público oferece a opção, o privado liga".

```nix
modules.services.paseoProxy = {
  enable = true;
  domain = "paseo.exemplo.dev";
  bindAddress = "100.x.y.z";                     # o IP desta máquina na tailnet
  cloudflareCredentialsFile = config.sops.templates."paseo-acme-cloudflare".path;
};
```

O que cada peça faz:

- **ACME por DNS-01.** O certificado é Let's Encrypt de verdade, emitido pelo
  desafio de DNS no Cloudflare. Ninguém precisa alcançar a máquina pela
  internet, então HTTP-01 não serviria.
- **`bindAddress`.** O nginx escuta em `127.0.0.1:443` e no IP da tailnet. É
  deliberadamente específico em vez de `0.0.0.0`, que exporia o daemon também na
  LAN. Junto vem `net.ipv4.ip_nonlocal_bind = 1`, porque o nginx sobe antes de o
  `tailscaled` atribuir o IP, e sem isso o bind falharia no boot.
- **`services.paseo.hostnames`.** Preenchido com o domínio automaticamente. Sem
  isso o daemon responde `403 Invalid Host header`, por causa da proteção contra
  DNS rebinding.
- **`daemon.cors.allowedOrigins`.** Também preenchido com o domínio. São duas
  checagens independentes e preencher só `hostnames` não basta: aquela olha o
  header `Host`, que quem manda é o nginx, e esta olha o `Origin`, que quem
  manda é o navegador. Mesma origem não isenta, o navegador manda `Origin` em
  todo handshake de WebSocket.
- **`passwordFile`.** Existe como opção, mas **não é usado aqui**. Veja "Quem
  autentica" logo abaixo.

### Quem autentica: a ACL da tailnet, não uma senha

O daemon nasce **sem autenticação**, e até existir proxy a única proteção era o
bind em loopback. Com o proxy, a pergunta passa a ser quem alcança a porta 443
deste nó, e a resposta está na ACL da tailnet, não numa senha.

A ACL já dava `autogroup:admin` para os devices do dono e deixava os tagueados
sem nenhuma regra de `src`, então o deny implícito os barra. Isso foi verificado
de dentro de um host tagueado: a conexão nem estabelece.

Uma senha por cima disso custa caro e entrega pouco. Ela vale para **todo**
cliente do daemon, então o `paseo` no terminal passa a responder
`Password required` a cada comando, e a web UI embutida **não tem tela de
login** para oferecer. O único caminho documentado é `Add Host` >
`Direct connection`, digitando a senha à mão em cada navegador.

O que fica descoberto é o loopback: qualquer processo local alcança o daemon sem
autenticar. Isso já era verdade antes de existir proxy.

Consequência que precisa estar escrita em algum lugar: a ACL virou
**load-bearing**. Adicionar uma regra de `src` para um device tagueado, ou
tagear uma máquina em que você não confia totalmente, entrega execução de código
como o usuário nesta máquina.

### O que alcança o serviço

| Origem | Alcança | Por quê |
|---|---|---|
| Devices do dono na tailnet | sim | `autogroup:admin` na ACL |
| Devices tagueados | não | sem regra de `src`, deny implícito |
| Outra máquina na LAN | não | o nginx não escuta no IP da LAN |
| Internet | não | nada publicado, e o A aponta para um IP `100.x` |
| Processos locais | sim, sem autenticar | loopback |

O registro DNS é público e qualquer um no mundo resolve o nome, mas ele devolve
um endereço CGNAT da tailnet. Expor o nome não expõe o serviço.

### Os três passos que não são Nix

1. **Token do Cloudflare** com permissão de editar DNS da zona, guardado como
   secret SOPS. Sem ele o ACME não emite nada.
2. **Registro A** apontando `paseo.exemplo.dev` para o IP `100.x.y.z` da tailnet.
   DNS público pode apontar para IP privado sem problema: quem não está na
   tailnet simplesmente não alcança.
3. **Entrada no `hosts` do Windows** mapeando o mesmo nome para `127.0.0.1`,
   feita como Administrador. Não é conforto: sem ela o nome resolve pelo DNS
   público para o IP da tailnet, e o navegador só chega lá enquanto o Tailscale
   do Windows estiver conectado.

E um quarto passo que só vale na primeira vez: **disparar a emissão do
certificado à mão**.

```bash
sudo systemctl start acme-order-renew-<dominio>.service
```

O `switch` sozinho não emite nada. O NixOS separa "garantir que existe algum
certificado para o nginx subir", que gera um autoassinado com `minica`, de
"pedir o certificado real", que é esta unidade e fica esperando o timer. O timer
pode estar a mais de um dia de distância, então na primeira vez o navegador
reclamaria de certificado inválido sem motivo aparente. Depois disso a renovação
é automática.

### Efeito colateral no omp-collab

Ligar o proxy move o `tailscale serve` do omp-collab de `:443` para `:8443`
(`modules.services.ompCollab.servePort`), porque o `tailscaled` segura o bind da
443 no IP da tailnet e o nginx precisa dela. O omp-collab continua funcionando,
só muda de porta na URL.

## Na tailnet: o desktop com `tailscale serve`

O desktop é um host NixOS pessoal com os repositórios em disco, então ele quer
o mesmo daemon do wsl, e é literalmente o mesmo: `modules/services/paseo.nix`
carrega o módulo do flake do Paseo e concentra a forma que os dois hosts
compartilham (package, user, grupo, `127.0.0.1:6767`, relay desligado e todo o
bloco `settings`). Serviço de **sistema**, como no wsl, e não o serviço de
usuário que o laptop sem NixOS usa.

O host importa os dois módulos e liga o daemon; a publicação é ligada pela
camada privada, porque `enable` e `fqdn` andam juntos e o FQDN é o dado que não
entra aqui. A mesma divisão do `paseoProxy` no wsl:

```nix
# hosts/desktop/default.nix
modules.services.paseo.enable = true;

# camada privada, que é quem pode nomear a tailnet
modules.services.paseoTailnet = {
  enable = true;
  fqdn = "host.tailnet-name.ts.net";
};
```

`paseoTailnet` publica esse daemon na tailnet: uma unidade systemd
`paseo-tailnet-serve` que roda
`tailscale serve --bg --https=443 http://127.0.0.1:6767`, e que, como o proxy,
preenche as duas checagens do daemon a partir do FQDN: `services.paseo.hostnames`
recebe o nome (header `Host`), e `daemon.cors.allowedOrigins` recebe
`https://<fqdn>` (header `Origin`).

O FQDN é `modules.services.paseoTailnet.fqdn`. Ele nasce vazio, com assertion
exigindo valor quando o módulo está ligado, porque o valor real nomeia a
tailnet e isso não entra em repositório público: quem preenche é o módulo
privado que o `flake.nix` passa para este host. A unidade ainda confere esse
valor contra o que o `tailscale status` reporta e falha com mensagem se
divergirem, porque servir por um nome que o daemon não conhece daria 403 em
tudo, e um nó renomeado é exatamente como isso acontece.

A unidade é de sistema e fala com o `tailscaled` como root, então o passo de
operador que o laptop sem NixOS precisa não se aplica aqui. O `--bg` registra o
handler no estado do `tailscaled`, que o mantém entre boots, e rodar de novo é
idempotente.

### Por que não o nginx do `paseoProxy`

Porque aqui não há nada para o ACME fazer. O `tailscale serve` entrega TLS e
nome de uma vez: o certificado é emitido pelo próprio `tailscaled` e o nome é o
MagicDNS do nó. Desaparecem o domínio, o registro A, o token do Cloudflare e o
passo manual da primeira emissão, e nada é publicado fora da tailnet. O que
resta de configuração é uma porta.

O nginx continua valendo onde o `tailscale serve` não chega: um nome próprio,
alcançável por um cliente que não está na tailnet. É o caso do wsl, que serve o
navegador do Windows pelo mesmo nome, com a entrada no `hosts`.

E os dois não convivem no mesmo host, porque ambos querem a 443 do nó: com o
serve ligado o `tailscaled` segura o bind de `<ip-tailnet>:443`, e o nginx do
proxy não sobe mais nesse endereço. `modules/services/paseo-tailnet.nix` tem
assertion contra ligar os dois juntos, e é a mesma disputa que move o
omp-collab para `:8443` quando o proxy está ligado.

### O app Electron local, e a porta

No desktop existe janela, e o app roda no mesmo host que o daemon. Dois daemons
não dividem a 6767, então o app não pode subir o dele: a activation de
`home/features/cli/paseo/` vira `manageBuiltInDaemon` para `false` em
`~/.config/Paseo/desktop-settings.json` sempre que este host tem daemon
gerenciado, seja o serviço de usuário do laptop, seja o de sistema daqui. O app
precisa ser reiniciado uma vez para largar o daemon que já tinha subido.

Quem ganha a porta importa: o app lança o daemon dele com `--no-web-ui`, então
se ele vencer a corrida o celular alcança a API e recebe 404 em toda rota de UI.

### O passo que não é Nix: a ACL da tailnet

O daemon não tem senha, aqui como no wsl: quem autentica é a ACL, e é ela que
precisa liberar a 443 deste nó. Enquanto a regra não existe o celular não recebe
403 nem tela de login, recebe **timeout**, porque a conexão nem estabelece. A
ACL é dado de infraestrutura pessoal e vive no repositório privado, junto com o
FQDN.

A tabela "o que alcança o serviço" acima vale igual aqui, com uma troca: a LAN
fica de fora porque o `tailscaled` só serve dentro da tailnet, não porque um
nginx escolheu em qual endereço escutar.

## Config declarativa: uma escolha, não duas

`services.paseo.settings` reescreve `~/.paseo/config.json` **a cada start** do
serviço. Então qualquer coisa ajustada em runtime, pelo CLI ou pela UI do app,
não sobrevive ao próximo restart.

A regra é escolher um lado. Aqui o lado é o Nix: ajuste de daemon vai em
`services.paseo.settings` no host, e não na interface.

O que está declarado hoje em `modules/services/paseo.nix`, para os dois hosts:

| Chave | Efeito |
|---|---|
| `features.webUi.enabled` | intenção declarada, inerte em 0.8.0-beta.1; quem serve a UI é `environment.PASEO_WEB_UI_ENABLED` |
| `daemon.mcp.injectIntoAgents` | entrega as ferramentas do Paseo ao agente |
| `daemon.browserTools.enabled` | dá acesso às ferramentas de browser |
| `daemon.autoArchiveAfterMerge` | arquiva workspace quando o PR é mergeado |
| `pluginsEnabled` | liga o carregamento de plugins locais |
| `agents.providers.<id>.enabled` | deixa só Claude Code e Oh My Pi ligados |

Sobre os providers: **não existe allowlist**. O modelo é opt-out por id, então
calar os outros exige `enabled = false` em cada um. Os builtin são `claude`,
`codex`, `copilot`, `opencode`, `pi` e `omp`. O `omp` é o único que nasce
desligado, então precisa ser ligado explicitamente mesmo sendo um dos dois que
se quer.

### O que fica de fora, e por quê

**`daemon.enableTerminalAgentHooks` não é ligado de propósito.** Ele não é
config do Paseo sozinho: o daemon passa a escrever hooks nos arquivos de config
dos agentes, ou seja no `~/.claude/settings.json`, que aqui é gerado por
activation em `home/features/cli/claude/activation/settings.nix`. Dois donos
escrevendo no mesmo arquivo é briga garantida, e o merge do Nix (`existing *
managed`, gerenciado vence) faz o Nix ganhar no próximo switch. O Paseo fica
fora do território do Claude.

**Três ajustes comuns não são alcançáveis por Nix**, porque não são config do
daemon:

| Ajuste | Onde vive |
|---|---|
| Browser interno | capacidade do app Electron, não existe chave. O que se liga é o acesso a ele, que é `daemon.browserTools` |
| Tool call display | preferência do cliente, chave `toolCallDetailLevel`, valores `overview` (mostrado como "Summary") e `detailed` |
| Fontes e tamanhos | preferências do cliente: `uiFontFamily`, `monoFontFamily`, `uiBaseFontSize`, `contentFontSize`, `codeFontSize` |

As preferências do cliente ficam no storage do navegador ou do app, sob
`@paseo:app-settings`, e portanto valem por device. Ajuste em Settings.

### Voz e idioma

O ditado e o modo de voz usam a OpenAI, não os modelos locais. A razão não é só
qualidade.

O provider local (sherpa-onnx) tem **três modelos, só isso**: `parakeet-...-v2`
(inglês, e é o default), `parakeet-...-v3` (25 idiomas europeus com detecção
automática, inclui português) e `kokoro-en-v0_19` (TTS, inglês). Nele a chave
`features.dictation.stt.language` **é inerte**: o código recebe o parâmetro e
nunca o usa, só o ecoa no evento de transcript. Ou seja, não há como fixar o
idioma, e o TTS não tem opção fora do inglês.

No provider da OpenAI a chave é enviada de verdade na request, o que torna o
reconhecimento em português determinístico em vez de depender de detecção.

| Chave | Valor | Por quê |
|---|---|---|
| `stt.provider` | `openai` | é onde `language` funciona |
| `stt.model` | `whisper-1` | ASR puro; um modelo que segue instrução trata a fala como pedido (ver abaixo) |
| `stt.language` | `pt` | ISO-639-1, não `pt-BR` |
| `tts.model` | `tts-1-hd` | `gpt-4o-mini-tts` provavelmente funcionaria, mas `openai/tts.ts:11` só declara `tts-1` e `tts-1-hd` |
| `tts.voice` | default `alloy` | aceita `alloy`, `echo`, `fable`, `onyx`, `nova`, `shimmer` |

O `whisper-1` precisa estar liberado no projeto da chave. A OpenAI permite
restringir modelos por projeto (Limit model access), e um modelo de fora da
lista devolve `403 Project ... does not have access to model whisper-1`, que no
ditado aparece como `STT transcription failed`.

#### Por que não `gpt-4o-transcribe`, e por que o prompt é substituído

O daemon manda, junto de todo áudio de ditado, uma instrução em inglês
(`"Transcribe only what the speaker says..."`,
`dictation/dictation-stream-manager.ts:175`). Num modelo multimodal que segue
instrução isso deixa a porta aberta para ele tratar a fala como pedido e
devolver resposta ou resumo em vez da transcrição. No `whisper-1` o campo
`prompt` é só bias de estilo e vocabulário, nunca instrução, mas aí um texto em
inglês enxerta inglês na transcrição de quem fala português.

Daí `PASEO_DICTATION_TRANSCRIPTION_PROMPT` receber uma frase em português com o
vocabulário que de fato se dita aqui. **Não** string vazia: `Environment="FOO="`
deixa a variável ausente no systemd, não vazia (verificado com unit de teste), e
ausente cai no `env ?? default`, ou seja traz a instrução em inglês de volta.
Como o valor precisa existir, que ele seja útil.

O preço de sair do `gpt-4o-transcribe` é o `confidenceThreshold`, que depende de
logprobs que só os modelos gpt-4o retornam (`openai/stt.ts:187`). Com whisper
ele fica inerte: transcrição ruim chega em vez de ser descartada, o que é melhor
que receber um resumo do que se falou.

#### A janela de commit, que é a causa real

O ditado não é uma request por gravação. O daemon corta o áudio a cada
`autoCommitSeconds` (default **15s**), transcreve cada pedaço separado e
concatena os textos (`dictation-stream-manager.ts:605` e `:758`). O corte é
cego: cai no meio da frase e o que fica em cima da emenda se perde.

Medido contra um daemon de teste, com 46s de fala (778 chars):

| Janela | Resultado |
|---|---|
| 15s (default) | 710 chars, sem "subir a migração do banco" e sem "do time consegue ler", exatamente as duas emendas |
| 15s, chunks em rajada | 967 chars, com os primeiros 15s repetidos quatro vezes |
| 300s | 781 chars, completo |

A rajada é o caso do celular pela tailnet, quando a conexão engasga e o cliente
despeja o atraso de uma vez: `commit()` em `openai/stt.ts` lê o buffer e só o
zera no `finally`, depois da resposta, então dois commits sobrepostos remandam o
mesmo áudio. Com uma janela que não fecha antes do fim não existe segundo commit
para correr contra o primeiro.

Daí `PASEO_DICTATION_AUTO_COMMIT_SECONDS = "300"`. O corpo é PCM 24 kHz mono
s16, ou seja 48 KB/s, e o limite de upload da API é 25 MB: 300s dá ~14 MB, então
todo ditado de tamanho humano vira uma única request e ainda sobra margem. Zero
desligaria o fatiamento de vez, mas trocaria a emenda por um erro de tamanho no
ditado longo.

A credencial **não** vai em `settings`, porque `settings` é renderizado como
JSON no `/nix/store` e seria legível por qualquer usuário da máquina. Ela entra
por `OPENAI_API_KEY` num `EnvironmentFile` vindo do SOPS, declarado na camada
privada.

Dois custos, e o segundo é o que importa: cerca de US$ 0,006 por minuto, e o
**áudio sai da máquina**. Para voltar ao local, troque os dois `provider` para
`local` e o modelo de STT para `parakeet-tdt-0.6b-v3-int8`, que é o único do
catálogo com português.

### Validar uma config antes de aplicar

O schema é `.strict()`: **uma chave desconhecida faz o daemon não subir**, com
`[Config] Invalid config in <path>`. Não há fallback para o default.

O upstream publica um JSON Schema em `paseo.sh/schemas/paseo.config.v1.json`,
mas ele é gerado por script e **pode estar defasado** em relação ao Zod que o
daemon usa de fato. Aconteceu: o schema publicado rejeitou `daemon.browserTools`
e `pluginsEnabled`, que existem e funcionam.

O teste que não mente é subir um daemon descartável com a config candidata:

```bash
mkdir -p /tmp/paseo-cfgtest
cp candidato.json /tmp/paseo-cfgtest/config.json
PASEO_HOME=/tmp/paseo-cfgtest PASEO_LISTEN=127.0.0.1:6799 paseo-server --no-relay
```

Se ele responder em `http://127.0.0.1:6799/api/health`, a config é válida.
Cuidado com o que você liga nesse teste: `enableTerminalAgentHooks` escreve nos
configs dos agentes do usuário real, porque `PASEO_HOME` isola o estado do
Paseo, não o resto do home.

## Pegadinhas conhecidas

**O terminal depende de um addon nativo que o build upstream perde.** O
`trace-daemon.mjs` do Paseo monta o closure por tracing estático e lista o
`node-pty` no caminho errado, então o `pty.node` é compilado e não copiado. Sem
ele o worker de terminal morre no import, o supervisor sobrevive, e o sintoma só
aparece no primeiro uso, como `TERMINAL_CREATE_FAILED: Terminal worker is not
running`. Sem terminal não há agente. O overlay `fixPtyNode` em `flake.nix`
conserta, e aborta o build se o upstream mudar o layout, para não virar no-op
silencioso.

**O módulo upstream ignora o overlay.** Ele faz
`services.paseo.package = lib.mkDefault self.packages.<system>.default`,
apontando para o output do flake do próprio Paseo. Por isso
`modules/services/paseo.nix` atribui `package = pkgs.paseo` explicitamente. Sem
essa linha, o CLI fica corrigido e o daemon não, e um `switch` parece não ter
efeito nenhum.

**`paseo daemon restart` não conhece o serviço systemd.** Ele mata o processo e
sobe um substituto solto, fora do unit, que fica com a 6767. O `paseo.service`
então não consegue dar bind e entra em loop de `Restart=on-failure`, enquanto o
app segue conversando com o processo avulso, que é o binário da geração
anterior. Isso faz um `switch` com correção no daemon parecer sem efeito, porque
o `ExecStart` novo nunca chega a rodar. Num host com o daemon gerenciado use
sempre o systemctl do serviço: `systemctl restart paseo` onde ele é de sistema
(wsl e desktop), `systemctl --user restart paseo` no laptop sem NixOS. Para
desfazer um restart avulso, pare o serviço, `paseo daemon stop`, conferir a
porta livre, e só então subir o serviço de novo.

**O `Applications/Paseo.AppImage` não é um AppImage.** É o nome que o launcher
do `paseo .` procura. O alvo é um wrapper shell em volta do electron.

**O acesso pelo celular depende da máquina ligada.** O nó da tailnet só existe
enquanto a máquina existe: o do wsl enquanto a distro WSL estiver rodando, o do
desktop enquanto o desktop estiver ligado. Nada disso é hospedado em outro
lugar, e por isso o celular tem dois alvos e não um.

**Cair na tela `/welcome` quase nunca é o proxy.** O HTML é estático e não passa
por checagem de origem, então a página carrega inteira mesmo quando o daemon
recusa a conexão. Sem WebSocket o app não completa o autoconnect e mostra o Add
Host. Olhe o `daemon.log`: `Rejected connection from origin` é
`daemon.cors.allowedOrigins`, e `Rejected WebSocket connection with invalid
daemon password` é credencial.

**O certificado não sai no primeiro switch.** Ver "Os três passos que não são
Nix" acima.

## Diagnóstico

```bash
systemctl status paseo            # o serviço
paseo daemon status               # versão, listen, home, providers
curl -s localhost:6767/api/health # o daemon responde?
tail -f ~/.paseo/daemon.log       # o log

# quem está com a porta? tem que ser o MainPID do unit, não um daemon avulso
ss -tlnp | grep 6767
systemctl show -p MainPID -p NRestarts --value paseo   # --user no laptop

# o terminal funciona? (isto é o que prova que o pty.node está no lugar)
paseo terminal create --cwd /tmp --json
```

## Referências

- Web UI e proxy reverso: <https://paseo.sh/docs/web-ui.md>
- Conectividade, SSH e Tailscale: <https://paseo.sh/docs/connectivity.md>
- Workspaces: <https://paseo.sh/docs/workspaces.md>
- Worktrees e `paseo.json`: <https://paseo.sh/docs/worktrees.md>
- Modelo de segurança: <https://paseo.sh/docs/security.md>
