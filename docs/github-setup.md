# Configuração do GitHub (Segurança e CI/CD)

Guia para configurar proteção de branch, secrets e CI/CD nos repositórios do homelab.

> Para configuração da VM no Proxmox, veja [proxmox-setup.md](proxmox-setup.md).

---

## 1. Proteção de Branch

Configurar no repositório `homelab-infra` e em cada repositório de app.

### Passo a passo

1. Ir em **Settings** > **Branches**
2. Em **Branch protection rules**, clicar em **Add rule**
3. Em **Branch name pattern**, digitar `main`
4. Marcar:
   - **Require a pull request before merging**
   - **Do not allow bypassing the above settings** (opcional, mas recomendado)
5. Clicar em **Create**

Isso impede push direto na `main` e exige que todas as alterações passem por Pull Request.

---

## 2. Configurar Secrets

Os secrets são usados pelos workflows de CI/CD para fazer deploy via SSH no servidor.

### Secrets necessários

| Secret | Valor | Onde é usado |
|--------|-------|--------------|
| `DEPLOY_SSH_KEY` | Chave privada SSH (conteúdo do arquivo `id_ed25519`) | Deploy via SSH |
| `DEPLOY_HOST` | IP do servidor (ex: `10.0.0.100`) | Deploy via SSH |
| `DEPLOY_USER` | Usuário SSH (ex: `deploy`) | Deploy via SSH |

### Como criar os secrets

1. No repositório, ir em **Settings** > **Secrets and variables** > **Actions**
2. Clicar em **New repository secret**
3. Preencher **Name** e **Secret**
4. Clicar em **Add secret**

### Gerar chave SSH dedicada para deploy

É recomendado usar uma chave SSH separada para o CI/CD, não a mesma do acesso pessoal.

No seu PC (PowerShell):

```powershell
ssh-keygen -t ed25519 -C "github-actions-deploy" -f $env:USERPROFILE\.ssh\id_deploy
```

Copiar a chave pública para a VM:

```powershell
type $env:USERPROFILE\.ssh\id_deploy.pub | ssh deploy@10.0.0.100 "cat >> ~/.ssh/authorized_keys"
```

Copiar o conteúdo da chave **privada** para usar como secret:

```powershell
type $env:USERPROFILE\.ssh\id_deploy
```

Copiar todo o conteúdo (incluindo `-----BEGIN` e `-----END`) e colar como valor do secret `DEPLOY_SSH_KEY`.

### Onde configurar os secrets

Os secrets precisam ser configurados em **cada repositório** que faz deploy:

- `homelab-infra` (para o workflow de infra)
- `musicas-igreja` (ou o repo do app, para o workflow de deploy do app)

Se preferir, pode usar **Organization secrets** para compartilhar entre repos.

---

## 3. CI/CD do homelab-infra

O repositório `homelab-infra` tem seu próprio workflow que valida os arquivos e faz deploy ao dar push na `main`.

### Arquivo: `.github/workflows/ci.yml`

O workflow faz:

1. **Validação** (em PRs e push na main):
   - Verifica se os `docker-compose.yml` são válidos
   - Roda ShellCheck nos scripts bash
2. **Deploy** (apenas push na main, após validação):
   - Conecta via SSH no servidor
   - Faz `git pull` e `docker compose up -d`

### Fluxo

```
Push/PR na main
       │
       ▼
  ┌──────────┐
  │ Validate  │── docker compose config
  │           │── ShellCheck
  └────┬─────┘
       │ (só push na main)
       ▼
  ┌──────────┐
  │  Deploy   │── SSH no servidor
  │           │── git pull + docker compose up -d
  └──────────┘
```

---

## 4. CI/CD dos Apps (Exemplo: musicas-igreja)

Cada repositório de app usa o **reusable workflow** definido em `homelab-infra` para build e deploy.

### Reusable workflow

O workflow `homelab-infra/.github/workflows/reusable-deploy.yml` faz:

1. Build da imagem Docker
2. Push para o GHCR (GitHub Container Registry)
3. Deploy via SSH (pull da nova imagem + restart do container)

