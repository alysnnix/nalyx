---
paths:
  - "**/*"
---

# Quality Rules

## CRITICAL: Validação Antes de Commit

```
TODA MUDANÇA DEVE SER VALIDADA ANTES DO COMMIT
```

- **Sem exceções**: Toda alteração deve passar nas verificações
- **Validar primeiro**: Rodar checks antes de commitar
- **Cada commit deve ser funcional**: Sistema deve rebuildar sem erros

## Antes de Cada Commit

```bash
# 1. Formatar código
nix fmt

# 2. Verificar configurações (sem build)
nix flake check --no-build

# 3. Testar rebuild (opcional, mas recomendado)
sudo nixos-rebuild dry-run --flake .#<host>
```

### Checklist de Commit

```
[ ] Código formatado (nix fmt)
[ ] Flake check passa
[ ] Sem imports quebrados
[ ] Sem syntax errors
[ ] Variáveis usadas corretamente
```

## Requisitos por Tipo de Mudança

| Tipo de Mudança | Requisito |
|-----------------|-----------|
| Novo módulo | Verificar imports, testar em dry-run |
| Mudança em host | Testar rebuild do host específico |
| Mudança em vars.nix | Verificar todos os hosts |
| Novo pacote | Verificar se existe no nixpkgs |
| Driver/Hardware | Testar em ambiente real |

## O Que Verificar

### Módulos Nix

```
[ ] Imports corretos (caminhos existem)
[ ] Atributos bem formados
[ ] Variáveis definidas usadas
[ ] Sem código morto (deadnix)
[ ] Formatação correta (nixfmt)
```

### Configurações de Programa

```
[ ] Pacote existe no nixpkgs
[ ] Configuração válida para o programa
[ ] Caminhos de arquivo corretos
[ ] Permissões adequadas
```

## Práticas Proibidas

```nix
# NUNCA commitar:

# Imports de arquivos inexistentes
imports = [ ./nao-existe.nix ];

# Variáveis não definidas
programs.${undefined}.enable = true;

# Código comentado sem propósito
# imports = [ ./velho ]; # TODO: remover

# hardware-configuration.nix editado manualmente
```

## Se o Check Falhar

1. **NÃO** commitar
2. **NÃO** usar --no-verify
3. **CORRIGIR** o problema
4. **VERIFICAR** novamente
5. **ENTÃO** commitar

## Resumo

```
FLAKE CHECK FALHOU = NÃO COMMITAR
FORMATO ERRADO = NÃO COMMITAR
REBUILD FALHOU = NÃO COMMITAR
```
