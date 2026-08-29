-- Least-privilege application role (Phase 6.2 audit, finding F1).
--
-- The app must NOT connect as the database owner / superuser. This creates a
-- `carecart_app` login role that can only run DML (SELECT/INSERT/UPDATE/DELETE)
-- on the application tables -- it cannot CREATE/DROP/ALTER, create roles or
-- databases, read pg_authid, or COPY ... TO PROGRAM. Migrations keep running as
-- the owner (a separate, privileged connection string).
--
-- Idempotent. Run it as the database owner against the app database:
--
--   psql "$MIGRATION_DATABASE_URL" \
--        -v app_pw="$APP_DB_PASSWORD" \
--        -f backend/scripts/create_app_role.sql
--
-- Then point the app at it:  APP_DATABASE_URL=postgresql+psycopg://carecart_app:<pw>@host:5432/carecart
-- (docker-compose wires this up automatically via infra/db-init/, see docker-compose.yml)

\set ON_ERROR_STOP on

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'carecart_app') THEN
    CREATE ROLE carecart_app LOGIN
      NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION;
  END IF;
END
$$;

-- (re)set the password each run so a rotated APP_DB_PASSWORD takes effect
ALTER ROLE carecart_app WITH PASSWORD :'app_pw';

-- see the schema, nothing more (CONNECT is already granted to PUBLIC by default)
GRANT USAGE ON SCHEMA public TO carecart_app;

-- DML on everything that exists now
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO carecart_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO carecart_app;

-- and on everything the owner creates later (future migrations)
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO carecart_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO carecart_app;

-- explicitly deny schema-level DDL (default in PG15+ for non-owners, made explicit)
REVOKE CREATE ON SCHEMA public FROM carecart_app;
