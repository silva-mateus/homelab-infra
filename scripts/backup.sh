#!/bin/bash
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/opt/homelab/backups}"
COMPOSE_DIR="${COMPOSE_DIR:-/opt/homelab/docker}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "========================================="
echo "  Homelab Backup - $TIMESTAMP"
echo "========================================="

mkdir -p "$BACKUP_DIR"

# Load env vars for database credentials
if [ -f "$COMPOSE_DIR/.env" ]; then
    set -a
    source "$COMPOSE_DIR/.env"
    set +a
fi

# 1. PostgreSQL dump (all databases)
echo "[1/3] Backing up PostgreSQL databases..."
PG_BACKUP="$BACKUP_DIR/postgres_$TIMESTAMP.sql.gz"
docker compose -f "$COMPOSE_DIR/docker-compose.yml" exec -T postgres \
    pg_dumpall -U postgres \
    | gzip > "$PG_BACKUP"
echo "  -> $PG_BACKUP ($(du -h "$PG_BACKUP" | cut -f1))"

# 2. Docker volumes backup
echo "[2/3] Backing up Docker volumes..."
VOLUMES_BACKUP="$BACKUP_DIR/volumes_$TIMESTAMP.tar.gz"
VOLUME_LIST=$(docker volume ls -q --filter name=homelab_ 2>/dev/null || true)
if [ -n "$VOLUME_LIST" ]; then
    docker run --rm \
        $(echo "$VOLUME_LIST" | xargs -I{} echo "-v {}:/backup/{}:ro") \
        -v "$BACKUP_DIR:/output" \
        alpine tar czf "/output/volumes_$TIMESTAMP.tar.gz" -C /backup .
    echo "  -> $VOLUMES_BACKUP"
else
    echo "  -> No homelab volumes found, skipping."
fi

# 3. Cleanup old backups
echo "[3/3] Cleaning up backups older than $RETENTION_DAYS days..."
find "$BACKUP_DIR" -name "postgres_*.sql.gz" -mtime +"$RETENTION_DAYS" -delete 2>/dev/null || true
find "$BACKUP_DIR" -name "volumes_*.tar.gz" -mtime +"$RETENTION_DAYS" -delete 2>/dev/null || true

echo ""
echo "Backup complete. Files in $BACKUP_DIR:"
ls -lh "$BACKUP_DIR"/*.{sql.gz,tar.gz} 2>/dev/null || echo "  (no backup files found)"
echo ""
