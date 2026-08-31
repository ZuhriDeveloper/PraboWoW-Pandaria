#!/bin/sh
# =============================================================================
# Entrypoint tunggal untuk kedua server. Compose memilih peran lewat `command`:
#   command: ["worldserver"]
#   command: ["authserver"]
#
# Semua .conf dihasilkan di dalam container dari env var setiap kali start,
# jadi kredensial tidak pernah masuk ke repo maupun ke image.
# =============================================================================
set -eu

ROLE="${1:-worldserver}"

case "$ROLE" in
    worldserver|authserver) ;;
    *) exec "$@" ;;                 # escape hatch: `docker run ... bash`
esac

# Core mem-parse connection string dengan memecah di ';'
# (LoginDatabaseInfo = "host;port;user;pass;db"). Password yang mengandung ';'
# menghasilkan field berlebih, dan gejalanya menyesatkan: server start normal
# lalu gagal autentikasi ke database dengan pesan yang tidak menyebut password.
# `openssl rand -base64 32` tidak pernah menghasilkan ';', tapi password yang
# diketik manual bisa.
case "${DB_PASSWORD:-}" in
    *";"*)
        echo "FATAL: DB_PASSWORD mengandung ';'." >&2
        echo "Core memecah connection string di karakter itu, jadi password akan" >&2
        echo "terpotong. Pakai password tanpa ';' -- mis. \`openssl rand -base64 32\`." >&2
        exit 1
        ;;
esac

render-config.sh "$ROLE"
wait-for-mysql.sh

if [ "$ROLE" = "authserver" ]; then
    # authserver-lah yang membuat schema auth (LoginDatabase.AutoSetup=1), jadi
    # tabel realmlist belum tentu ada sekarang. Tulis barisnya di background
    # dengan retry, jangan blokir startup.
    configure-realm.sh &
else
    # worldserver menunggu authserver sehat (depends_on), jadi schema auth
    # sudah ada. Tulis realmlist secara sinkron supaya baris sudah benar
    # sebelum worldserver membacanya saat start.
    configure-realm.sh

    bootstrap-world-db.sh

    DATA="${DATA_DIR_CONTAINER:-/opt/skyfire/data}"
    missing=""
    for d in dbc maps vmaps mmaps; do
        [ -d "${DATA}/${d}" ] || missing="${missing} ${d}"
    done
    if [ -n "$missing" ]; then
        echo "FATAL: folder data client hilang di ${DATA}:${missing}" >&2
        echo "Ekstrak dengan tools/extract-client-data.ps1 lalu unggah dengan" >&2
        echo "tools/upload-client-data.sh." >&2
        exit 1
    fi
fi

chown -R skyfire:skyfire /opt/skyfire/etc /opt/skyfire/logs /opt/skyfire/tdb 2>/dev/null || true

echo "Menjalankan ${ROLE}..."
exec gosu skyfire "/opt/skyfire/bin/${ROLE}" -c "/opt/skyfire/etc/${ROLE}.conf"
