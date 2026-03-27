#!/bin/bash
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/opt/homelab/backups}"
COMPOSE_DIR="${COMPOSE_DIR:-/opt/homelab/docker}"

# ---------------------------------------------------------------------------
# App registry — must match backup.sh
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

declare -A APP_SERVICES=(
    [musicas-igreja]="musicas-igreja-api musicas-igreja-web"
    [gerenciamento-financeiro]="gerenciamento-financeiro-api gerenciamento-financeiro-web"
    [gerenciamento-pastoral]="gerenciamento-pastoral-api gerenciamento-pastoral-web"
    [gestao-aulas]="gestao-aulas-api gestao-aulas-web"
    [portfolio]="portfolio portfolio-api"
)

# ---------------------------------------------------------------------------
# Usage
# ---------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Without arguments, starts interactive mode.

Options:
  --app <name>       Restore a specific app
  --all              Restore all apps
  --latest           Use the most recent backup
  --timestamp <ts>   Use a specific timestamp (format: YYYYMMDD_HHMMSS)
  --db-only          Restore only the database (skip volumes)
  --volumes-only     Restore only volumes (skip database)
  -h, --help         Show this help

Examples:
  $0                                           # interactive mode
  $0 --app musicas-igreja --latest             # restore latest DB + volumes
  $0 --app musicas-igreja --db-only --latest   # restore only the latest DB
  $0 --all --latest                            # restore everything from latest

Available apps: ${ALL_APPS[*]}
EOF
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
find_latest_timestamp() {
    local app_dir="$1"
    ls -1 "$app_dir" 2>/dev/null \
        | grep -oE '[0-9]{8}_[0-9]{6}' \
        | sort -ru \
        | head -1
}

list_timestamps() {
    local app_dir="$1"
    ls -1 "$app_dir" 2>/dev/null \
        | grep -oE '[0-9]{8}_[0-9]{6}' \
        | sort -ru \
        | uniq
}

apps_with_backups() {
    local result=()
    for app in "${ALL_APPS[@]}"; do
        local app_dir="$BACKUP_DIR/$app"
        if [ -d "$app_dir" ] && [ -n "$(ls -A "$app_dir" 2>/dev/null)" ]; then
            result+=("$app")
        fi
    done
    echo "${result[@]}"
}

ensure_postgres_running() {
    echo "  Ensuring PostgreSQL is running..."
    docker compose -f "$COMPOSE_DIR/docker-compose.yml" up -d postgres >/dev/null 2>&1

    local retries=15
    while ! docker compose -f "$COMPOSE_DIR/docker-compose.yml" exec -T postgres pg_isready -U postgres >/dev/null 2>&1; do
        retries=$((retries - 1))
        if [ "$retries" -le 0 ]; then
            echo "  ERROR: PostgreSQL did not become ready in time."
            exit 1
        fi
        sleep 2
    done
    echo "  PostgreSQL is ready."
}

# ---------------------------------------------------------------------------
# Restore functions
# ---------------------------------------------------------------------------
restore_globals() {
    local globals_dir="$BACKUP_DIR/globals"
    local latest
    latest=$(find_latest_timestamp "$globals_dir")

    if [ -z "$latest" ]; then
        echo "  No globals backup found, skipping roles/users restore."
        return 0
    fi

    local globals_file="$globals_dir/globals_${latest}.sql.gz"
    if [ ! -f "$globals_file" ]; then
        echo "  Globals file not found for timestamp $latest, skipping."
        return 0
    fi

    echo "  Restoring globals (roles/users) from $latest..."
    gunzip -c "$globals_file" | docker compose -f "$COMPOSE_DIR/docker-compose.yml" exec -T postgres psql -U postgres >/dev/null 2>&1 || true
    echo "  Globals restored."
}

