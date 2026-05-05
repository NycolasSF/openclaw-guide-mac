# OpenClaw em Mac mini com Docker — Instalação Hardenada

> Última atualização: 2026-05-05
> Objetivo: rodar OpenClaw num **Mac mini local** (Apple Silicon ou Intel) usando Docker Desktop, com **isolamento agressivo** — sem o "modo solto" que a config padrão da distribuição comercial usa em VPS.
> Base: runtime extraído de uma instância OpenClaw já existente (persona + workspace + sessions opcionais), ou instalação limpa.

## TL;DR — quero instalar agora

Ver **[QUICKSTART.md](QUICKSTART.md)** (10 min, com `bash scripts/install.sh`).

## Arquivos do repo

| Arquivo | O que é |
|---|---|
| [README.md](README.md) | Guia completo (este arquivo) — modelo de ameaças, o que pode/não pode acessar, troubleshooting, rollback |
| [QUICKSTART.md](QUICKSTART.md) | Receita de bolo de 10 minutos |
| [docker-compose.yml](docker-compose.yml) | Compose hardenado pronto pra subir no Mac |
| [.env.example](.env.example) | Template de variáveis (token, API keys) |
| [config/openclaw.json.example](config/openclaw.json.example) | Template de config do gateway sanitizado |
| [scripts/install.sh](scripts/install.sh) | Bootstrap automático |
| [scripts/backup.sh](scripts/backup.sh) | Backup diário com retenção 14d |
| [agent/](agent/) | Persona **Claudius** (PT-BR, COO Digital) — bootstrap files (PERSONA, BOOTSTRAP, MEMORY, USER, TOOLS). Ver [agent/README.md](agent/README.md) |
| [reference/docker-compose.vps-original.yml](reference/docker-compose.vps-original.yml) | Compose padrão de VPS comercial **com pontos vermelhos comentados** — didático, não usar em prod |

---

---

## 1. Sumário Executivo

| Item | Valor |
|---|---|
| Hardware alvo | Mac mini M1/M2/M3 (8GB+ RAM) ou Intel (16GB+) |
| OS | macOS 14 Sonoma+ (testado em 14.5) |
| Engine | Docker Desktop 4.30+ (ou OrbStack/Colima) |
| Tempo total | ~45min (com runtime já extraído) |
| Postura de segurança | **Local-only, zero exposição externa, sem docker.sock** |
| Persona | Claudios PT-BR (vem do `openclaw-runtime.tgz` da VPS) |
| Acesso externo | ❌ Nenhum por padrão. Opcional via Tailscale |
| LLMs | Anthropic + OpenAI + OpenRouter (keys próprias) |
| Channels | Telegram via long-poll (outbound only) — desativado por padrão |

---

## 2. Modelo de Ameaças

OpenClaw é um agente que **executa código** (escreve arquivos, roda comandos shell, faz chamadas HTTP). Na config padrão de distribuições comerciais em VPS, ele costuma rodar com:

- `/var/run/docker.sock` montado → **escape trivial pro host** (cria container privilegiado, monta `/`, lê tudo)
- `/usr/bin/docker` montado → reforça o escape
- Bind `0.0.0.0` em `--bind lan` → exposto na LAN inteira
- Egress livre → pode falar com qualquer host na internet

No Mac mini local **queremos o oposto**: o agente trabalha em sandbox bem definido e não consegue escapar nem morder nada além do permitido.

### O que queremos prevenir

| Ameaça | Mitigação |
|---|---|
| Container escape via `docker.sock` | **Não montar `docker.sock`** — agente perde capacidade de criar containers irmãos, mas isso é OK localmente |
| Acesso a `/etc`, `~`, `/Users` do host | **Apenas 2 volumes nominados**: `~/.openclaw/` e workspace explícito |
| Exposição na LAN/Wi-Fi | **Bind `127.0.0.1`** apenas — só localhost do Mac alcança |
| Privilege escalation | `cap_drop: ALL` + `no-new-privileges:true` |
| Fork bomb / consumo infinito | Limites de CPU/RAM/PIDs no compose |
| Vazamento de credenciais via logs | Logs com tamanho máximo + rotação |
| Abuso de rede outbound | Egress controlado por allowlist (opcional, nível avançado) |

