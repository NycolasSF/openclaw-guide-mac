# CLAUDE.md — Instruções para Claude Code

> Este arquivo é lido automaticamente por Claude Code quando outro agente clonar este repo num Mac mini novo. Ele contém o caminho mais curto para subir o OpenClaw hardenado.

---

## 1. O que este repo é

Guia + scripts + bootstrap files para instalar **OpenClaw em Mac mini com Docker**, com hardening agressivo (sem `docker.sock`, bind 127.0.0.1 only, cap_drop ALL, resource limits) e a persona **Claudius** (PT-BR, COO Digital) já pré-configurada.

Repo público: https://github.com/NycolasSF/openclaw-guide-mac

---

## 2. Caminho mais curto (TL;DR para Claude Code)

Se o usuário pediu para "instalar OpenClaw neste Mac mini" e estamos dentro deste repo:

```bash
bash scripts/install.sh
```

Se o usuário ainda não clonou:

```bash
git clone https://github.com/NycolasSF/openclaw-guide-mac.git ~/openclaw-guide-mac
cd ~/openclaw-guide-mac
bash scripts/install.sh
```

**Modo totalmente automático** (sem prompts — exige API keys via env):

```bash
NON_INTERACTIVE=1 \
INSTALL_DOCKER=1 \
ENABLE_BACKUP=1 \
ANTHROPIC_API_KEY=sk-ant-xxxxx \
bash scripts/install.sh
```

---

## 3. O que `install.sh` faz (13 passos)

1. Verifica macOS + Homebrew
2. Instala `openssl` se faltar
3. Detecta Docker — se não tiver, oferece `brew install --cask docker` (autoriza com `INSTALL_DOCKER=1`)
4. Cria `~/openclaw-data/{config,workspace,backups}` e `~/openclaw/`
5. Copia `docker-compose.yml` hardenado para `~/openclaw/`
6. Copia `backup.sh` para `~/openclaw/`
7. Gera token gateway novo (32 bytes hex) + cria `.env` com chmod 600
8. Pergunta API keys (Anthropic / OpenAI / OpenRouter) — pode pular com ENV vars
9. Cria `openclaw.json` a partir do template, com token sincronizado
10. Copia persona **Claudius** (5 bootstrap files) para `~/openclaw-data/workspace/`
11. `docker compose pull` + `up -d`
12. Aguarda healthcheck (até 60s)
13. Configura backup launchd 03:00 (opcional, autoriza com `ENABLE_BACKUP=1`)

Roda validação de hardening no final (bind 127.0.0.1, cap_drop ALL, sem docker.sock).

---

## 4. Estrutura do repo

```
openclaw-guide-mac/
├── README.md                                    Guia completo, 17 seções
├── QUICKSTART.md                                Receita 10 min
├── CLAUDE.md                                    Este arquivo
├── docker-compose.yml                           Compose hardenado (subir via install.sh)
├── .env.example                                 Template de variáveis
├── LICENSE                                      MIT
├── .gitignore                                   Bloqueia secrets
│
├── config/
│   └── openclaw.json.example                    Template do gateway sanitizado
│
├── scripts/
│   ├── install.sh                               ⭐ ENTRY POINT
│   └── backup.sh                                Backup diário (instalado em ~/openclaw/)
│
├── agent/
│   ├── README.md                                Como customizar a persona
│   └── workspace/
│       ├── PERSONA.md                           Quem é Claudius, tom, NUNCA/SEMPRE
│       ├── BOOTSTRAP.md                         Wake protocol + regras de ação externa
│       ├── MEMORY.md                            Fatos duráveis, regras de copy (cap 3KB)
│       ├── USER.md                              Sobre o operador
│       └── TOOLS.md                             Notas locais (template)
│
└── reference/
    └── docker-compose.vps-original.yml          Compose padrão VPS comercial com pontos vermelhos comentados (didático, NÃO usar)
```

---

## 5. Resultado esperado após `install.sh`

```
~/openclaw/
├── docker-compose.yml
├── .env                     (chmod 600 — token + API keys)
└── backup.sh

~/openclaw-data/
├── config/
│   └── openclaw.json        (token sincronizado com .env)
├── workspace/
│   ├── PERSONA.md
│   ├── BOOTSTRAP.md
│   ├── MEMORY.md
│   ├── USER.md
│   └── TOOLS.md
├── backups/
└── backup.log

# Container rodando
docker ps  →  openclaw-gateway   Up X seconds (healthy)   127.0.0.1:18789-18790

# Control UI
http://127.0.0.1:18789  →  autenticar com token de ~/openclaw/.env
```