restore_db() {
    local app="$1"
    local timestamp="$2"
    local db="${APP_DBS[$app]:-}"

    if [ -z "$db" ]; then
        echo "  [$app] No database configured, skipping DB restore."
        return 0
    fi

    local db_file="$BACKUP_DIR/$app/db_${timestamp}.sql.gz"
    if [ ! -f "$db_file" ]; then
        echo "  [$app] ERROR: Backup file not found: $db_file"
        return 1
    fi

    echo "  [$app] Dropping and recreating database '$db'..."
    docker compose -f "$COMPOSE_DIR/docker-compose.yml" exec -T postgres \
        psql -U postgres -c "DROP DATABASE IF EXISTS $db;" >/dev/null 2>&1
    docker compose -f "$COMPOSE_DIR/docker-compose.yml" exec -T postgres \
        psql -U postgres -c "CREATE DATABASE $db ENCODING 'UTF8' LC_COLLATE 'en_US.utf8' LC_CTYPE 'en_US.utf8';" >/dev/null 2>&1

    echo "  [$app] Restoring database '$db' from $timestamp..."
    gunzip -c "$db_file" | docker compose -f "$COMPOSE_DIR/docker-compose.yml" exec -T postgres psql -U postgres -d "$db" >/dev/null 2>&1
    echo "  [$app] Database restored."
}

restore_volumes() {
    local app="$1"
    local timestamp="$2"
    local volumes="${APP_VOLUMES[$app]:-}"

    if [ -z "$volumes" ]; then
        echo "  [$app] No volumes configured, skipping volume restore."
        return 0
    fi

    local services="${APP_SERVICES[$app]:-}"

    if [ -n "$services" ]; then
        echo "  [$app] Stopping app services..."
        # shellcheck disable=SC2086
        docker compose -f "$COMPOSE_DIR/docker-compose.apps.yml" stop $services 2>/dev/null || true
    fi

    for volume in $volumes; do
        local vol_short="${volume#homelab_}"
        local vol_file="$BACKUP_DIR/$app/vol_${vol_short}_${timestamp}.tar.gz"

        if [ ! -f "$vol_file" ]; then
            echo "  [$app] Volume backup not found: $vol_file, skipping."
            continue
        fi

        echo "  [$app] Restoring volume '$volume' from $timestamp..."
        docker run --rm \
            -v "$volume:/target" \
            -v "$(dirname "$vol_file"):/input:ro" \
            alpine sh -c "rm -rf /target/* /target/..?* /target/.[!.]* 2>/dev/null; tar xzf /input/$(basename "$vol_file") -C /target"
        echo "  [$app] Volume '$volume' restored."
    done

    if [ -n "$services" ]; then
        echo "  [$app] Starting app services..."
        # shellcheck disable=SC2086
        docker compose -f "$COMPOSE_DIR/docker-compose.apps.yml" start $services 2>/dev/null || true
    fi
}

restart_app_services() {
    local app="$1"
    local services="${APP_SERVICES[$app]:-}"
    if [ -n "$services" ]; then
        echo "  [$app] Restarting app services..."
        # shellcheck disable=SC2086
        docker compose -f "$COMPOSE_DIR/docker-compose.apps.yml" restart $services 2>/dev/null || true
    fi
}

restore_app() {
    local app="$1"
    local timestamp="$2"
    local what="$3"

    echo ""
    echo "--- Restoring: $app ($what) from $timestamp ---"

    case "$what" in
        db-only)
            restore_db "$app" "$timestamp"
            restart_app_services "$app"
            ;;
        volumes-only)
            restore_volumes "$app" "$timestamp"
            ;;
        all)
            restore_db "$app" "$timestamp"
            restore_volumes "$app" "$timestamp"
            restart_app_services "$app"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Interactive mode
