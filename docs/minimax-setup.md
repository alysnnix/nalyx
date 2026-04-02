# Configurar MiniMax no Claude Code (Ubuntu)

Este guia explica como configurar o wrapper MiniMax para usar o modelo MiniMax-M2.7 no Claude Code via API da MiniMax. Sistema alvo: **Ubuntu** (sem NixOS).

## Arquitetura

O wrapper é um script shell que intercepta chamadas ao `claude` e define variáveis de ambiente para redirecionar a API para a MiniMax:

```
claude --minimax "pergunta"
  └─> default.sh detecta --minimax
      └─> minimax.sh exporta variáveis
          └─> command claude (binary real)
```

## 1. Estrutura dos Arquivos

Crie a seguinte estrutura:

```
~/.local/bin/
└── claude-wrapper/
    ├── default.sh    # Wrapper principal que detecta --minimax
    └── minimax.sh    # Wrapper que seta variáveis do MiniMax
```

## 2. `minimax.sh`

```bash
#!/usr/bin/env bash
# minimax.sh — define variáveis de ambiente para API MiniMax

_claude_minimax() {
    local key_file="$HOME/.config/minimax-api-key"

    if [ ! -f "$key_file" ]; then
        echo "❌ MiniMax API key não encontrada em $key_file"
        echo "   Crie o arquivo com: echo 'sua_chave_aqui' > $key_file"
        return 1
    fi

    local minimax_token
    minimax_token="$(cat "$key_file")"

    (
        export ANTHROPIC_BASE_URL="https://api.minimax.io/anthropic"
        export ANTHROPIC_AUTH_TOKEN="$minimax_token"
        export ANTHROPIC_MODEL="MiniMax-M2.7"
        export ANTHROPIC_SMALL_FAST_MODEL="MiniMax-M2.7"
        command claude "$@"
    )
}
```

## 3. `default.sh` (wrapper principal)

```bash
#!/usr/bin/env bash
# default.sh — detecta flags e despacha para o handler correto

_claude() {
    local minimax=0
    local remaining_args=()

    for arg in "$@"; do
        case "$arg" in
            --minimax) minimax=1 ;;
            *) remaining_args+=("$arg") ;;
        esac
    done

    if (( minimax )); then
        source "$(dirname "$0")/minimax.sh"
        _claude_minimax "${remaining_args[@]}"
    else
        command claude "$@"
    fi
}

_claude "$@"
```

## 4. Instalação

```bash
# 1. Clone ou copie os scripts
mkdir -p ~/.local/bin/claude-wrapper
cp minimax.sh ~/.local/bin/claude-wrapper/
cp default.sh ~/.local/bin/claude-wrapper/

# 2. Torne executáveis
chmod +x ~/.local/bin/claude-wrapper/*.sh

# 3. Adicione ao PATH (coloque no seu .bashrc ou .zshrc)
echo 'export PATH="$HOME/.local/bin/claude-wrapper:$PATH"' >> ~/.bashrc
echo 'alias claude="$HOME/.local/bin/claude-wrapper/default.sh"' >> ~/.bashrc

# 4. Recarregue
source ~/.bashrc

# 5. Coloque sua API key
echo "sua_chave_api_minimax" > ~/.config/minimax-api-key
chmod 600 ~/.config/minimax-api-key
```

## 5. Uso

```bash
# Usar MiniMax
claude --minimax "pergunta aqui"

# Uso normal (sem wrapper)
command claude "pergunta aqui"
```

## Variáveis Exportadas

| Variável | Valor | Para que serve |
|----------|-------|----------------|
| `ANTHROPIC_BASE_URL` | `https://api.minimax.io/anthropic` | Endpoint da API MiniMax |
| `ANTHROPIC_AUTH_TOKEN` | Conteúdo de `~/.config/minimax-api-key` | Autenticação |
| `ANTHROPIC_MODEL` | `MiniMax-M2.7` | Modelo principal |
| `ANTHROPIC_SMALL_FAST_MODEL` | `MiniMax-M2.7` | Modelo rápido |

## Onde Pegar a API Key

1. Crie uma conta em [MiniMax](https://www.minimax.io/)
2. Vá em API Settings / Developer Settings
3. Copie a API key

## Notas

- O arquivo da API key (`~/.config/minimax-api-key`) deve ter permissões `600` para segurança
- O alias `claude` no PATH sobrescreve o comando original — use `command claude` para pular o wrapper
- Funciona com bash e zsh
