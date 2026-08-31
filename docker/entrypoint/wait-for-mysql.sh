#!/bin/sh
# Tunggu MySQL siap menerima koneksi. Compose sudah memakai
# depends_on: service_healthy, ini lapis pengaman kedua untuk kasus
# restart mandiri di mana MySQL belum sempat naik.
set -eu

HOST="${DB_HOST:-mysql}"
PORT="${DB_PORT:-3306}"
USER="${DB_USER:-skyfire}"
PASS="${DB_PASSWORD:-}"
TIMEOUT="${DB_WAIT_TIMEOUT:-180}"

echo "Menunggu MySQL di ${HOST}:${PORT} (timeout ${TIMEOUT}s)..."
elapsed=0
while [ "$elapsed" -lt "$TIMEOUT" ]; do
    if mysqladmin ping -h "$HOST" -P "$PORT" -u "$USER" -p"$PASS" --silent >/dev/null 2>&1; then
        echo "MySQL siap setelah ${elapsed}s."
        exit 0
    fi
    sleep 3
    elapsed=$((elapsed + 3))
done

echo "FATAL: MySQL tidak siap setelah ${TIMEOUT}s." >&2
exit 1
