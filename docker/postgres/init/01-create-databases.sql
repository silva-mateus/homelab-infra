-- Each project gets its own database within the shared PostgreSQL instance.

CREATE DATABASE musicas_igreja
  ENCODING 'UTF8'
  LC_COLLATE 'en_US.utf8'
  LC_CTYPE 'en_US.utf8';

CREATE DATABASE gerenciamento_pastoral
  ENCODING 'UTF8'
  LC_COLLATE 'en_US.utf8'
  LC_CTYPE 'en_US.utf8';

CREATE DATABASE gerenciamento_financeiro
  ENCODING 'UTF8'
  LC_COLLATE 'en_US.utf8'
  LC_CTYPE 'en_US.utf8';

CREATE DATABASE gestao_aulas
  ENCODING 'UTF8'
  LC_COLLATE 'en_US.utf8'
  LC_CTYPE 'en_US.utf8';
