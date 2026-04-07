# Configuração da VM no Proxmox

Guia completo para criar e configurar a VM Debian 12 no Proxmox VE para hospedar o homelab.

> Para configuração do GitHub (branch protection, secrets, CI/CD), veja [github-setup.md](github-setup.md).

---

## 1. Criar a VM no Proxmox

### 1.1 Baixar a ISO

1. Acessar o Proxmox pelo navegador (`https://IP_DO_PROXMOX:8006`)
2. No menu lateral, clicar no storage `local`
3. Ir em **ISO Images** > **Download from URL**
4. Colar a URL da ISO do Debian 12 (netinst):
   ```
   https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.9.0-amd64-netinst.iso
   ```
5. Clicar em **Download**

### 1.2 Criar a VM

1. Clicar em **Create VM** (canto superior direito)
2. Preencher as configurações:

| Aba | Campo | Valor |
|-----|-------|-------|
| **General** | Name | `homelab` |
| **OS** | ISO image | `debian-12.x.x-amd64-netinst.iso` |
| **System** | BIOS | Default (SeaBIOS) |
| **System** | Qemu Agent | Habilitado |
| **Disks** | Disk size | `40 GB` |
| **Disks** | Storage | O SSD disponível |
| **CPU** | Sockets | `1` |
| **CPU** | Cores | `2` |
| **CPU** | Type | `host` |
| **Memory** | Memory | `4096` MB |
| **Network** | Bridge | `vmbr0` |
| **Network** | Model | VirtIO (paravirtualized) |

3. Confirmar e **não iniciar ainda**

---

## 2. Instalar Debian 12

1. Iniciar a VM e abrir o console
2. Selecionar **Install** (não graphical)
3. Seguir o instalador:

| Etapa | Valor |
|-------|-------|
| Idioma | Portuguese (Brazil) ou English |
| Localização | Brazil |
| Teclado | Português Brasileiro (ou o que usar) |
| Hostname | `homelab` |
| Domínio | (deixar vazio) |
| Senha root | Definir uma senha forte |
| Novo usuário | Criar um usuário (ex: `deploy`) |
| Particionamento | Guiado - usar disco inteiro |
| Esquema de partição | Todos os arquivos em uma partição |

4. Na seleção de software:
   - **Desmarcar** Desktop Environment e print server
   - **Marcar** SSH server
   - **Marcar** standard system utilities
5. Instalar GRUB no disco principal
6. Finalizar e reiniciar

---

## 3. Configurar IP Estático

Após o boot, fazer login como root no console do Proxmox.

### 3.1 Identificar a interface de rede

```bash
ip link show
```

A interface será algo como `ens18` ou `eth0`.

### 3.2 Editar a configuração de rede

```bash
nano /etc/network/interfaces
```

Substituir o bloco da interface (ex: `ens18`) por:

```
auto ens18
iface ens18 inet static
    address 10.0.0.100
    netmask 255.255.255.0
    gateway 10.0.0.1
    dns-nameservers 1.1.1.1 1.0.0.1
```

### 3.3 Aplicar as alterações

```bash
systemctl restart networking
```

### 3.4 Verificar conectividade

```bash
ip addr show ens18
ping -c 3 1.1.1.1
ping -c 3 google.com
```

> A partir daqui, pode acessar via SSH do seu PC: `ssh deploy@10.0.0.100`

---

## 4. Configurar SSH

### 4.1 Acesso por senha (já funciona após instalação)

Do Windows (PowerShell):

```powershell
ssh deploy@10.0.0.100
```

### 4.2 Gerar chave SSH no Windows

Se ainda não tiver uma chave SSH:

```powershell
ssh-keygen -t ed25519 -C "seu-email@exemplo.com"
```

Aceitar o caminho padrão (`C:\Users\SEU_USER\.ssh\id_ed25519`).

### 4.3 Copiar a chave para a VM

```powershell
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh deploy@10.0.0.100 "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && chmod 700 ~/.ssh"
```

Testar o login sem senha:

```powershell
ssh deploy@10.0.0.100
```

### 4.4 Desabilitar autenticação por senha

Na VM (como root):

```bash
nano /etc/ssh/sshd_config
```

Alterar/adicionar:

```
PasswordAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
```

Reiniciar o SSH:

```bash
systemctl restart sshd
```

> **Importante:** Testar em uma nova janela ANTES de fechar a sessão atual, para não ficar trancado fora.

---

