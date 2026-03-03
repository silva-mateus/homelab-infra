#!/bin/bash
set -euo pipefail

COMPOSE_DIR="${COMPOSE_DIR:-/opt/homelab/docker}"
BACKUP_DIR="${BACKUP_DIR:-/opt/homelab/backups}"

echo "========================================="
echo "  Homelab Restore"
echo "========================================="

# Load env vars
if [ -f "$COMPOSE_DIR/.env" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$COMPOSE_DIR/.env"
    set +a
fi

echo ""
echo "Available PostgreSQL backups:"
ls -lh "$BACKUP_DIR"/postgres_*.sql.gz 2>/dev/null || echo "  (none found)"
echo ""

read -rp "Enter the full path to the PostgreSQL backup file: " BACKUP_FILE

if [ ! -f "$BACKUP_FILE" ]; then
    echo "ERROR: File not found: $BACKUP_FILE"
    exit 1
fi

echo ""
echo "WARNING: This will overwrite ALL databases in the PostgreSQL instance."
read -rp "Are you sure? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

echo ""
echo "[1/2] Ensuring PostgreSQL is running..."
cd "$COMPOSE_DIR"
docker compose up -d postgres
sleep 5

echo "[2/2] Restoring from $BACKUP_FILE..."
gunzip -c "$BACKUP_FILE" | docker compose exec -T postgres psql -U postgres

echo ""
echo "Restore complete. Restarting application services..."
cd "$COMPOSE_DIR"
docker compose -f docker-compose.apps.yml restart

echo "Done."