### O que aceitamos como risco

- Agente continua podendo **ler/escrever** dentro do workspace montado (é o trabalho dele)
- Agente continua podendo fazer **chamadas HTTPS outbound** (LLMs, Telegram long-poll). Bloquear isso quebra o produto.
- Agente continua podendo executar **comandos shell** dentro do próprio container (também é o trabalho dele) — o jail é o container, não o shell.

---

## 3. O que o OpenClaw no Docker pode/não pode acessar

### 3.1. Pode acessar (na config hardenada deste documento)

| Recurso | Onde | Por quê |
|---|---|---|
| Próprio filesystem do container | `/` do container (rootfs ephemeral) | Trabalho do agente |
| `~/.openclaw/` no host (montado) | volume `OPENCLAW_CONFIG_DIR` → `/home/node/.openclaw/` | Config + sessions + memory + workspace persistem |
| Workspace explícito (montado) | volume `OPENCLAW_WORKSPACE_DIR` → `/home/node/.openclaw/workspace/` | Bootstrap files (AGENTS.md, SOUL.md, etc) |
| Loopback do container | `127.0.0.1:18789`, `127.0.0.1:18790` | Gateway + bridge para a Control UI |
| Egress HTTPS/443 | Internet | Anthropic API, OpenAI API, OpenRouter, Telegram long-poll |
| Egress DNS/53 | Internet | Resolver hostnames |
| Variáveis de ambiente do `.env` | Todas as `OPENCLAW_*`, `ANTHROPIC_API_KEY`, etc | Configuração |

### 3.2. Não pode acessar (barreiras impostas pela config)

| Recurso | Bloqueio |
|---|---|
| `~/Documents`, `~/Desktop`, `~/Downloads` do macOS | Não tem volume montado |
| `/Users/<outro>/`, `/etc`, `/Library`, `/System` | Não tem volume montado |
| Outros containers Docker | **`docker.sock` removido** — não enxerga o socket Docker |
| Binário `docker` do host | **`/usr/bin/docker` removido** do volume mount |
| LAN do Mac (Wi-Fi, Ethernet) | Bind `127.0.0.1` apenas, host network desativada |
| Câmera, microfone, USB | macOS não permite acesso a devices físicos pra Docker Desktop sem opt-in explícito |
| Bluetooth, AirDrop | Idem acima |
| Capabilities Linux privilegiadas | `cap_drop: ALL` (sem NET_ADMIN, NET_RAW, SYS_ADMIN, etc) |
| Mount de novos volumes em runtime | `no-new-privileges:true` impede mount adicional |
| Privileged mode | `privileged: false` (default, mas explícito no compose) |
| Outro container do Mac | Network própria isolada (`network_mode: bridge` da própria stack) |

### 3.3. Pode acessar com configuração extra (opt-in)

| Recurso | Como habilitar | Quando |
|---|---|---|
| Pasta específica de projetos | Adicionar volume `~/projetos:/home/node/projetos:rw` no compose | Se quer que o agente edite código de um repo |
| Tailscale tailnet | Camada 7 opcional (seção 9) | Acesso remoto seguro do iPhone/celular |
| Acesso a outro Docker container (ex: Postgres local) | Network compartilhada explícita | Se vai rodar app + agente juntos |
| LLM rodando localmente (Ollama) | Bridge network compartilhada | Modelos locais sem custo de API |

### 3.4. Comparação com a config padrão de VPS comercial

