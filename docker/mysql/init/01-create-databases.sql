-- Core System: Database initialization
-- Each project gets its own database within the shared MySQL instance.

CREATE DATABASE IF NOT EXISTS musicas_igreja
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

CREATE DATABASE IF NOT EXISTS gerenciamento_pastoral
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

CREATE DATABASE IF NOT EXISTS gerenciamento_financeiro
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

-- Add new project databases below:
-- CREATE DATABASE IF NOT EXISTS novo_projeto
--   CHARACTER SET utf8mb4
--   COLLATE utf8mb4_unicode_ci;