# ---------------------------------------------------------------------------
interactive_mode() {
    echo ""
    echo "Scanning for available backups..."

    local available
    # shellcheck disable=SC2207
    available=($(apps_with_backups))

    if [ ${#available[@]} -eq 0 ]; then
        echo "No backups found in $BACKUP_DIR."
        exit 0
    fi

    echo ""
    echo "Apps with available backups:"
    local i=1
    for app in "${available[@]}"; do
        echo "  $i) $app"
        ((i++))
    done
    echo "  a) Restore ALL apps"
    echo ""

    local choice
    read -rp "Select an option: " choice

    local selected_apps=()
    if [ "$choice" = "a" ] || [ "$choice" = "A" ]; then
        selected_apps=("${available[@]}")
    elif [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#available[@]} ]; then
        selected_apps=("${available[$((choice - 1))]}")
    else
        echo "Invalid selection."
        exit 1
    fi

    for app in "${selected_apps[@]}"; do
        echo ""
        echo "--- $app ---"
        local app_dir="$BACKUP_DIR/$app"
        local timestamps
        # shellcheck disable=SC2207
        timestamps=($(list_timestamps "$app_dir"))

        if [ ${#timestamps[@]} -eq 0 ]; then
            echo "  No backup timestamps found, skipping."
            continue
        fi

        echo "  Available backups:"
        local j=1
        for ts in "${timestamps[@]}"; do
            local formatted="${ts:0:4}-${ts:4:2}-${ts:6:2} ${ts:9:2}:${ts:11:2}:${ts:13:2}"
            echo "    $j) $formatted ($ts)"
            ((j++))
        done
        echo ""

        local ts_choice
        read -rp "  Select backup number for $app (or 'skip'): " ts_choice

        if [ "$ts_choice" = "skip" ]; then
            echo "  Skipping $app."
            continue
        fi

        if ! [[ "$ts_choice" =~ ^[0-9]+$ ]] || [ "$ts_choice" -lt 1 ] || [ "$ts_choice" -gt ${#timestamps[@]} ]; then
            echo "  Invalid selection, skipping $app."
            continue
        fi

        local selected_ts="${timestamps[$((ts_choice - 1))]}"

        echo ""
        echo "  What to restore?"
        echo "    1) Database + Volumes (all)"
        echo "    2) Database only"
        echo "    3) Volumes only"
        echo ""
        local what_choice
        read -rp "  Select option: " what_choice

        local what="all"
        case "$what_choice" in
            1) what="all" ;;
            2) what="db-only" ;;
            3) what="volumes-only" ;;
            *) echo "  Invalid selection, defaulting to all." ;;
        esac

        echo ""
        echo "  About to restore $app ($what) from $selected_ts."
        local confirm
        read -rp "  Continue? (yes/no): " confirm
        if [ "$confirm" != "yes" ]; then
            echo "  Skipping $app."
            continue
        fi

        ensure_postgres_running
        restore_globals
        restore_app "$app" "$selected_ts" "$what"
    done

    echo ""
    echo "Restore complete."
}

# ---------------------------------------------------------------------------
# CLI argument parsing
# ---------------------------------------------------------------------------
MODE="interactive"
TARGET_APP=""
TIMESTAMP_ARG=""
RESTORE_WHAT="all"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app)
            TARGET_APP="$2"
            MODE="cli"
            shift 2
            ;;
        --all)
            TARGET_APP="__all__"
            MODE="cli"
            shift
            ;;
        --latest)
            TIMESTAMP_ARG="latest"
            shift
            ;;
        --timestamp)
            TIMESTAMP_ARG="$2"
            shift 2
            ;;
        --db-only)
            RESTORE_WHAT="db-only"
            shift
            ;;
        --volumes-only)
            RESTORE_WHAT="volumes-only"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

echo "========================================="
echo "  Homelab Restore"
echo "========================================="

if [ -f "$COMPOSE_DIR/.env" ]; then
    set -a
    # shellcheck source=/dev/null
    source "$COMPOSE_DIR/.env"
    set +a
fi

if [ "$MODE" = "interactive" ]; then
    interactive_mode
    exit 0
fi

# ---------------------------------------------------------------------------
# CLI mode validation
# ---------------------------------------------------------------------------
if [ -z "$TIMESTAMP_ARG" ]; then
    echo "ERROR: --latest or --timestamp <ts> is required in CLI mode."
    usage
    exit 1
fi

if [ "$TARGET_APP" != "__all__" ]; then
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
    CLI_APPS=("$TARGET_APP")
else
    CLI_APPS=("${ALL_APPS[@]}")
fi

ensure_postgres_running
restore_globals

for app in "${CLI_APPS[@]}"; do
    app_dir="$BACKUP_DIR/$app"

    if [ ! -d "$app_dir" ]; then
        echo "  [$app] No backup directory found, skipping."
        continue
    fi

    if [ "$TIMESTAMP_ARG" = "latest" ]; then
        ts=$(find_latest_timestamp "$app_dir")
        if [ -z "$ts" ]; then
            echo "  [$app] No backups found, skipping."
            continue
        fi
        echo "  [$app] Using latest backup: $ts"
    else
        ts="$TIMESTAMP_ARG"
    fi

    restore_app "$app" "$ts" "$RESTORE_WHAT"
done

echo ""
echo "Restore complete."