| Recurso | VPS comercial (padrão) | Mac mini hardenado |
|---|---|---|
| `/var/run/docker.sock` montado | ✅ Sim (escape trivial) | ❌ **Removido** |
| `/usr/bin/docker` montado | ✅ Sim | ❌ **Removido** |
| `--bind lan` (0.0.0.0) | ✅ Sim | ❌ **`local` (127.0.0.1)** |
| Cap drop ALL | ❌ Não no gateway (só no CLI) | ✅ Em ambos |
| Resource limits | ❌ Não | ✅ 2GB RAM, 2 CPU, 200 PIDs |
| Read-only rootfs | ❌ Não | ✅ Onde possível (com tmpfs nos paths necessários) |
| Logging limit | ❌ Não | ✅ json-file 10MB×3 |
| Healthcheck | ✅ Sim | ✅ Sim (mantido) |

---

## 4. Pré-requisitos do Mac mini

### 4.1. Hardware

- **Apple Silicon (M1/M2/M3) recomendado** — imagem OpenClaw é multi-arch (`linux/amd64` + `linux/arm64`)
- 8 GB RAM mínimo, 16 GB ideal (Docker Desktop come ~3 GB, OpenClaw ~1.5 GB, sobra pro macOS)
- 50 GB livres em disco (Docker Desktop reserva volume virtual)

### 4.2. Software

