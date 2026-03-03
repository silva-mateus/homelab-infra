# Homelab Infrastructure

IaC (Infrastructure as Code) para o homelab Proxmox, gerenciando todos os projetos pessoais com Docker.

## Arquitetura

- **PostgreSQL 17** compartilhado para todos os projetos
- **Cloudflare Tunnel** para acesso externo
- **GHCR** (GitHub Container Registry) para imagens Docker
- **GitHub Actions** reusable workflows para CI/CD

## Setup Inicial

```bash
# No servidor (VM no Proxmox)
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

1. Adicionar database e user nos init scripts (`docker/postgres/init/`)
2. Adicionar variáveis em `docker/.env.example` e `.env`
3. Passar as variáveis para o serviço `postgres` em `docker/docker-compose.yml`
4. Adicionar service em `docker/docker-compose.apps.yml`
5. Configurar hostname no Cloudflare Tunnel dashboard

## Backup

O script `scripts/backup.sh` faz dump de todos os databases PostgreSQL e volumes Docker.
Backups são salvos em `/opt/homelab/backups/` com retenção de 30 dias.

Para agendar backup diário:

```bash
# crontab -e
0 3 * * * /opt/homelab/scripts/backup.sh >> /var/log/homelab-backup.log 2>&1
```
