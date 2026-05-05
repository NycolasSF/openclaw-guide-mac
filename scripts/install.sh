#!/usr/bin/env bash
# OpenClaw Mac mini — bootstrap automatizado
#
# Uso:
#   bash install.sh                 # interativo (pergunta API keys)
#   NON_INTERACTIVE=1 bash install.sh   # pula prompts (.env fica com keys vazias)
#
# Variáveis ENV opcionais (preenchem o .env automaticamente, pulam prompt):
#   ANTHROPIC_API_KEY, OPENAI_API_KEY, OPENROUTER_API_KEY
#   INSTALL_DOCKER=1                # autoriza brew install --cask docker se faltar
#   ENABLE_BACKUP=1                 # configura backup launchd 03h auto

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
ok()   { echo -e "${GREEN}✅ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠  $*${NC}"; }
err()  { echo -e "${RED}❌ $*${NC}" >&2; }

NON_INTERACTIVE="${NON_INTERACTIVE:-0}"
INSTALL_DOCKER="${INSTALL_DOCKER:-0}"
ENABLE_BACKUP="${ENABLE_BACKUP:-0}"

ask() {
  local prompt="$1" default="${2:-}" reply
  if [[ "$NON_INTERACTIVE" == "1" ]]; then
    echo "$default"
    return
  fi
  read -r -p "$prompt" reply
  echo "${reply:-$default}"
}

# ─────────────────────────────────────────────────────────
# 1. Pre-flight: macOS + brew + openssl
# ─────────────────────────────────────────────────────────
log "Verificando pré-requisitos..."

if [[ "$(uname -s)" != "Darwin" ]]; then
  err "Este script é para macOS. Detectado: $(uname -s)"
  exit 1
fi

if ! command -v brew &>/dev/null; then
  err "Homebrew não encontrado. Instale primeiro:"
  echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  exit 1
fi

if ! command -v openssl &>/dev/null; then
  log "Instalando openssl via brew..."
  brew install openssl
fi

# ─────────────────────────────────────────────────────────
# 2. Docker — instalar se faltar (autoriza ou pergunta)
# ─────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
  warn "Docker não encontrado."
  if [[ "$INSTALL_DOCKER" == "1" ]]; then
    INSTALL_REPLY="y"
  else
    INSTALL_REPLY=$(ask "Instalar Docker Desktop via brew --cask? [Y/n] " "y")
  fi

  if [[ "${INSTALL_REPLY,,}" =~ ^(y|s|sim|yes|)$ ]]; then
    log "Instalando Docker Desktop (vai pedir senha sudo do macOS)..."
    brew install --cask docker
    ok "Docker Desktop instalado"
    warn "Abra o Docker Desktop manualmente UMA vez para concluir setup, depois rode este script de novo."
    open -a Docker || true
    exit 0
  else
    err "Instale Docker Desktop, OrbStack ou Colima manualmente:"
    echo "  Docker Desktop: https://docs.docker.com/desktop/install/mac-install/"
    echo "  OrbStack:       https://orbstack.dev/"
    exit 1
  fi
fi

if ! docker info &>/dev/null; then
  err "Docker daemon não está rodando. Abra o Docker Desktop / OrbStack e tente de novo."
  open -a Docker 2>/dev/null || true
  exit 1
fi

ok "Pré-requisitos OK (Docker $(docker --version | awk '{print $3}' | tr -d ','))"

# ─────────────────────────────────────────────────────────
# 3. Estrutura de pastas
# ─────────────────────────────────────────────────────────
log "Criando estrutura em ~/openclaw-data e ~/openclaw..."
mkdir -p "$HOME/openclaw-data/config"
mkdir -p "$HOME/openclaw-data/workspace"
mkdir -p "$HOME/openclaw-data/backups"
mkdir -p "$HOME/openclaw"
ok "Estrutura criada"

# ─────────────────────────────────────────────────────────
# 4. Copiar docker-compose.yml + scripts
# ─────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log "Copiando docker-compose.yml para ~/openclaw/..."
cp "$SCRIPT_DIR/docker-compose.yml" "$HOME/openclaw/docker-compose.yml"
ok "docker-compose.yml instalado"

