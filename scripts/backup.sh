#!/usr/bin/env bash
# OpenClaw Mac mini — backup automático
# Roda diariamente via launchd (ver QUICKSTART.md §8)
set -euo pipefail

DATE=$(date +%Y-%m-%d_%H%M%S)
BACKUP_DIR="$HOME/openclaw-data/backups"
SOURCE_DIR="$HOME/openclaw-data/config"
COMPOSE="$HOME/openclaw/docker-compose.yml"
LOG="$HOME/openclaw-data/backup.log"
RETENTION_DAYS=14

mkdir -p "$BACKUP_DIR"

# Stop gateway pra consistência do SQLite
if docker compose -f "$COMPOSE" ps openclaw-gateway 2>/dev/null | grep -q running; then
  docker compose -f "$COMPOSE" stop openclaw-gateway
  STOPPED=1
else
  STOPPED=0
fi

# Tarball
ARCHIVE="$BACKUP_DIR/openclaw-$DATE.tar.gz"
tar czf "$ARCHIVE" -C "$HOME/openclaw-data" config

# Restart se foi stopped por nós
if [[ "$STOPPED" == "1" ]]; then
  docker compose -f "$COMPOSE" start openclaw-gateway
fi

# Retenção
find "$BACKUP_DIR" -name "openclaw-*.tar.gz" -mtime +"$RETENTION_DAYS" -delete

# Log
SIZE=$(du -h "$ARCHIVE" | cut -f1)
echo "[$(date)] Backup OK: $ARCHIVE ($SIZE)" >> "$LOG"
