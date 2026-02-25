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
    source "$COMPOSE_DIR/.env"
    set +a
fi

# List available backups
echo ""
echo "Available MySQL backups:"
ls -lh "$BACKUP_DIR"/mysql_*.sql.gz 2>/dev/null || echo "  (none found)"
echo ""

read -rp "Enter the full path to the MySQL backup file: " BACKUP_FILE

if [ ! -f "$BACKUP_FILE" ]; then
    echo "ERROR: File not found: $BACKUP_FILE"
    exit 1
fi

echo ""
echo "WARNING: This will overwrite ALL databases in the MySQL instance."
read -rp "Are you sure? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

# Ensure MySQL is running
echo ""
echo "[1/2] Ensuring MySQL is running..."
cd "$COMPOSE_DIR"
docker compose up -d mysql
sleep 5

# Restore
echo "[2/2] Restoring from $BACKUP_FILE..."
gunzip -c "$BACKUP_FILE" | docker compose exec -T mysql mysql -u root -p"${MYSQL_ROOT_PASSWORD}"

echo ""
echo "Restore complete. Restarting application services..."
docker compose -f docker-compose.apps.yml restart

echo "Done."