---

## 6. Pós-instalação — o que dizer ao usuário

Após o `install.sh` rodar com sucesso:

1. **Editar `~/openclaw-data/workspace/USER.md`** com nome, email, papel e horários do operador
2. **Editar `~/openclaw-data/workspace/MEMORY.md`** com regras de negócio próprias (substituir o conteúdo de exemplo pelo do operador)
3. **Restart se editou os bootstrap files:** `docker compose -f ~/openclaw/docker-compose.yml restart`
4. **Abrir** `http://127.0.0.1:18789` e autenticar com o token

---

## 7. Troubleshooting (se algo der errado)

### `docker: command not found` mesmo após instalar
- Abrir Docker Desktop manualmente uma vez (precisa de aceite de termos)
- Aguardar ícone na barra de menu virar verde
- Rodar `bash scripts/install.sh` de novo

### `Cannot connect to the Docker daemon`
- Docker Desktop não está rodando — abrir o app
- Ou usar OrbStack: `brew install --cask orbstack && orb start`

### Container sobe mas Control UI dá "token inválido"
- Tokens divergem entre `.env` e `openclaw.json`
- Ver: `grep TOKEN ~/openclaw/.env` vs `grep token ~/openclaw-data/config/openclaw.json`
- Editar para que sejam iguais e: `docker compose -f ~/openclaw/docker-compose.yml restart`

### Persona Claudius não responde / responde genérico
- Verificar bootstrap: `ls ~/openclaw-data/workspace/`
- Restart: `docker compose -f ~/openclaw/docker-compose.yml restart`
- Logs: `docker logs openclaw-gateway --tail 100 | grep -i bootstrap`

### Imagem ARM64 não disponível
- Adicionar no `docker-compose.yml`: `platform: linux/amd64` no service `openclaw-gateway`
- Performance pior em M1/M2 emulado, mas funciona

### Mais troubleshooting
Ver [`README.md`](README.md) §11.

---

## 8. Rollback completo

```bash
docker compose -f ~/openclaw/docker-compose.yml down
docker rmi openclaw/openclaw:latest
rm -rf ~/openclaw-data ~/openclaw
launchctl unload ~/Library/LaunchAgents/com.openclaw.backup.plist 2>/dev/null
rm -f ~/Library/LaunchAgents/com.openclaw.backup.plist
```

---

## 9. O que NÃO fazer (regras para Claude Code)

- ❌ **Nunca** sugerir montar `/var/run/docker.sock` no container — quebra todo o hardening
- ❌ **Nunca** trocar `--bind local` por `--bind lan` no compose sem o usuário pedir explicitamente — expõe na rede
- ❌ **Nunca** remover `cap_drop: ALL` do compose
- ❌ **Nunca** commit `.env`, `openclaw.json`, `*.sqlite`, `paired.json`, `credentials/` (já bloqueado pelo `.gitignore`, mas reforçar)
- ❌ **Nunca** reusar tokens (gateway, Telegram bot, Discord) entre instâncias — cria conflito (long-poll exclusivo, etc)
- ❌ **Nunca** rodar `docker compose down -v` (com `-v`) sem confirmar com o usuário — apagaria volumes anônimos
- ❌ **Nunca** enviar mensagens externas (Telegram, Discord, WhatsApp) pelo agente sem confirmação explícita do operador

---

## 10. Quando precisar editar este repo

Se for fazer melhorias (ex: adicionar suporte a Linux, novo provider de LLM, novo profile de hardening):

1. Trabalhar em branch separado: `git checkout -b feat/<nome>`
2. Testar localmente em Mac mini real ou VM
3. PR pra `main`
4. **Não fazer push direto pra `main` sem testar `bash scripts/install.sh` em ambiente limpo**

---

## 11. Referências cruzadas

- Guia completo: [README.md](README.md)
- Receita rápida: [QUICKSTART.md](QUICKSTART.md)
- Como customizar persona: [agent/README.md](agent/README.md)
- Compose original VPS (didático): [reference/docker-compose.vps-original.yml](reference/docker-compose.vps-original.yml)
- Repo OpenClaw upstream: https://github.com/openclaw/openclaw

---

*Última atualização: 2026-05-05. Mantido junto com o resto do repo — atualizar este arquivo sempre que `install.sh` mudar de comportamento.*