### Configuração no repositório do app

Criar o arquivo `.github/workflows/deploy.yml` no repositório do app (ex: `musicas-igreja`):

```yaml
name: Deploy

on:
  push:
    branches: [main]

jobs:
  deploy-api:
    uses: SEU_USUARIO/homelab-infra/.github/workflows/reusable-deploy.yml@main
    with:
      service_name: musicas-igreja-api
      dockerfile_path: ./src/Api/Dockerfile
      context: .
    secrets:
      DEPLOY_SSH_KEY: ${{ secrets.DEPLOY_SSH_KEY }}
      DEPLOY_HOST: ${{ secrets.DEPLOY_HOST }}
      DEPLOY_USER: ${{ secrets.DEPLOY_USER }}

  deploy-web:
    uses: SEU_USUARIO/homelab-infra/.github/workflows/reusable-deploy.yml@main
    with:
      service_name: musicas-igreja-web
      dockerfile_path: ./src/Web/Dockerfile
      context: .
    secrets:
      DEPLOY_SSH_KEY: ${{ secrets.DEPLOY_SSH_KEY }}
      DEPLOY_HOST: ${{ secrets.DEPLOY_HOST }}
      DEPLOY_USER: ${{ secrets.DEPLOY_USER }}
```

### Inputs do reusable workflow

| Input | Descrição | Exemplo |
|-------|-----------|---------|
| `service_name` | Nome do serviço no `docker-compose.apps.yml` | `musicas-igreja-api` |
| `dockerfile_path` | Caminho do Dockerfile no repo | `./src/Api/Dockerfile` |
| `context` | Contexto do build Docker | `.` |

### Secrets necessários no repo do app

Mesmos secrets da seção 2: `DEPLOY_SSH_KEY`, `DEPLOY_HOST`, `DEPLOY_USER`.

### Fluxo completo

```
Push na main (repo do app)
       │
       ▼
  ┌───────────────┐
  │ Build & Push   │── Build imagem Docker
  │                │── Push para ghcr.io
  │                │── Tags: latest + sha do commit
  └───────┬───────┘
          │
          ▼
  ┌───────────────┐
  │    Deploy      │── SSH no servidor
  │                │── docker compose pull <service>
  │                │── docker compose up -d <service>
  │                │── docker image prune -f
  └───────────────┘
```

### Tags das imagens

O workflow gera duas tags para cada build:

- `ghcr.io/SEU_USUARIO/musicas-igreja-api:latest`
- `ghcr.io/SEU_USUARIO/musicas-igreja-api:<sha-do-commit>`

A tag `latest` é usada pelo `docker-compose.apps.yml`. A tag com SHA permite rollback para uma versão específica.

### Rollback manual

Se precisar voltar para uma versão anterior:

```bash
cd /opt/homelab/docker

# Ver tags disponíveis
docker pull ghcr.io/SEU_USUARIO/musicas-igreja-api:abc1234

# Ou editar o compose temporariamente para usar uma tag fixa
docker compose -f docker-compose.apps.yml up -d musicas-igreja-api
```

---

## 5. Checklist Completa

### Para o homelab-infra

- [ ] Criar secrets: `DEPLOY_SSH_KEY`, `DEPLOY_HOST`, `DEPLOY_USER`
- [ ] Configurar branch protection na `main`
- [ ] Verificar que o workflow `ci.yml` está rodando

### Para cada novo app

- [ ] Criar secrets: `DEPLOY_SSH_KEY`, `DEPLOY_HOST`, `DEPLOY_USER`
- [ ] Configurar branch protection na `main`
- [ ] Criar `.github/workflows/deploy.yml` usando o reusable workflow
- [ ] Garantir que o Dockerfile existe no caminho configurado
- [ ] Adicionar o serviço em `homelab-infra/docker/docker-compose.apps.yml`
- [ ] Adicionar database/user nos init scripts do PostgreSQL
- [ ] Configurar hostname no Cloudflare Tunnel
