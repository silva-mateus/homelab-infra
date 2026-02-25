# Homelab Infrastructure

IaC (Infrastructure as Code) para o homelab Proxmox, gerenciando todos os projetos pessoais com Docker.

## Arquitetura

- **MySQL 8.0** compartilhado (um database por projeto)
- **Cloudflare Tunnel** para acesso externo
- **GHCR** (GitHub Container Registry) para imagens Docker
- **GitHub Actions** reusable workflows para CI/CD

## Setup Inicial

```bash
# No servidor (VM/LXC no Proxmox)
curl -fsSL https://raw.githubusercontent.com/SEU_USER/homelab-infra/main/scripts/setup.sh | bash
```

Ou manualmente:

```bash
git clone <repo-url> /opt/homelab
cd /opt/homelab/docker
cp .env.example .env
# Editar .env com suas credenciais
docker compose up -d
docker compose -f docker-compose.apps.yml up -d
```

## Comandos Úteis

```bash
cd /opt/homelab/docker

# Status dos serviços
docker compose ps
docker compose -f docker-compose.apps.yml ps

# Logs
docker compose -f docker-compose.apps.yml logs -f musicas-igreja-api

# Atualizar um serviço
docker compose -f docker-compose.apps.yml pull musicas-igreja-api
docker compose -f docker-compose.apps.yml up -d musicas-igreja-api

# Backup
../scripts/backup.sh

# Restore
../scripts/restore.sh
```

## Adicionar Novo Projeto

1. Adicionar database em `docker/mysql/init/01-create-databases.sql`
2. Adicionar user em `docker/mysql/init/02-create-users.sql`
3. Adicionar variáveis em `docker/.env.example` e `.env`
4. Adicionar service em `docker/docker-compose.apps.yml`
5. Configurar hostname no Cloudflare Tunnel dashboard

## Backup

O script `scripts/backup.sh` faz dump de todos os databases MySQL e volumes Docker.
Backups são salvos em `/opt/homelab/backups/` com retenção de 30 dias.

Para agendar backup diário:

```bash
# crontab -e
0 3 * * * /opt/homelab/scripts/backup.sh >> /var/log/homelab-backup.log 2>&1
```
