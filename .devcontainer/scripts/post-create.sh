#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

echo "[devcontainer] Waiting for MySQL to become ready..."
"${SCRIPT_DIR}/wait-for-mysql.sh"

echo "[devcontainer] Provisioning development and test databases..."
"${SCRIPT_DIR}/provision-mysql.sh"

cd "${REPO_ROOT}"

echo "[devcontainer] Installing bundle dependencies (if needed)..."
bundle check || bundle install

cat <<'MSG'

Devcontainer is ready.

Next steps inside the container:
  * bin/test-unit        # baseline sqlite run
  * bin/test-integration # integration suite
  * mysql --host mysql --user rails --password=rails --skip-ssl --execute "SHOW DATABASES LIKE 'activerecord_tenanted_%';"
MSG
