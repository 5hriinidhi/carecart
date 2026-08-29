#!/bin/sh
# Runs once, on first Postgres cluster init (see docker-compose.yml volume
# mounts). Creates the least-privilege `carecart_app` role the backend connects
# as (Phase 6.2 audit F1). The SQL itself lives at backend/scripts/create_app_role.sql
# and is mounted read-only at /opt/carecart/.
#
# For an ALREADY-initialised database, run it by hand instead:
#   docker compose exec -e APP_DB_PASSWORD=... postgres \
#     sh /docker-entrypoint-initdb.d/10-app-role.sh
set -e

if [ -z "${APP_DB_PASSWORD:-}" ]; then
  echo "[db-init] APP_DB_PASSWORD not set - skipping carecart_app role creation." >&2
  echo "[db-init] the backend will fall back to the POSTGRES_USER connection." >&2
  exit 0
fi

echo "[db-init] creating/refreshing the least-privilege carecart_app role ..."
psql -v ON_ERROR_STOP=1 \
     -v app_pw="$APP_DB_PASSWORD" \
     --username "$POSTGRES_USER" \
     --dbname "$POSTGRES_DB" \
     -f /opt/carecart/create_app_role.sql
echo "[db-init] carecart_app ready (DML only, no DDL / no superuser)."
