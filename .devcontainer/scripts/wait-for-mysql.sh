#!/usr/bin/env bash
set -euo pipefail

MYSQL_HOST=${MYSQL_HOST:-mysql}
MYSQL_PORT=${MYSQL_PORT:-3306}
MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD:-devcontainer}
MYSQL_INIT_TIMEOUT=${MYSQL_INIT_TIMEOUT:-120}

end=$((SECONDS + MYSQL_INIT_TIMEOUT))
while (( SECONDS < end )); do
  if MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" mysqladmin ping \
      --protocol=tcp \
      -h "${MYSQL_HOST}" \
      -P "${MYSQL_PORT}" \
      -u root \
      --skip-ssl \
      --silent; then
    echo "[devcontainer] MySQL is ready."
    exit 0
  fi

  sleep 2
done

echo "[devcontainer] MySQL did not become available within ${MYSQL_INIT_TIMEOUT}s" >&2
exit 1
