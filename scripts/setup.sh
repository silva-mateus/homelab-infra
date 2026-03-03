#!/bin/bash
set -euo pipefail

INSTALL_DIR="/opt/homelab"

echo "========================================="
echo "  Homelab Setup Script"
echo "========================================="

# 1. Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "[1/6] Installing Docker..."
    curl -fsSL https://get.docker.com | sh
    sudo systemctl enable docker
    sudo systemctl start docker
    sudo usermod -aG docker "$USER"
    echo "Docker installed. You may need to re-login for group changes."
else
    echo "[1/6] Docker already installed: $(docker --version)"
fi

# 2. Check if Docker Compose plugin is available
if ! docker compose version &> /dev/null; then
    echo "[2/6] Installing Docker Compose plugin..."
    sudo apt-get update
    sudo apt-get install -y docker-compose-plugin
else
    echo "[2/6] Docker Compose already installed: $(docker compose version)"
fi

# 3. Clone or update the infra repo
if [ -d "$INSTALL_DIR" ]; then
    echo "[3/6] Updating existing installation at $INSTALL_DIR..."
    cd "$INSTALL_DIR"
    git pull
else
    echo "[3/6] Cloning homelab-infra to $INSTALL_DIR..."
    read -rp "Enter the homelab-infra git repo URL: " REPO_URL
    sudo mkdir -p "$INSTALL_DIR"
    sudo chown "$USER:$USER" "$INSTALL_DIR"
    git clone "$REPO_URL" "$INSTALL_DIR"
    cd "$INSTALL_DIR"
fi

# 4. Set up environment file
cd "$INSTALL_DIR/docker"
if [ ! -f .env ]; then
    echo "[4/6] Creating .env from template..."
    cp .env.example .env
    echo ""
    echo "IMPORTANT: Edit $INSTALL_DIR/docker/.env with your actual passwords and tokens."
    echo "Press Enter after editing the file to continue..."
    read -r
else
    echo "[4/6] .env already exists, skipping..."
fi

# 5. Start shared services (PostgreSQL, Cloudflare Tunnel)
echo "[5/6] Starting shared services (PostgreSQL, Cloudflare Tunnel)..."
docker compose up -d

echo "Waiting for PostgreSQL to be healthy..."
RETRIES=30
until docker compose exec postgres pg_isready -U postgres 2>/dev/null; do
    RETRIES=$((RETRIES - 1))
    if [ $RETRIES -le 0 ]; then
        echo "ERROR: PostgreSQL did not become healthy in time."
        exit 1
    fi
    sleep 2
done
echo "PostgreSQL is ready."

# 6. Start application services
echo "[6/6] Starting application services..."
docker compose -f docker-compose.apps.yml up -d

echo ""
echo "========================================="
echo "  Setup complete!"
echo "========================================="
echo ""
echo "Shared services: docker compose -f docker-compose.yml ps"
echo "App services:    docker compose -f docker-compose.apps.yml ps"
echo "Logs:            docker compose -f docker-compose.apps.yml logs -f <service>"
echo ""
