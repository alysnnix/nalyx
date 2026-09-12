# Paseo

Daemon self-hosted para agentes de código. Este documento é sobre **operar** o
Paseo nesta config: adicionar projetos, escolher cliente, e expor o daemon num
domínio próprio. Para o porquê de cada decisão de empacotamento, os comentários
em prosa nos arquivos `.nix` citados abaixo são a fonte.

## A regra que explica todo o resto

O daemon executa os agentes **no filesystem da máquina onde ele roda**, e não
sincroniza nada do cliente para o daemon. O `--cwd` de qualquer comando é um
caminho no host do daemon.

Consequência prática: o daemon mora onde os repositórios moram. Nesta config
isso é o WSL. O cliente é sempre remoto, e é só uma janela.

```
Windows                          WSL (nixos-wsl)
  browser ...................... nginx? .... paseo daemon 127.0.0.1:6767
  app desktop --- ssh -W ------------------- ^
  celular ------- tailnet ------- nginx ---- ^
```

## Onde a configuração vive

| Arquivo | O que declara |
|---|---|
| `flake.nix` | o input `paseo`, e o overlay `fixPtyNode` que conserta os pacotes |
| `hosts/wsl/default.nix` | `services.paseo`, o daemon como serviço systemd |
| `home/features/cli/paseo/` | o CLI em todo host, e o app desktop só onde há janela |
| `modules/services/paseo-proxy.nix` | o nginx com TLS para um domínio próprio, desligado por padrão |

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

Já está ligada (`settings.features.webUi.enabled`). Abra:

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

`Settings` → `Add host` → `Direct connection`, com o IP da tailnet e a porta
`6767`. Isso exige o daemon alcançável além do loopback, o que é exatamente o
que a próxima seção resolve, e com TLS.

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
  cloudflareCredentialsFile = config.sops.secrets.paseo_cloudflare_dns.path;
  passwordFile = config.sops.secrets.paseo_password.path;
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
- **`passwordFile`.** Um `EnvironmentFile` com `PASEO_PASSWORD=...`. Assim que o
  daemon fica alcançável pela tailnet, qualquer device dela executa comandos como
  você, então a senha deixa de ser opcional.

### Os três passos que não são Nix

1. **Token do Cloudflare** com permissão de editar DNS da zona, guardado como
   secret SOPS. Sem ele o ACME não emite nada.
2. **Registro A** apontando `paseo.exemplo.dev` para o IP `100.x.y.z` da tailnet.
   DNS público pode apontar para IP privado sem problema: quem não está na
   tailnet simplesmente não alcança.
3. **Entrada no `hosts` do Windows** mapeando o mesmo nome para `127.0.0.1`.
   É isso que faz a URL continuar funcionando com o Tailscale desligado, porque
   o loopback não depende dele.

### Efeito colateral no omp-collab

Ligar o proxy move o `tailscale serve` do omp-collab de `:443` para `:8443`
(`modules.services.ompCollab.servePort`), porque o `tailscaled` segura o bind da
443 no IP da tailnet e o nginx precisa dela. O omp-collab continua funcionando,
só muda de porta na URL.

## Config declarativa: uma escolha, não duas

`services.paseo.settings` reescreve `~/.paseo/config.json` **a cada start** do
serviço. Então qualquer coisa feita em runtime (`paseo daemon set-password`, ou
o app mexendo em provider e MCP) não sobrevive ao próximo restart.

A regra é escolher um lado. Nesta config o lado escolhido é o Nix, então
qualquer ajuste de daemon vai em `services.paseo.settings` no host, não no CLI.

A senha é a exceção, e por um motivo concreto: `settings` vira um JSON no
`/nix/store`, que é legível por qualquer usuário da máquina. Por isso ela entra
por `EnvironmentFile` apontando para um secret do SOPS.

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
apontando para o output do flake do próprio Paseo. Por isso `hosts/wsl` atribui
`package = pkgs.paseo` explicitamente. Sem essa linha, o CLI fica corrigido e o
daemon não, e um `switch` parece não ter efeito nenhum.

**O `Applications/Paseo.AppImage` não é um AppImage.** É o nome que o launcher
do `paseo .` procura. O alvo é um wrapper shell em volta do electron.

**O acesso pelo celular depende do PC ligado.** O nó da tailnet só existe
enquanto a distro WSL estiver rodando.

## Diagnóstico

```bash
systemctl status paseo            # o serviço
paseo daemon status               # versão, listen, home, providers
curl -s localhost:6767/api/health # o daemon responde?
tail -f ~/.paseo/daemon.log       # o log

# o terminal funciona? (isto é o que prova que o pty.node está no lugar)
paseo terminal create --cwd /tmp --json
```

## Referências

- Web UI e proxy reverso: <https://paseo.sh/docs/web-ui.md>
- Conectividade, SSH e Tailscale: <https://paseo.sh/docs/connectivity.md>
- Workspaces: <https://paseo.sh/docs/workspaces.md>
- Worktrees e `paseo.json`: <https://paseo.sh/docs/worktrees.md>
- Modelo de segurança: <https://paseo.sh/docs/security.md>