## 5. Configurar Firewall (UFW)

```bash
sudo apt install -y ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp    # SSH
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS
sudo ufw enable
```

Verificar status:

```bash
sudo ufw status verbose
```

---

## 6. Atualizar Sistema e Instalar Dependências

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl sudo
```

Adicionar o usuário ao grupo sudo (se não estiver):

```bash
su - root
usermod -aG sudo deploy
exit
```

Fazer logout e login novamente para o grupo ter efeito.

---

## 7. Instalar Docker e Docker Compose

```bash
curl -fsSL https://get.docker.com | sh
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker $USER
```

**Fazer logout e login novamente** para o grupo `docker` ter efeito.

Verificar a instalação:

```bash
docker --version
docker compose version
```

---

## 8. Clonar Repositório e Configurar

```bash
sudo mkdir -p /opt/homelab
sudo chown $USER:$USER /opt/homelab
git clone https://github.com/SEU_USUARIO/homelab-infra.git /opt/homelab
cd /opt/homelab/docker
cp .env.example .env
```

Editar o `.env` com valores reais:

```bash
nano .env
```

Variáveis que precisam ser preenchidas:

| Variável | Descrição |
|----------|-----------|
| `GITHUB_USER` | Seu username do GitHub |
| `POSTGRES_HOST_PORT` | Porta do PostgreSQL (padrão: `5432`) |
| `POSTGRES_PASSWORD` | Senha do superuser PostgreSQL |
| `CLOUDFLARE_TUNNEL_TOKEN` | Token do Cloudflare Tunnel (seção 10) |
| `MUSICAS_DB_USER` | Usuário do banco musicas (ex: `musicas_user`) |
| `MUSICAS_DB_PASSWORD` | Senha do banco musicas |
| `PASTORAL_DB_USER` | Usuário do banco pastoral |
| `PASTORAL_DB_PASSWORD` | Senha do banco pastoral |
| `FINANCEIRO_DB_USER` | Usuário do banco financeiro |
| `FINANCEIRO_DB_PASSWORD` | Senha do banco financeiro |
| `FINANCEIRO_COOKIE_DOMAIN` | Domínio do cookie de sessão (ex: `financeiro.seudominio.com`) |
| `AULAS_DB_USER` | Usuário do banco aulas (ex: `aulas_user`) |
| `AULAS_DB_PASSWORD` | Senha do banco aulas |
| `AULAS_COOKIE_DOMAIN` | Domínio do cookie de sessão (ex: `aulas.seudominio.com`) |

---

## 9. Autenticar no GHCR

Criar um Personal Access Token (PAT) no GitHub:

1. GitHub > Settings > Developer settings > Personal access tokens > Tokens (classic)
2. Gerar novo token com scope `read:packages`
3. Copiar o token

Na VM:

```bash
echo "SEU_TOKEN" | docker login ghcr.io -u SEU_USUARIO --password-stdin
```

> Para mais detalhes sobre configuração do GitHub, veja [github-setup.md](github-setup.md).

---

## 10. Configurar Cloudflare Tunnel

### 10.1 Criar o Tunnel

1. Acessar [Cloudflare Zero Trust](https://one.dash.cloudflare.com/)
2. Ir em **Networks** > **Tunnels**
3. Clicar em **Create a tunnel**
4. Dar um nome (ex: `homelab`)
5. Copiar o **token** gerado

### 10.2 Salvar o token

Editar o `.env` e colar o token:

```bash
cd /opt/homelab/docker
nano .env
```

```
CLOUDFLARE_TUNNEL_TOKEN=eyJhIjoixxxx...
```

### 10.3 Configurar os hostnames

No dashboard do Cloudflare (mesmo tunnel), adicionar **Public Hostnames**:

| Subdomain | Tipo | URL (Service) |
|-----------|------|---------------|
| `financeiro.seudominio.com` | HTTP | `gerenciamento-financeiro-web:80` |
| `musicas.seudominio.com` | HTTP | `musicas-igreja-web:80` |
| `pastoral.seudominio.com` | HTTP | `gerenciamento-pastoral-web:80` |
| `aulas.seudominio.com` | HTTP | `gestao-aulas-web:80` |
| `portfolio.seudominio.com` | HTTP | `portfolio:80` |
| `logs.seudominio.com` | HTTP | `homelab-dozzle:8080` |
| `db.seudominio.com` | HTTP | `homelab-adminer:8080` |
| `home.seudominio.com` | HTTP | `homelab-homepage:3000` |

Os nomes dos serviços correspondem aos `container_name` nos arquivos docker-compose.

> As aplicações web já fazem proxy reverso para a API internamente via nginx (`/api/` -> API container), então não é necessário expor a API separadamente.

---

## 11. Instalar GitHub Actions Self-Hosted Runner

O CI/CD usa um runner self-hosted que roda diretamente no servidor para fazer pull das imagens e reiniciar containers.

### 11.1 Criar o runner no GitHub

1. Ir em **Settings** > **Actions** > **Runners** no repositório `homelab-infra` (ou na organização, para compartilhar entre repos)
2. Clicar em **New self-hosted runner**
3. Selecionar **Linux** e **x64**
4. Seguir os comandos exibidos na tela (resumidos abaixo)

### 11.2 Instalar no servidor

```bash
mkdir -p ~/actions-runner && cd ~/actions-runner

