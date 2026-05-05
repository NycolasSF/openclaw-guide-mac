# Quickstart — OpenClaw Mac mini em 10 minutos

> Para a documentação completa (modelo de ameaças, o que o agente pode/não pode acessar, troubleshooting, rollback): ver [README.md](README.md).

## 1. Pré-requisitos

- macOS 14+ (Sonoma ou superior)
- [Docker Desktop](https://docs.docker.com/desktop/install/mac-install/) **ou** [OrbStack](https://orbstack.dev/) **ou** [Colima](https://github.com/abiosoft/colima)
- Homebrew (para `openssl`, opcionalmente `tailscale`, `ollama`)

## 2. Clone o repo

```bash
git clone https://github.com/NycolasSF/openclaw-guide-mac.git
cd openclaw-guide-mac
```

## 3. Rode o instalador

```bash
bash scripts/install.sh
```

O script:
1. Verifica Docker rodando
2. Cria `~/openclaw-data/{config,workspace,backups}` e `~/openclaw/`
3. Copia `docker-compose.yml` hardenado para `~/openclaw/`
4. Gera token novo (32 bytes hex) e cria `.env` com `chmod 600`
5. Cria `openclaw.json` a partir do template, com token sincronizado
6. Cria workspace mínimo (`AGENTS.md`, `USER.md`)
7. `docker compose pull` + `up -d`
8. Aguarda healthcheck

## 4. Adicione suas API keys

```bash
nano ~/openclaw/.env
# Preencher: ANTHROPIC_API_KEY, OPENAI_API_KEY, OPENROUTER_API_KEY
docker compose -f ~/openclaw/docker-compose.yml restart
```

## 5. Acesse a Control UI

```bash
open http://127.0.0.1:18789
```

Autentique com o token (mesmo valor de `OPENCLAW_GATEWAY_TOKEN` em `.env`).

## 6. (Opcional) Trazer persona/sessions de outra instância

Se você tem OpenClaw rodando em outra VPS/host e quer trazer a persona, sessions e memória:

```bash
# No host de origem (ex: VPS Ubuntu)
sudo tar czf /tmp/openclaw-runtime.tgz -C /root .openclaw

# Para o Mac mini
scp <user>@<host>:/tmp/openclaw-runtime.tgz /tmp/

# No Mac mini
docker compose -f ~/openclaw/docker-compose.yml down
rm -rf ~/openclaw-data/config/*
tar xzf /tmp/openclaw-runtime.tgz --strip-components=1 -C ~/openclaw-data/config/

# IMPORTANTE: editar para evitar conflito com a outra instância
nano ~/openclaw-data/config/openclaw.json
#   - gateway.auth.token: COLAR o mesmo valor de OPENCLAW_GATEWAY_TOKEN do .env
#   - gateway.bind: "local"
#   - channels.telegram.enabled: false   (ou criar bot novo)
#   - channels.whatsapp.enabled: false
#   - channels.discord.enabled: false

docker compose -f ~/openclaw/docker-compose.yml up -d
```

⚠️ **Reusar tokens de Telegram/WhatsApp/Discord da outra instância derruba a outra** (long-poll é exclusivo). Crie bot novo no `@BotFather` para o Mac.

## 7. Backup automático (launchd)

```bash
chmod +x scripts/backup.sh
cp scripts/backup.sh ~/openclaw/backup.sh

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
        <key>Hour</key><integer>3</integer>
        <key>Minute</key><integer>0</integer>
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

Backup roda às 03:00 todo dia, com retenção de 14 dias em `~/openclaw-data/backups/`.

## 8. Validar hardening

```bash
# Bind 127.0.0.1 (não 0.0.0.0)
docker port openclaw-gateway

# cap_drop: [ALL]
docker inspect openclaw-gateway --format='{{.HostConfig.CapDrop}}'

# docker.sock NÃO montado
docker inspect openclaw-gateway --format='{{range .Mounts}}{{.Source}}{{"\n"}}{{end}}' | grep -i docker.sock || echo "✅ socket protegido"

# Resource limits
docker stats openclaw-gateway --no-stream
```

## 9. Rollback

```bash
docker compose -f ~/openclaw/docker-compose.yml down
docker rmi openclaw/openclaw:latest
rm -rf ~/openclaw-data ~/openclaw
launchctl unload ~/Library/LaunchAgents/com.openclaw.backup.plist
rm -f ~/Library/LaunchAgents/com.openclaw.backup.plist
```

---

**Próximas leituras:**
- [README.md](README.md) — guia completo (~26 KB, 17 seções)
- [reference/docker-compose.vps-original.yml](reference/docker-compose.vps-original.yml) — compose padrão de VPS comercial **com pontos vermelhos comentados** (didático, não usar em prod)
