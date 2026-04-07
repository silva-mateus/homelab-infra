# Homelab Infrastructure

IaC (Infrastructure as Code) para o homelab Proxmox, gerenciando todos os projetos pessoais com Docker.

## Arquitetura

- **PostgreSQL 17** compartilhado para todos os projetos
- **Redis 7** (cache / SignalR) — usado pelo **Gerenciamento Financeiro** API
- **Cloudflare Tunnel** para acesso externo
- **GHCR** (GitHub Container Registry) para imagens Docker
- **GitHub Actions** reusable workflows para CI/CD

Os ficheiros `docker-compose.yml` (infra partilhada) e `docker-compose.apps.yml` (aplicações) **devem ser usados em conjunto** para rede e dependências corretas (ex.: API financeiro → Redis + Postgres).

```bash
docker compose -f docker-compose.yml -f docker-compose.apps.yml up -d
```

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
# Editar .env: POSTGRES_PASSWORD, REDIS_PASSWORD, tokens, FINANCEIRO_*, GITHUB_USER, etc.
docker compose -f docker-compose.yml -f docker-compose.apps.yml up -d
```

## Comandos Úteis

```bash
cd /opt/homelab/docker

# Status de toda a stack
docker compose -f docker-compose.yml -f docker-compose.apps.yml ps

# Logs
docker compose -f docker-compose.yml -f docker-compose.apps.yml logs -f musicas-igreja-api

# Atualizar um serviço (igual ao deploy via GitHub Actions)
docker compose -f docker-compose.yml -f docker-compose.apps.yml pull musicas-igreja-api
docker compose -f docker-compose.yml -f docker-compose.apps.yml up -d musicas-igreja-api

# Backup
../scripts/backup.sh

# Restore
../scripts/restore.sh
```

## Cloudflare Tunnel (dashboard)

Rotas públicas configuram-se no **dashboard Cloudflare** (Zero Trust → Tunnels), não via ficheiros YAML deste repositório.

Para o **Gerenciamento Financeiro** web, o contentor Nginx escuta na porta **8080**. No mapeamento do hostname (ex.: `financeiro.seudominio.com`), o URL de origem interno deve ser `http://gerenciamento-financeiro-web:8080` (rede Docker onde o `cloudflared` corre), **não** `:80`.

## Adicionar Novo Projeto

1. Adicionar database e user nos init scripts (`docker/postgres/init/`)
2. Adicionar variáveis em `docker/.env.example` e `.env` no servidor
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
