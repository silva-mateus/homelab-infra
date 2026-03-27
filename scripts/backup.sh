#!/bin/bash
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/opt/homelab/backups}"
COMPOSE_DIR="${COMPOSE_DIR:-/opt/homelab/docker}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# ---------------------------------------------------------------------------
# App registry — maps each app to its PostgreSQL database and Docker volumes.
# Add new apps here as they are created.
# ---------------------------------------------------------------------------
ALL_APPS=(musicas-igreja gerenciamento-financeiro gerenciamento-pastoral gestao-aulas portfolio)

declare -A APP_DBS=(
    [musicas-igreja]="musicas_igreja"
    [gerenciamento-financeiro]="gerenciamento_financeiro"
    [gerenciamento-pastoral]="gerenciamento_pastoral"
    [gestao-aulas]="gestao_aulas"
)

declare -A APP_VOLUMES=(
    [musicas-igreja]="homelab_musicas_data homelab_musicas_organized"
    [portfolio]="homelab_portfolio_highscores"
)

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    echo "Usage: $0 [app-name]"
    echo ""
    echo "Without arguments, backs up all apps."
    echo "With an app name, backs up only that app."
    echo ""
    echo "Available apps: ${ALL_APPS[*]}"
    echo ""
    echo "Environment variables:"
    echo "  BACKUP_DIR      Backup root directory  (default: /opt/homelab/backups)"
    echo "  COMPOSE_DIR     Docker compose directory (default: /opt/homelab/docker)"
    echo "  RETENTION_DAYS  Days to keep old backups (default: 30)"
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
TARGET_APP="${1:-}"

if [ "$TARGET_APP" = "-h" ] || [ "$TARGET_APP" = "--help" ]; then
    usage
    exit 0
fi

if [ -n "$TARGET_APP" ]; then
    found=false
    for app in "${ALL_APPS[@]}"; do
        if [ "$app" = "$TARGET_APP" ]; then
            found=true
            break
        fi
    done
    if [ "$found" = false ]; then
        echo "ERROR: Unknown app '$TARGET_APP'"
        echo "Available apps: ${ALL_APPS[*]}"
        exit 1
    fi
fi

if [ -n "$TARGET_APP" ]; then
    APPS_TO_BACKUP=("$TARGET_APP")
else
    APPS_TO_BACKUP=("${ALL_APPS[@]}")
fi

echo "========================================="
echo "  Homelab Backup - $TIMESTAMP"
if [ -n "$TARGET_APP" ]; then
    echo "  App: $TARGET_APP"
fi
echo "========================================="
echo ""

if [ -f "$COMPOSE_DIR/.env" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$COMPOSE_DIR/.env"
    set +a
fi

ERRORS=0

# ---------------------------------------------------------------------------
# 1. PostgreSQL globals (roles, users, permissions)
# ---------------------------------------------------------------------------
echo "[1/4] Backing up PostgreSQL globals (roles/users)..."
GLOBALS_DIR="$BACKUP_DIR/globals"
mkdir -p "$GLOBALS_DIR"
GLOBALS_FILE="$GLOBALS_DIR/globals_$TIMESTAMP.sql.gz"

if docker compose -f "$COMPOSE_DIR/docker-compose.yml" exec -T postgres \
    pg_dumpall --globals-only -U postgres 2>/dev/null \
    | gzip > "$GLOBALS_FILE"; then
    echo "  -> $GLOBALS_FILE ($(du -h "$GLOBALS_FILE" | cut -f1))"
else
    echo "  ERROR: Failed to backup globals."
    ERRORS=$((ERRORS + 1))
fi

# ---------------------------------------------------------------------------
# 2. Per-database backups
# ---------------------------------------------------------------------------
echo ""
echo "[2/4] Backing up databases..."
DB_COUNT=0

for app in "${APPS_TO_BACKUP[@]}"; do
    db="${APP_DBS[$app]:-}"
    [ -z "$db" ] && continue

    app_dir="$BACKUP_DIR/$app"
    mkdir -p "$app_dir"
    db_file="$app_dir/db_${TIMESTAMP}.sql.gz"

    echo "  [$app] Dumping database '$db'..."
    if docker compose -f "$COMPOSE_DIR/docker-compose.yml" exec -T postgres \
        pg_dump -U postgres "$db" 2>/dev/null \
        | gzip > "$db_file"; then
        echo "    -> $db_file ($(du -h "$db_file" | cut -f1))"
        DB_COUNT=$((DB_COUNT + 1))
    else
        echo "    ERROR: Failed to dump '$db'."
        rm -f "$db_file"
        ERRORS=$((ERRORS + 1))
    fi
done

echo "  $DB_COUNT database(s) backed up."

# ---------------------------------------------------------------------------
# 3. Per-volume backups
# ---------------------------------------------------------------------------
echo ""
echo "[3/4] Backing up volumes..."
VOL_COUNT=0

for app in "${APPS_TO_BACKUP[@]}"; do
    volumes="${APP_VOLUMES[$app]:-}"
    [ -z "$volumes" ] && continue

    app_dir="$BACKUP_DIR/$app"
    mkdir -p "$app_dir"

    for volume in $volumes; do
        if ! docker volume inspect "$volume" &>/dev/null; then
            echo "  [$app] Volume '$volume' not found, skipping."
            continue
        fi

        vol_file="vol_${volume#homelab_}_${TIMESTAMP}.tar.gz"
        echo "  [$app] Backing up volume '$volume'..."
        if docker run --rm \
            -v "$volume:/source:ro" \
            -v "$app_dir:/output" \
            alpine tar czf "/output/$vol_file" -C /source . 2>/dev/null; then
            echo "    -> $app_dir/$vol_file"
            VOL_COUNT=$((VOL_COUNT + 1))
        else
            echo "    ERROR: Failed to backup volume '$volume'."
            ERRORS=$((ERRORS + 1))
        fi
    done
done

echo "  $VOL_COUNT volume(s) backed up."

# ---------------------------------------------------------------------------
# 4. Cleanup old backups
# ---------------------------------------------------------------------------
echo ""
echo "[4/4] Cleaning up backups older than $RETENTION_DAYS days..."
find "$BACKUP_DIR" -type f \
    \( -name "db_*.sql.gz" -o -name "vol_*.tar.gz" -o -name "globals_*.sql.gz" \) \
    -mtime +"$RETENTION_DAYS" -delete 2>/dev/null || true

# Remove empty app directories left after cleanup
find "$BACKUP_DIR" -mindepth 1 -type d -empty -delete 2>/dev/null || true

echo ""
if [ "$ERRORS" -gt 0 ]; then
    echo "Backup finished with $ERRORS error(s). Check output above."
    exit 1
else
    echo "Backup complete — $DB_COUNT database(s), $VOL_COUNT volume(s)."
fi
echo ""