log "Copiando backup.sh para ~/openclaw/..."
cp "$SCRIPT_DIR/scripts/backup.sh" "$HOME/openclaw/backup.sh"
chmod +x "$HOME/openclaw/backup.sh"
ok "backup.sh instalado"

# ─────────────────────────────────────────────────────────
# 5. .env — criar se não existir + perguntar API keys
# ─────────────────────────────────────────────────────────
if [[ ! -f "$HOME/openclaw/.env" ]]; then
  log "Gerando token novo e criando .env..."
  TOKEN=$(openssl rand -hex 32)
  cp "$SCRIPT_DIR/.env.example" "$HOME/openclaw/.env"
  sed -i.bak "s|__GENERATE_WITH_openssl_rand_hex_32__|$TOKEN|g" "$HOME/openclaw/.env"
  rm -f "$HOME/openclaw/.env.bak"

  # API keys — env > prompt > vazio
  ANTH="${ANTHROPIC_API_KEY:-}"
  OPNAI="${OPENAI_API_KEY:-}"
  OPNRT="${OPENROUTER_API_KEY:-}"

  if [[ "$NON_INTERACTIVE" != "1" ]]; then
    echo ""
    echo "API keys (ENTER para deixar vazio agora — pode editar ~/openclaw/.env depois):"
    [[ -z "$ANTH" ]] && read -r -p "  ANTHROPIC_API_KEY  : " ANTH || true
    [[ -z "$OPNAI" ]] && read -r -p "  OPENAI_API_KEY     : " OPNAI || true
    [[ -z "$OPNRT" ]] && read -r -p "  OPENROUTER_API_KEY : " OPNRT || true
  fi

  [[ -n "$ANTH" ]]  && sed -i.bak "s|^ANTHROPIC_API_KEY=.*|ANTHROPIC_API_KEY=$ANTH|" "$HOME/openclaw/.env"
  [[ -n "$OPNAI" ]] && sed -i.bak "s|^OPENAI_API_KEY=.*|OPENAI_API_KEY=$OPNAI|" "$HOME/openclaw/.env"
  [[ -n "$OPNRT" ]] && sed -i.bak "s|^OPENROUTER_API_KEY=.*|OPENROUTER_API_KEY=$OPNRT|" "$HOME/openclaw/.env"
  rm -f "$HOME/openclaw/.env.bak"

  chmod 600 "$HOME/openclaw/.env"
  ok ".env criado (chmod 600)"
else
  ok ".env já existe — preservado (não sobrescrito)"
  TOKEN=$(grep '^OPENCLAW_GATEWAY_TOKEN=' "$HOME/openclaw/.env" | cut -d= -f2)
fi

# ─────────────────────────────────────────────────────────
# 6. openclaw.json — criar se não existir
# ─────────────────────────────────────────────────────────
if [[ ! -f "$HOME/openclaw-data/config/openclaw.json" ]]; then
  log "Criando openclaw.json a partir do template..."
  cp "$SCRIPT_DIR/config/openclaw.json.example" "$HOME/openclaw-data/config/openclaw.json"
  sed -i.bak "s|__REPLACE_WITH_openssl_rand_hex_32__|$TOKEN|g" "$HOME/openclaw-data/config/openclaw.json"
  rm -f "$HOME/openclaw-data/config/openclaw.json.bak"
  ok "openclaw.json criado com token sincronizado"
else
  ok "openclaw.json já existe — preservado"
  warn "Verifique que gateway.auth.token bate com OPENCLAW_GATEWAY_TOKEN do .env"
fi

# ─────────────────────────────────────────────────────────
# 7. Workspace bootstrap — copia persona Claudius
# ─────────────────────────────────────────────────────────
if [[ ! -f "$HOME/openclaw-data/workspace/PERSONA.md" ]]; then
  if [[ -d "$SCRIPT_DIR/agent/workspace" ]]; then
    log "Copiando persona Claudius para ~/openclaw-data/workspace/..."
    cp "$SCRIPT_DIR/agent/workspace/"*.md "$HOME/openclaw-data/workspace/"
    ok "Persona Claudius instalada (PERSONA, BOOTSTRAP, MEMORY, USER, TOOLS)"
    warn "Edite USER.md e MEMORY.md com seus dados antes de operar (ver agent/README.md)"
  else
    log "Criando workspace placeholder mínimo..."
    cat > "$HOME/openclaw-data/workspace/USER.md" <<'EOF'