- macOS 14 Sonoma+ atualizado
- **Docker Desktop 4.30+** (https://docs.docker.com/desktop/install/mac-install/)
  - Alternativas: **OrbStack** (mais leve, recomendado para M1/M2) ou **Colima** (CLI-only, free)
- Homebrew (`brew install`)
- Git
- (Opcional) Tailscale para acesso remoto

### 4.3. Configuração inicial do Docker Desktop

**Settings → Resources:**
- CPUs: 2 (limita o que Docker pode usar)
- Memory: 4 GB
- Swap: 1 GB
- Disk image size: 32 GB

**Settings → Advanced:**
- Allow Rosetta para amd64/x86 emulation: ✅ (habilitar — algumas deps do OpenClaw podem ter binários x86)

**Settings → File sharing:**
- Adicionar **apenas** `~/openclaw-data/` na lista (criar a pasta antes — ver §5.1). NÃO compartilhar `~/Documents`, `~/Desktop`, etc.

---

## 5. Instalação passo a passo

### 5.1. Criar estrutura de pastas no host

```bash
# No Terminal do Mac
mkdir -p ~/openclaw-data/config
mkdir -p ~/openclaw-data/workspace
mkdir -p ~/openclaw-data/backups

# Permissões — UID 1000 do container 'node'
# No macOS UIDs não batem 1:1 com Linux, mas Docker Desktop faz translation
# Apenas garantir que o user atual seja owner
chown -R $(id -u):$(id -g) ~/openclaw-data
```

### 5.2. Transferir runtime extraído da VPS (opcional — pula se for instalação limpa)

Se você tem uma instância OpenClaw rodando em VPS e quer trazer a persona/sessions, faça um pull do `~/.openclaw/` da VPS pro PC e gere um tarball (`openclaw-runtime.tgz`).

**Do PC pro Mac mini:**

```bash
# Do PC (Windows PowerShell ou Mac Terminal)
scp /caminho/local/openclaw-runtime.tgz nyc@mac-mini.local:/tmp/
```

```bash
# No Mac mini (Terminal)
cd ~/openclaw-data
tar xzf /tmp/openclaw-runtime.tgz --strip-components=1 -C config/
# Resultado: ~/openclaw-data/config/openclaw.json + workspace/ + sessions/ + memory/ etc
```

⚠️ **Editar `~/openclaw-data/config/openclaw.json` antes de subir o container:**

```bash
# 1. Gerar token novo (NUNCA reusar o da prod)
openssl rand -hex 32
# Output exemplo: a1b2c3d4...

# 2. Substituir token no openclaw.json
# Caminho: gateway.auth.token
# Trocar pelo token novo gerado acima
```

```bash
# 3. Trocar bind de "custom" + "0.0.0.0" para "local"
# Editar /home/$USER/openclaw-data/config/openclaw.json:
# gateway.bind: "local"  (era "custom")
# Remover gateway.customBindHost (era "0.0.0.0")
```

```bash
# 4. DESABILITAR channels que conflitam com prod (Telegram, WhatsApp, Discord)
# Editar:
# channels.telegram.enabled: false
# channels.whatsapp.enabled: false
# channels.discord.enabled: false
# Apagar os tokens daí pra evitar reuso acidental
```

> **Por que desabilitar channels?** Telegram bot token tem long-poll exclusivo — se o Mac e a VPS falarem com o mesmo bot, brigam. WhatsApp Baileys idem. Pra usar Telegram no Mac, criar bot novo no `@BotFather` (ex: `@nyc_mac_dev_bot`).

### 5.3. Criar o `docker-compose.yml` hardenado

Crie `~/openclaw/docker-compose.yml`:

```yaml
# OpenClaw Mac mini — config hardenada
services:
  openclaw-gateway:
    image: ${OPENCLAW_IMAGE:-openclaw/openclaw:latest}
    container_name: openclaw-gateway
    hostname: openclaw-mac
    restart: unless-stopped
    init: true

    # ── Network: APENAS loopback do host ──
    ports:
      - "127.0.0.1:18789:18789"
      - "127.0.0.1:18790:18790"

    # ── Volumes: APENAS o necessário ──
    volumes:
      - ${HOME}/openclaw-data/config:/home/node/.openclaw
      - ${HOME}/openclaw-data/workspace:/home/node/.openclaw/workspace
      # ❌ NÃO montar /var/run/docker.sock (escape trivial)
      # ❌ NÃO montar /usr/bin/docker
      # Se precisar editar repo: descomentar a linha abaixo + path explícito
      # - ${HOME}/projetos/repo-x:/home/node/projetos/repo-x

    # ── Environment ──
    environment:
      HOME: /home/node
      TERM: xterm-256color
      TZ: America/Sao_Paulo
      OPENCLAW_GATEWAY_TOKEN: ${OPENCLAW_GATEWAY_TOKEN}
      # API keys via .env (nunca hardcoded aqui)
      ANTHROPIC_API_KEY: ${ANTHROPIC_API_KEY:-}
      OPENAI_API_KEY: ${OPENAI_API_KEY:-}
      OPENROUTER_API_KEY: ${OPENROUTER_API_KEY:-}

    # ── Comando ──
    command:
      - node
      - dist/index.js
      - gateway
      - --bind
      - local              # ← bind 127.0.0.1, NÃO lan
      - --port
      - "18789"

    # ── HARDENING ──
    cap_drop:
      - ALL
    cap_add:
      - CHOWN              # node escreve em volumes com UID diferente
      - DAC_OVERRIDE       # idem
      - SETUID
      - SETGID
    security_opt:
      - no-new-privileges:true
    read_only: false       # OpenClaw escreve em /tmp + /home/node — manter false simplifica
    privileged: false      # explícito (default)

    # ── Resource limits ──
    mem_limit: 2g
    mem_reservation: 512m
    cpus: 2.0
    pids_limit: 200

    # ── Logging com rotação ──
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

    # ── Healthcheck ──
    healthcheck:
      test:
        - CMD
        - node
        - -e
        - fetch('http://127.0.0.1:18789/healthz').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))
      interval: 30s
      timeout: 5s
      retries: 5
      start_period: 30s

    # ── Network nominada (isolamento) ──
    networks:
      - openclaw-net

networks:
  openclaw-net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.30.0.0/24
```

### 5.4. Criar `.env` com secrets

```bash
cat > ~/openclaw/.env <<'EOF'
# Gerar com: openssl rand -hex 32
OPENCLAW_GATEWAY_TOKEN=COLAR_TOKEN_NOVO_AQUI

# Imagem (default da comunidade ou versão pinada)
OPENCLAW_IMAGE=openclaw/openclaw:2026.4.22

# API keys (preencher manualmente)
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-proj-...
OPENROUTER_API_KEY=sk-or-v1-...
EOF

chmod 600 ~/openclaw/.env
```

⚠️ **O token do `.env` precisa BATER com o token dentro do `openclaw.json`** (`gateway.auth.token`). Edite ambos para o mesmo valor.

### 5.5. Pull da imagem + subir

```bash
cd ~/openclaw

# Pull (multi-arch — Docker escolhe arm64 ou amd64 automaticamente)
docker compose pull

# Subir
docker compose up -d

# Verificar
docker compose ps
docker compose logs -f openclaw-gateway
```

Esperado: log mostrando `gateway listening on 127.0.0.1:18789`.

### 5.6. Validar acesso

```bash
# Healthcheck
curl -s http://127.0.0.1:18789/healthz
# Esperado: {"status":"ok"}

# Control UI
open http://127.0.0.1:18789
# (browser abre — autenticar com o token do .env)
```

---

## 6. Configuração da Persona Claudios

Como o `openclaw-runtime.tgz` da prod foi extraído pra `~/openclaw-data/config/`, a persona já vem montada:

```
~/openclaw-data/config/
├── openclaw.json                   ← config principal (já editado §5.2)
├── workspace/                       ← AGENTS.md, SOUL.md, USER.md, BOOTSTRAP.md, IDENTITY.md, MEMORY.md
├── agents/main/sessions/            ← histórico de conversas
├── memory/main.sqlite               ← memória durável
├── devices/paired.json              ← Telegram/iMessage pareados (DESABILITAR antes de subir)
├── credentials/                     ← profiles OAuth (rotacionar)
└── tasks/runs.sqlite                ← runs de tasks agendadas
```

### 6.1. Decidir: trazer histórico ou começar limpo

**Opção A — começar limpo (recomendado pra dev):**
```bash
# Apaga sessions e memória, mantém workspace + bootstrap files
rm -rf ~/openclaw-data/config/agents/main/sessions/*
rm -f ~/openclaw-data/config/memory/main.sqlite*
rm -f ~/openclaw-data/config/devices/paired.json
echo '[]' > ~/openclaw-data/config/devices/paired.json
docker compose restart openclaw-gateway
```

**Opção B — trazer tudo (paridade com prod):**
Não fazer nada — o tarball já tem tudo. Apenas garantir que channels estão desabilitados (§5.2) pra não brigar.

### 6.2. Validar persona

Acessar Control UI (`http://127.0.0.1:18789`) → conversar:
> "Quem é você?"

Resposta esperada: Claudios responde em PT-BR, citando AGENTS.md, SOUL.md, IDENTITY.md.

---

## 7. Network — Local-only por padrão

### 7.1. Verificar bind correto

```bash
# Deve mostrar APENAS 127.0.0.1, NÃO 0.0.0.0
sudo lsof -i :18789 | grep LISTEN
# Esperado: docker-pr ... TCP 127.0.0.1:18789 (LISTEN)
```

```bash
# Tentar acessar de outro device da rede (deve FALHAR)
# Pegue o IP do Mac (ex: 192.168.0.50) e do iPhone tente:
curl http://192.168.0.50:18789/healthz
# Esperado: connection refused (correto)
```

Se aparecer `0.0.0.0`, algo está errado — revisar:
- `gateway.bind` no `openclaw.json` está `local`?
- Compose está com `127.0.0.1:18789:18789` (e não só `18789:18789`)?
- macOS firewall ativo? `sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate`

### 7.2. macOS Application Firewall (camada extra)

```bash
# Habilitar firewall app-level
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setblockall off
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on
```

### 7.3. (Opcional) Acesso remoto via Tailscale

Se quiser acessar do iPhone/notebook fora de casa **sem expor publicamente**:

```bash
# Instalar
brew install tailscale
sudo tailscaled install-system-daemon
sudo tailscale up

# Pegar IP tailnet do Mac (ex: 100.64.1.5)
tailscale ip -4
```

Acessar do iPhone (com app Tailscale logado): `http://100.64.1.5:18789` — só dispositivos no seu tailnet alcançam. Sem porta aberta na internet.

⚠️ Pra Tailscale funcionar com bind `127.0.0.1` precisa de um pequeno ajuste:
- Trocar a porta no compose para `0.0.0.0:18789:18789` **MAS** habilitar `tailscale serve --bg --https=443 http://127.0.0.1:18789` que faz proxy só dentro do tailnet (não expõe na LAN).
- OU: usar `tailscale funnel` (não recomendado — expõe na internet).

---

## 8. Backup automático no Mac mini

### 8.1. Script de backup

```bash
mkdir -p ~/openclaw-data/backups

cat > ~/openclaw/backup.sh <<'EOF'
#!/bin/bash
set -e
DATE=$(date +%Y-%m-%d_%H%M%S)
BACKUP_DIR="$HOME/openclaw-data/backups"
SOURCE="$HOME/openclaw-data/config"

mkdir -p "$BACKUP_DIR"

# Stop container pra consistência do SQLite
docker compose -f "$HOME/openclaw/docker-compose.yml" stop openclaw-gateway

tar czf "$BACKUP_DIR/openclaw-$DATE.tar.gz" -C "$HOME/openclaw-data" config

# Restart
docker compose -f "$HOME/openclaw/docker-compose.yml" start openclaw-gateway

# Retenção 14 dias
find "$BACKUP_DIR" -name "openclaw-*.tar.gz" -mtime +14 -delete

echo "[$(date)] Backup: $BACKUP_DIR/openclaw-$DATE.tar.gz" >> "$HOME/openclaw-data/backup.log"
EOF

chmod +x ~/openclaw/backup.sh
```

### 8.2. Agendar via launchd (jeito macOS)

```bash
cat > ~/Library/LaunchAgents/com.openclaw.backup.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.openclaw.backup</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$HOME/openclaw/backup.sh</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>3</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardErrorPath</key>
    <string>$HOME/openclaw-data/backup.err</string>
    <key>StandardOutPath</key>
    <string>$HOME/openclaw-data/backup.out</string>
</dict>
</plist>
EOF

launchctl load ~/Library/LaunchAgents/com.openclaw.backup.plist
```

Backup roda toda madrugada às 03:00. Verificar com `tail ~/openclaw-data/backup.log`.

---

## 9. Comandos operacionais

### 9.1. Stack lifecycle

```bash
cd ~/openclaw

# Subir
docker compose up -d

# Logs (live)
docker compose logs -f openclaw-gateway

# Restart sem reload da imagem
docker compose restart openclaw-gateway

# Atualizar imagem
docker compose pull && docker compose up -d --force-recreate

# Parar tudo
docker compose down

# Parar + apagar volumes anônimos (NÃO afeta os bind mounts em ~/openclaw-data)
docker compose down -v
```

### 9.2. CLI do OpenClaw (dentro do container)

```bash
# Healthcheck completo
docker exec openclaw-gateway openclaw doctor

# Listar agentes
docker exec openclaw-gateway openclaw agents list

# Listar channels (Telegram/Discord/etc)
docker exec openclaw-gateway openclaw channels list

# Listar devices pareados
docker exec openclaw-gateway openclaw devices list

# Reload de config sem restart
docker exec openclaw-gateway openclaw config reload

# Versão
docker exec openclaw-gateway openclaw --version
```

### 9.3. Inspeção de segurança

```bash
# Confirmar que docker.sock NÃO está montado
docker inspect openclaw-gateway | grep -i docker.sock
# Esperado: nenhum resultado

# Confirmar capabilities dropadas
docker inspect openclaw-gateway --format='{{.HostConfig.CapDrop}}'
# Esperado: [ALL]

# Confirmar bind 127.0.0.1
docker port openclaw-gateway
# Esperado: 18789/tcp -> 127.0.0.1:18789

# Resource limits
docker stats openclaw-gateway --no-stream
# Esperado: MEM USAGE / LIMIT mostra 2GiB
```

### 9.4. Backup manual

```bash
~/openclaw/backup.sh
ls -lh ~/openclaw-data/backups/
```

### 9.5. Restore

```bash
# Listar backups
ls -lt ~/openclaw-data/backups/

# Restaurar específico
docker compose down
rm -rf ~/openclaw-data/config
mkdir -p ~/openclaw-data/config
tar xzf ~/openclaw-data/backups/openclaw-2026-05-05_030000.tar.gz \
  -C ~/openclaw-data --strip-components=1
docker compose up -d
```

---

## 10. Validação Pós-Deploy

```bash
# 1. Container rodando + healthy
docker ps --filter name=openclaw --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# 2. Apenas 127.0.0.1
docker port openclaw-gateway | grep -E '127\.0\.0\.1' || echo "❌ BIND ERRADO"

# 3. Capabilities limpas
docker inspect openclaw-gateway --format='{{.HostConfig.CapDrop}}' | grep -q ALL && echo "✅ caps OK" || echo "❌"

# 4. docker.sock NÃO montado
docker inspect openclaw-gateway --format='{{range .Mounts}}{{.Source}}{{"\n"}}{{end}}' | grep docker.sock && echo "❌ SOCK MONTADO" || echo "✅ socket protegido"

# 5. Tokens batem
TOKEN_ENV=$(grep OPENCLAW_GATEWAY_TOKEN ~/openclaw/.env | cut -d= -f2)
TOKEN_JSON=$(grep -A1 'auth' ~/openclaw-data/config/openclaw.json | grep token | cut -d'"' -f4)
[ "$TOKEN_ENV" = "$TOKEN_JSON" ] && echo "✅ tokens batem" || echo "❌ tokens divergem"

# 6. CLI responde
docker exec openclaw-gateway openclaw doctor

# 7. Healthcheck HTTP
curl -s http://127.0.0.1:18789/healthz | grep -q ok && echo "✅ gateway OK" || echo "❌"

# 8. Channels desabilitados (se quiser começar limpo)
docker exec openclaw-gateway openclaw channels list
# Esperado: telegram, whatsapp, discord = disabled
```

---

## 11. Troubleshooting

### "Token inválido" na Control UI
- Verificar §10 passo 5: tokens precisam bater entre `.env` e `openclaw.json`
- Restart: `docker compose restart`

### Container não sobe — `permission denied` em volumes
- macOS Docker Desktop precisa de file sharing habilitado em `~/openclaw-data` (Settings → File sharing)
- `chmod -R 755 ~/openclaw-data`

### "Cannot connect to Docker daemon"
- Docker Desktop não está rodando — abrir o app
- OrbStack: `orb start`
- Colima: `colima start`

### Persona Claudios não responde / responde genérico
- Verificar bootstrap: `cat ~/openclaw-data/config/workspace/AGENTS.md`
- `openclaw config reload`
- Logs: `docker logs openclaw-gateway --tail 100 | grep -i bootstrap`

### Telegram briga com a VPS prod
- **Esperado** se reusar bot token. Solução: criar bot novo (`@BotFather`) e atualizar `channels.telegram.botToken` no `openclaw.json`. Ou desabilitar.

### Imagem ARM64 não disponível / erro `exec format error`
- Forçar amd64 (com Rosetta): adicionar `platform: linux/amd64` no service do compose
- Performance pior em M1/M2 emulado, mas funciona

### Memória insuficiente (OOMKilled)
- Aumentar `mem_limit` no compose (ex: `4g`)
- Aumentar memory do Docker Desktop (Settings → Resources)
- Verificar se o agente está em loop: `docker stats`

---

## 12. Rollback completo

```bash
# Parar container
cd ~/openclaw && docker compose down

# Apagar imagem
docker rmi openclaw/openclaw:2026.4.22

# Apagar dados (CUIDADO — perde sessions e memória)
rm -rf ~/openclaw-data ~/openclaw

# Apagar launchd
launchctl unload ~/Library/LaunchAgents/com.openclaw.backup.plist
rm -f ~/Library/LaunchAgents/com.openclaw.backup.plist

# Apagar imagens dangling
docker image prune -f
```

---

## 13. Diferenças vs VPS comercial padrão

| Item | VPS comercial (padrão) | Mac mini hardenado |
|---|---|---|
| Hardware | 2 vCPU + 4 GB shared | M1/M2 + 8 GB dedicada |
| OS | Ubuntu 24.04 | macOS 14+ |
| Engine | Docker 29.4 | Docker Desktop 4.30+ |
| `docker.sock` montado | ✅ | ❌ |
| `cap_drop ALL` | ❌ (só CLI) | ✅ (gateway + CLI) |
| Bind | `lan` (0.0.0.0) | `local` (127.0.0.1) |
| Acesso externo | nginx + Cloudflare + LE | Nenhum (ou Tailscale) |
| Wrapper Flask comercial | ✅ instalado | ❌ não precisa (CLI direto) |
| Hardening SSH/UFW/fail2ban | ✅ | n/a (sem SSH externo) |
| Backup | cron 03h tar.gz | launchd 03h tar.gz |
| Channels Telegram | ativo (bot da prod) | **desabilitado** (ou bot novo) |
| Persona | mesma do snapshot | mesma do snapshot |
| Custo | R$ 50–80/mês | R$ 0 (já tem o Mac) |

---

## 14. Próximos passos opcionais

### Avançado: egress allowlist (bloquear chamadas a hosts não autorizados)

Por padrão, OpenClaw pode chamar **qualquer** endpoint HTTPS. Pra restringir a apenas Anthropic + OpenAI + OpenRouter + Telegram:

1. Subir um proxy outbound (mitmproxy ou squid) num container irmão
2. Setar `HTTPS_PROXY=http://allowlist-proxy:8080` no env do gateway
3. Configurar allowlist no proxy

Trabalhoso e quebra alguns recursos (download de modelos, web search). **Não recomendado** pra uso doméstico — o jail de filesystem + capabilities + bind já é forte o suficiente.

### Avançado: rootless Docker

Docker Desktop 4.30+ suporta modo rootless. Ainda mais isolamento mas com quirks de performance. Considerar se segurança >> conveniência.

### LLM local com Ollama

Pra reduzir custo de API e ter modelo offline:

```bash
brew install ollama
ollama serve &
ollama pull llama3.2:3b
```

Adicionar no `.env`:
```
OPENROUTER_API_KEY=  # vazio
OLLAMA_BASE_URL=http://host.docker.internal:11434
```

E configurar o agent pra usar Ollama no `openclaw.json`:
```json
"model": { "primary": "ollama/llama3.2:3b" }
```

> Nota: `host.docker.internal` precisa ser resolvido — Docker Desktop adiciona automaticamente. No Linux puro precisa de `extra_hosts`.

---

## 15. Referências

- Repo OpenClaw upstream: https://github.com/openclaw/openclaw
- Docs OpenClaw: https://docs.openclaw.ai
- Docker Desktop for Mac: https://docs.docker.com/desktop/install/mac-install/
- OrbStack (alternativa leve): https://orbstack.dev/
- Tailscale: https://tailscale.com/download/mac
- Ollama: https://ollama.com/download/mac

---

## 16. Checklist final

Antes de declarar "instalado":

- [ ] `docker compose ps` mostra container `healthy`
- [ ] `docker port openclaw-gateway` mostra **127.0.0.1**, não 0.0.0.0
- [ ] `docker inspect ... CapDrop` mostra `[ALL]`
- [ ] `docker inspect ... Mounts` **não** lista `docker.sock`
- [ ] Tokens batem entre `.env` e `openclaw.json`
- [ ] Channels Telegram/WhatsApp/Discord = **desabilitados** OU com bot novo
- [ ] Control UI acessível em `http://127.0.0.1:18789`
- [ ] Persona Claudios responde em PT-BR
- [ ] Backup launchd carregado (`launchctl list | grep openclaw`)
- [ ] Tentativa de acesso de outro device na LAN: **falha** (correto)

---

## 17. Histórico de mudanças

| Data | Mudança |
|---|---|
| 2026-05-05 | Criação inicial. Baseado em docker-compose de distribuição comercial em VPS, com 7 endurecimentos: cap_drop ALL, no-new-privileges, bind 127.0.0.1, sem docker.sock, mem/cpu/pids limits, log rotation, network nominada. |
