-- Core System: User creation and privileges
-- Each project gets a dedicated user with access only to its own database.
-- Passwords are set via environment variables in docker-compose.

-- Musicas Igreja
CREATE USER IF NOT EXISTS 'musicas_user'@'%' IDENTIFIED BY 'change-me-musicas';
GRANT ALL PRIVILEGES ON musicas_igreja.* TO 'musicas_user'@'%';

-- Gerenciamento Pastoral
CREATE USER IF NOT EXISTS 'pastoral_user'@'%' IDENTIFIED BY 'change-me-pastoral';
GRANT ALL PRIVILEGES ON gerenciamento_pastoral.* TO 'pastoral_user'@'%';

-- Gerenciamento Financeiro
CREATE USER IF NOT EXISTS 'financeiro_user'@'%' IDENTIFIED BY 'change-me-financeiro';
GRANT ALL PRIVILEGES ON gerenciamento_financeiro.* TO 'financeiro_user'@'%';

-- Add new project users below:
-- CREATE USER IF NOT EXISTS 'novo_user'@'%' IDENTIFIED BY 'change-me';
-- GRANT ALL PRIVILEGES ON novo_projeto.* TO 'novo_user'@'%';

FLUSH PRIVILEGES;
