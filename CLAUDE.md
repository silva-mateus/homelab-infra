# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Working context (read first)

- **Default scope:** infra, compose, scripts, and server-side deploy live **here**. Application business logic and Dockerfiles for apps are in **their own repos** (e.g. **`gerenciamento-financeiro`**).
- When the user is only changing **app code**, they may work in the app repo; you only need this repo if the task touches compose, env templates, init SQL, backups, or deploy workflows.
- Optional: if your Claude Code workspace includes the parent folder, use skill **`homelab-networkmat`** for a short cross-repo map.

## Project Overview

This is a homelab infrastructure-as-code (IaC) project for managing personal projects with Docker on Proxmox. It provides shared infrastructure services (PostgreSQL, Redis) and hosts multiple personal applications.

## Architecture

### Core Infrastructure Services
- **PostgreSQL 17**: Shared database instance with separate databases for each application
- **Redis 7**: Used for caching and SignalR (specifically by the Finance Management API)
- **Cloudflare Tunnel**: Provides external access to services
- **Dozzle**: Real-time Docker log viewer
- **Adminer**: Database management interface
- **Homepage**: Dashboard for monitoring all services

### Application Structure
Applications are split across two Docker Compose files that must be used together:
- `docker/docker-compose.yml`: Core infrastructure services
- `docker/docker-compose.apps.yml`: Application services

All services share the `homelab` Docker network for internal communication.

### Related application repositories

| App (compose service prefix) | Source repo | Notes |
|-----------------------------|-------------|--------|
| `gerenciamento-financeiro-*` | `gerenciamento-financeiro` | API + web images; app `deploy.yml` calls this repo’s reusable workflow |

Add rows here when new apps are wired in `docker-compose.apps.yml`.

### Database Management
- Each application gets its own PostgreSQL database within the shared instance
- Database creation and user setup are handled by init scripts in `docker/postgres/init/`
- Environment variables define database credentials for each application

### Security Considerations
- This is a **public repository** serving as a portfolio
- **NEVER commit** sensitive data: API keys, tokens, passwords, `.env` files with real values
- Use environment variables for all secrets and configuration
- Keep `.env`, `appsettings.Development.json`, and similar config files in `.gitignore`

## Common Development Tasks

### Starting the Full Stack
```bash
cd docker
docker compose -f docker-compose.yml -f docker-compose.apps.yml up -d
```

### Checking Service Status
```bash
cd docker
docker compose -f docker-compose.yml -f docker-compose.apps.yml ps
```

### Viewing Logs
```bash
cd docker
docker compose -f docker-compose.yml -f docker-compose.apps.yml logs -f [service-name]
```

### Updating a Specific Service
```bash
cd docker
docker compose -f docker-compose.yml -f docker-compose.apps.yml pull [service-name]
docker compose -f docker-compose.yml -f docker-compose.apps.yml up -d [service-name]
```

### Backup Operations
```bash
# Full backup of all applications
../scripts/backup.sh

# Backup specific application only
../scripts/backup.sh [app-name]

# Restore from backup
../scripts/restore.sh
```

### Environment Setup
1. Copy `docker/.env.example` to `docker/.env`
2. Edit `.env` with actual values (never commit this file)
3. Required variables include:
   - `POSTGRES_PASSWORD`, `REDIS_PASSWORD`
   - `GITHUB_USER` (for pulling images from GHCR)
   - `CLOUDFLARE_TUNNEL_TOKEN`
   - Application-specific database credentials

## Adding a New Application

1. **Add database**: Create SQL in `docker/postgres/init/01-create-databases.sql`
2. **Add user script**: Update `docker/postgres/init/02-create-users.sh`
3. **Add environment variables**: Update `docker/.env.example` and server `.env`
4. **Pass variables to PostgreSQL**: Add to `postgres` service environment in `docker/docker-compose.yml`
5. **Add service definition**: Create service in `docker/docker-compose.apps.yml`
6. **Configure backup**: Add app to registry in `scripts/backup.sh`
7. **Configure Cloudflare**: Add hostname in Cloudflare Tunnel dashboard

## CI/CD Pipeline

- GitHub Actions validates Docker Compose configuration on push
- Automatic deployment to self-hosted runner on `main` branch push
- Deployment syncs repository and restarts services

## Backup System

- `scripts/backup.sh`: Creates PostgreSQL dumps and Docker volume backups
- Backups stored in `/opt/homelab/backups/` with 30-day retention
- Supports per-application or full-system backups
- Backup registry in script maps apps to databases and volumes

## Key Directories

- `docker/`: All Docker Compose files and configuration
- `docker/postgres/init/`: Database initialization scripts
- `docker/homepage/`: Homepage dashboard configuration
- `scripts/`: Backup, restore, and setup scripts
- `docs/`: Setup documentation for GitHub and Proxmox
- `cloudflare/`: **Optional / legacy** Tunnel config files — **not applied** to the live tunnel unless you adopt file-based sync. Live routes are set in the **dashboard** (see below).

## Important Notes

- **Cloudflare Tunnel:** public hostnames and origins are configured in the **Cloudflare dashboard**. Do not assume `cloudflare/config.yml` reflects production.
- **Financeiro web → tunnel:** map the origin to `gerenciamento-financeiro-web` using the **port the container listens on** for HTTP (often **8080** for unprivileged nginx images; confirm with `docker ps` / `EXPOSE` in the app `web.Dockerfile` if behavior changes).
- **Redis / financeiro API:** `Redis__ConnectionString` and DB URLs are set in `docker-compose.apps.yml` / server `.env` — see `gerenciamento-financeiro/CLAUDE.md` for app-side env names only.
- This is a solo project portfolio - no external contributions are accepted
- Always use both Docker Compose files together for correct networking and dependencies