#!/usr/bin/env bash
# OpenClaw Mac mini — bootstrap automatizado
# Uso: bash install.sh
set -euo pipefail

# ─────────────────────────────────────────────────────────
# Cores
# ─────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[$(date +%H:%M:%S)]${NC} $*"; }
ok()   { echo -e "${GREEN}✅ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠  $*${NC}"; }
err()  { echo -e "${RED}❌ $*${NC}" >&2; }

# ─────────────────────────────────────────────────────────
# Pre-flight
# ─────────────────────────────────────────────────────────
log "Verificando pré-requisitos..."

if [[ "$(uname -s)" != "Darwin" ]]; then
  err "Este script é para macOS. Detectado: $(uname -s)"
  exit 1
fi

if ! command -v docker &>/dev/null; then
  err "Docker não encontrado. Instale Docker Desktop, OrbStack ou Colima primeiro."
  echo "  Docker Desktop: https://docs.docker.com/desktop/install/mac-install/"
  echo "  OrbStack:       https://orbstack.dev/"
  exit 1
fi

if ! docker info &>/dev/null; then
  err "Docker daemon não está rodando. Abra o Docker Desktop / OrbStack e tente de novo."
  exit 1
fi

if ! command -v openssl &>/dev/null; then
  err "openssl não encontrado. Instale via 'brew install openssl' e rode de novo."
  exit 1
fi

ok "Pré-requisitos OK"

# ─────────────────────────────────────────────────────────
# Estrutura de pastas
# ─────────────────────────────────────────────────────────
log "Criando estrutura em ~/openclaw-data e ~/openclaw..."
mkdir -p "$HOME/openclaw-data/config"
mkdir -p "$HOME/openclaw-data/workspace"
mkdir -p "$HOME/openclaw-data/backups"
mkdir -p "$HOME/openclaw"
ok "Estrutura criada"

# ─────────────────────────────────────────────────────────
# Copiar docker-compose.yml e arquivos de config
# ─────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log "Copiando docker-compose.yml para ~/openclaw/..."
cp "$SCRIPT_DIR/docker-compose.yml" "$HOME/openclaw/docker-compose.yml"
ok "docker-compose.yml instalado"

# ─────────────────────────────────────────────────────────
# .env — criar se não existir
# ─────────────────────────────────────────────────────────
if [[ ! -f "$HOME/openclaw/.env" ]]; then
  log "Gerando token novo e criando .env..."
  TOKEN=$(openssl rand -hex 32)
  cp "$SCRIPT_DIR/.env.example" "$HOME/openclaw/.env"
  # Substitui o placeholder pelo token gerado
  sed -i.bak "s|__GENERATE_WITH_openssl_rand_hex_32__|$TOKEN|g" "$HOME/openclaw/.env"
  rm -f "$HOME/openclaw/.env.bak"
  chmod 600 "$HOME/openclaw/.env"
  ok ".env criado com token novo (chmod 600)"
  warn "Edite ~/openclaw/.env e preencha as API keys (ANTHROPIC_API_KEY, etc) antes de subir."
else
  ok ".env já existe — preservado (não sobrescrito)"
  TOKEN=$(grep '^OPENCLAW_GATEWAY_TOKEN=' "$HOME/openclaw/.env" | cut -d= -f2)
fi

# ─────────────────────────────────────────────────────────
# openclaw.json — criar se não existir
# ─────────────────────────────────────────────────────────
if [[ ! -f "$HOME/openclaw-data/config/openclaw.json" ]]; then
  log "Criando openclaw.json a partir do template..."
  cp "$SCRIPT_DIR/config/openclaw.json.example" "$HOME/openclaw-data/config/openclaw.json"
  # Sincroniza token
  sed -i.bak "s|__REPLACE_WITH_openssl_rand_hex_32__|$TOKEN|g" "$HOME/openclaw-data/config/openclaw.json"
  rm -f "$HOME/openclaw-data/config/openclaw.json.bak"
  ok "openclaw.json criado com token sincronizado"
else
  ok "openclaw.json já existe — preservado"
  warn "Verifique manualmente que gateway.auth.token bate com OPENCLAW_GATEWAY_TOKEN do .env"
fi

# ─────────────────────────────────────────────────────────
# Workspace bootstrap — copia persona Claudius se disponível, senão placeholder
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
# Pull + Up
# ─────────────────────────────────────────────────────────
log "Fazendo pull da imagem OpenClaw..."
cd "$HOME/openclaw"
docker compose pull
ok "Pull concluído"

log "Subindo container..."
docker compose up -d
ok "Container iniciado"

# ─────────────────────────────────────────────────────────
# Validação
# ─────────────────────────────────────────────────────────
log "Aguardando healthcheck (até 60s)..."
for i in {1..30}; do
  if docker inspect openclaw-gateway --format='{{.State.Health.Status}}' 2>/dev/null | grep -q healthy; then
    ok "Container healthy"
    break
  fi
  sleep 2
done

# ─────────────────────────────────────────────────────────
# Resultado
# ─────────────────────────────────────────────────────────
echo ""
echo "═══════════════════════════════════════════════════════"
echo "  OpenClaw Mac mini instalado com hardening"
echo "═══════════════════════════════════════════════════════"
echo ""
echo "  Control UI:   http://127.0.0.1:18789"
echo "  Token:        ~/openclaw/.env  (chmod 600)"
echo "  Config:       ~/openclaw-data/config/openclaw.json"
echo "  Workspace:    ~/openclaw-data/workspace/"
echo "  Backups:      ~/openclaw-data/backups/"
echo ""
echo "  Próximos passos:"
echo "    1. Editar ~/openclaw/.env e adicionar API keys"
echo "    2. docker compose -f ~/openclaw/docker-compose.yml restart"
echo "    3. Abrir http://127.0.0.1:18789 e autenticar com o token"
echo ""
echo "  Validação de hardening (rodar manualmente):"
echo "    docker inspect openclaw-gateway --format='{{.HostConfig.CapDrop}}'"
echo "    docker port openclaw-gateway"
echo ""
echo "═══════════════════════════════════════════════════════"