# Usuário

> Quem você é, suas preferências e contexto. Será injetado no início de cada sessão.
EOF
    ok "Workspace mínimo criado em ~/openclaw-data/workspace/"
  fi
fi

# ─────────────────────────────────────────────────────────
# 8. Pull + Up
# ─────────────────────────────────────────────────────────
log "Fazendo pull da imagem OpenClaw..."
cd "$HOME/openclaw"
docker compose pull
ok "Pull concluído"

log "Subindo container..."
docker compose up -d
ok "Container iniciado"

# ─────────────────────────────────────────────────────────
# 9. Validação healthcheck
# ─────────────────────────────────────────────────────────
log "Aguardando healthcheck (até 60s)..."
HEALTHY=0
for i in {1..30}; do
  if docker inspect openclaw-gateway --format='{{.State.Health.Status}}' 2>/dev/null | grep -q healthy; then
    HEALTHY=1
    break
  fi
  sleep 2
done
[[ "$HEALTHY" == "1" ]] && ok "Container healthy" || warn "Healthcheck demorando — verificar com 'docker logs openclaw-gateway'"

# ─────────────────────────────────────────────────────────
# 10. Backup launchd (opcional)
# ─────────────────────────────────────────────────────────
if [[ "$ENABLE_BACKUP" == "1" ]]; then
  CONFIG_BACKUP="y"
elif [[ "$NON_INTERACTIVE" != "1" ]]; then
  CONFIG_BACKUP=$(ask "Configurar backup automático às 03:00 via launchd? [Y/n] " "y")
else
  CONFIG_BACKUP="n"
fi

if [[ "${CONFIG_BACKUP,,}" =~ ^(y|s|sim|yes|)$ ]]; then
  PLIST="$HOME/Library/LaunchAgents/com.openclaw.backup.plist"
  cat > "$PLIST" <<EOF
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
  launchctl unload "$PLIST" 2>/dev/null || true
  launchctl load "$PLIST"
  ok "Backup launchd configurado (03:00 todo dia, retenção 14d)"
fi

# ─────────────────────────────────────────────────────────
# Validação de hardening
# ─────────────────────────────────────────────────────────
echo ""
log "Validando hardening..."
PORT_BIND=$(docker port openclaw-gateway 2>/dev/null | head -1)
if echo "$PORT_BIND" | grep -q "127\.0\.0\.1"; then ok "bind 127.0.0.1 OK"; else warn "bind suspeito: $PORT_BIND"; fi

CAPS=$(docker inspect openclaw-gateway --format='{{.HostConfig.CapDrop}}' 2>/dev/null)
if echo "$CAPS" | grep -q "ALL"; then ok "cap_drop: ALL OK"; else warn "caps suspeitas: $CAPS"; fi

if docker inspect openclaw-gateway --format='{{range .Mounts}}{{.Source}}{{"\n"}}{{end}}' 2>/dev/null | grep -q docker.sock; then
  err "docker.sock MONTADO — escape risk!"
else
  ok "docker.sock protegido"
fi

# ─────────────────────────────────────────────────────────
# Resultado final
# ─────────────────────────────────────────────────────────
HAS_ANTH=$(grep -c '^ANTHROPIC_API_KEY=.\+' "$HOME/openclaw/.env" || true)

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  OpenClaw Mac mini instalado com hardening"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  Control UI:   http://127.0.0.1:18789"
echo "  Token:        ~/openclaw/.env"
echo "  Config:       ~/openclaw-data/config/openclaw.json"
echo "  Workspace:    ~/openclaw-data/workspace/"
echo "  Backups:      ~/openclaw-data/backups/"
echo ""

if [[ "$HAS_ANTH" == "0" ]]; then
  warn "ANTHROPIC_API_KEY vazia. Edite ~/openclaw/.env e rode:"
  echo "    docker compose -f ~/openclaw/docker-compose.yml restart"
  echo ""
fi

echo "  Próximo: abrir http://127.0.0.1:18789 e autenticar com o token"
echo ""
echo "═══════════════════════════════════════════════════════"