curl -o actions-runner-linux-x64.tar.gz -L \
  https://github.com/actions/runner/releases/latest/download/actions-runner-linux-x64-2.321.0.tar.gz

tar xzf ./actions-runner-linux-x64.tar.gz

./config.sh --url https://github.com/SEU_USUARIO/homelab-infra --token SEU_TOKEN
```

> O token e a URL exatos são exibidos na página do GitHub ao criar o runner. Use os valores de lá.

### 11.3 Configurar como serviço

```bash
sudo ./svc.sh install
sudo ./svc.sh start
sudo ./svc.sh status
```

O runner agora inicia automaticamente com o sistema e executa os jobs `runs-on: self-hosted`.

### 11.4 Verificar

De volta ao GitHub, em **Settings** > **Actions** > **Runners**, o runner deve aparecer como **Idle** (online).

---

## 12. Subir Serviços

```bash
cd /opt/homelab/docker

# Stack completa: PostgreSQL, Redis, Cloudflare Tunnel e apps (use sempre os dois ficheiros)
docker compose -f docker-compose.yml -f docker-compose.apps.yml up -d

# Ou apenas alguns serviços (ex.: musicas-igreja)
docker compose -f docker-compose.yml -f docker-compose.apps.yml up -d musicas-igreja-api musicas-igreja-web
```

Verificar se tudo está rodando:

```bash
docker compose -f docker-compose.yml -f docker-compose.apps.yml ps
```

---

## 13. Configurar Backup Automático

Agendar backup diário às 3h da manhã:

```bash
sudo crontab -e
```

Adicionar a linha:

```
0 3 * * * /opt/homelab/scripts/backup.sh >> /var/log/homelab-backup.log 2>&1
```

Para executar um backup manual:

```bash
/opt/homelab/scripts/backup.sh
```

Os backups ficam em `/opt/homelab/backups/` com retenção de 30 dias.

---

## 14. Comandos Úteis

```bash
cd /opt/homelab/docker

# Status de todos os containers
docker compose -f docker-compose.yml -f docker-compose.apps.yml ps

# Logs em tempo real
docker compose -f docker-compose.yml -f docker-compose.apps.yml logs -f postgres
docker compose -f docker-compose.yml -f docker-compose.apps.yml logs -f musicas-igreja-api

# Reiniciar um serviço
docker compose -f docker-compose.yml -f docker-compose.apps.yml restart musicas-igreja-api

# Atualizar imagem e reiniciar
docker compose -f docker-compose.yml -f docker-compose.apps.yml pull musicas-igreja-api
docker compose -f docker-compose.yml -f docker-compose.apps.yml up -d musicas-igreja-api

# Atualizar stack (após git pull)
cd /opt/homelab
git pull
cd docker
docker compose -f docker-compose.yml -f docker-compose.apps.yml up -d

# Parar tudo (atenção: remove contentores da stack merge)
docker compose -f docker-compose.yml -f docker-compose.apps.yml down

# Backup manual
/opt/homelab/scripts/backup.sh

# Restore
/opt/homelab/scripts/restore.sh

# Ver uso de disco dos volumes
docker system df -v

# Limpar imagens não utilizadas
docker image prune -f
```

---

## Instalação do QEMU Guest Agent (Opcional)

Para melhor integração com o Proxmox (shutdown graceful, info de IP, etc.):

```bash
sudo apt install -y qemu-guest-agent
sudo systemctl enable qemu-guest-agent
sudo systemctl start qemu-guest-agent
```
