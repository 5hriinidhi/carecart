#!/bin/sh
# Container entrypoint: apply DB migrations, then run the given command.
# Set AUTO_MIGRATE=0 to skip (e.g. if migrations are run as a separate job).
set -e

if [ "${AUTO_MIGRATE:-1}" != "0" ]; then
  echo "[entrypoint] alembic upgrade head ..."
  n=0
  until alembic upgrade head; do
    n=$((n + 1))
    if [ "$n" -ge 10 ]; then
      echo "[entrypoint] migrations failed after $n attempts" >&2
      exit 1
    fi
    echo "[entrypoint] retry $n/10 in 2s (waiting for DB) ..."
    sleep 2
  done
  echo "[entrypoint] migrations up to date."
fi

exec "$@"
