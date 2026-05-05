# Configuração do Agent — Persona Claudius

Esta pasta contém os **bootstrap files** da persona usada pelo OpenClaw rodando neste Mac mini. É a config sanitizada da instância de produção (sem tokens, sem secrets).

## O que é a persona

Claudius é uma persona em PT-BR otimizada para atuar como **COO Digital / braço direito** do operador. Foco em estratégia, copy, lançamentos digitais e operação de ferramentas. Tom: direto, seco, proativo, opinativo.

Detalhes em [`workspace/PERSONA.md`](workspace/PERSONA.md).

## Estrutura — workspace/

OpenClaw lê esses arquivos no boot de cada sessão (na ordem definida em `BOOTSTRAP.md`):

| Arquivo | Função | Tamanho |
|---|---|---|
| `PERSONA.md` | Quem é, tom, NUNCA/SEMPRE | ~600 tokens |
| `BOOTSTRAP.md` | Wake protocol — ordem de leitura, regras de ação externa | ~1.2 KB |
| `MEMORY.md` | Fatos duráveis, regras inegociáveis, decisões | cap **3 KB** |
| `USER.md` | Sobre o operador, horários, stack | enxuto |
| `TOOLS.md` | Aliases SSH, paths, devices — específico do setup | livre |

> Versão da persona: **v2 (2026-04-25)** — `SOUL.md` + `IDENTITY.md` consolidados em `PERSONA.md`. `AGENTS.md` e `HEARTBEAT.md` deletados (regras absorvidas por `BOOTSTRAP.md` e config do gateway).

## Como instalar a persona no seu Mac

```bash
# Depois de rodar scripts/install.sh (que cria ~/openclaw-data/workspace/ vazio)
cp -r agent/workspace/* ~/openclaw-data/workspace/

# Reiniciar o gateway pra ele recarregar workspace
docker compose -f ~/openclaw/docker-compose.yml restart
```

A próxima sessão na Control UI já vai responder com a persona Claudius.

## Como customizar para sua realidade

A persona aqui é otimizada para um caso de uso específico (escola de educação contábil). Para adaptar:

1. **`USER.md`** — trocar nome, email, papel profissional, horários, stack — **obrigatório**
2. **`MEMORY.md`** — trocar regras de negócio (produto, preço, regras de copy) pelas suas — **obrigatório**
3. **`PERSONA.md`** — ajustar tom, NUNCA/SEMPRE, role — **opcional**
4. **`BOOTSTRAP.md`** — ajustar regras de ação externa, fontes que devem ser confirmadas — **opcional**
5. **`TOOLS.md`** — preencher com seus SSH hosts, devices, voices — **opcional**

## Configurações de gateway (agents.defaults)

Estas são as configurações de runtime aplicadas no `openclaw.json` para a v2:

```json
"agents": {
  "defaults": {
    "workspace": "/home/node/.openclaw/workspace",
    "model": {
      "primary": "anthropic/claude-sonnet-4-6"
    },
    "contextInjection": "continuation-skip",
    "bootstrapMaxChars": 5000,
    "bootstrapTotalMaxChars": 12000,
    "params": {
      "cacheRetention": "long"
    }
  }
}
```

Detalhes:
- **`bootstrapMaxChars: 5000`** — limite por arquivo individual do workspace
- **`bootstrapTotalMaxChars: 12000`** — limite total agregado (force a disciplina; estimado ~9KB pós-v2)
- **`cacheRetention: "long"`** — TTL 1h em vez de 5min (aumenta cache hit em conversas seguidas)
- **`contextInjection: "continuation-skip"`** — não reinjeta contexto em mensagens de continuação da mesma conversa

## Como atualizar a persona depois

Edite os arquivos em `~/openclaw-data/workspace/` direto e reinicie o gateway:

```bash
nano ~/openclaw-data/workspace/MEMORY.md
docker compose -f ~/openclaw/docker-compose.yml restart
```

A persona não precisa rebuild — é só leitura de arquivos no volume bind-mounted.

## Por que dois caminhos?

- `agent/workspace/` (este repo, **versionado**) — template/snapshot que você pode commitar
- `~/openclaw-data/workspace/` (no Mac, **runtime real**) — onde o OpenClaw lê de fato

Manter os dois em sync é decisão sua. Sugestão: mudanças relevantes vão pro repo via PR; runtime no Mac pode ter ajustes finos transientes.
