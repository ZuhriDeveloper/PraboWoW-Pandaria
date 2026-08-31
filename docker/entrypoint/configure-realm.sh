#!/bin/sh
# =============================================================================
# Menulis baris realmlist ke database auth.
#
# Dua hal yang diperbaiki di sini sekaligus:
#   1. auth_database.sql:362 men-seed realm dengan address 127.0.0.1. Kalau
#      dibiarkan, client berhasil login lalu tersangkut selamanya di character
#      screen karena diarahkan ke localhost miliknya sendiri.
#   2. worldserver.conf.dist ship RealmID=0 sedangkan baris seed ber-id 1.
#      Config kita memakai ${REALM_ID}; baris di DB dibuat dengan id yang sama.
#
# Idempoten (upsert), aman dipanggil di setiap start.
# =============================================================================
set -eu

DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-3306}"
DB_USER="${DB_USER:-skyfire}"
DB_PASSWORD="${DB_PASSWORD:?DB_PASSWORD wajib diisi}"
DB_AUTH="${DB_AUTH:-auth}"

REALM_ID="${REALM_ID:-1}"
REALM_NAME="${REALM_NAME:-PraboWoW Pandaria}"
REALM_ADDRESS="${REALM_ADDRESS:?REALM_ADDRESS wajib diisi}"
REALM_PORT="${REALM_PORT:-8085}"
GAMEBUILD=18414

WAIT_SECONDS="${REALM_CONFIG_TIMEOUT:-600}"

case "$REALM_ADDRESS" in
    127.0.0.1|localhost|0.0.0.0|::1)
        echo "FATAL: REALM_ADDRESS='${REALM_ADDRESS}'." >&2
        echo "Client akan login sukses tapi tersangkut di character screen." >&2
        echo "Isi dengan IP publik atau hostname VPS (DNS only, jangan proxied)." >&2
        exit 1
        ;;
esac

mysql_run() { mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" "$@"; }

echo "[realm] Menunggu ${DB_AUTH}.realmlist (maks ${WAIT_SECONDS}s)..."
elapsed=0
while [ "$elapsed" -lt "$WAIT_SECONDS" ]; do
    if mysql_run -N -B -e \
        "SELECT COUNT(*) FROM information_schema.tables
          WHERE table_schema='${DB_AUTH}' AND table_name='realmlist'" 2>/dev/null | grep -q '^1$'; then
        break
    fi
    sleep 5
    elapsed=$((elapsed + 5))
done

if [ "$elapsed" -ge "$WAIT_SECONDS" ]; then
    echo "FATAL: ${DB_AUTH}.realmlist tidak muncul setelah ${WAIT_SECONDS}s." >&2
    echo "Cek log authserver -- setup database auth kemungkinan gagal." >&2
    exit 1
fi

mysql_run "$DB_AUTH" <<SQL
INSERT INTO \`realmlist\`
    (\`id\`, \`name\`, \`address\`, \`localAddress\`, \`localSubnetMask\`,
     \`port\`, \`icon\`, \`flag\`, \`timezone\`, \`allowedSecurityLevel\`,
     \`population\`, \`gamebuild\`)
VALUES
    (${REALM_ID}, '${REALM_NAME}', '${REALM_ADDRESS}', '${REALM_ADDRESS}',
     '255.255.255.0', ${REALM_PORT}, 0, 0, 0, 0, 0, ${GAMEBUILD})
ON DUPLICATE KEY UPDATE
    \`name\`         = VALUES(\`name\`),
    \`address\`      = VALUES(\`address\`),
    \`localAddress\` = VALUES(\`localAddress\`),
    \`port\`         = VALUES(\`port\`),
    \`gamebuild\`    = VALUES(\`gamebuild\`);
SQL

echo "[realm] realm ${REALM_ID} -> ${REALM_ADDRESS}:${REALM_PORT} (build ${GAMEBUILD})"
