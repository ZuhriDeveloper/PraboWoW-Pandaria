#!/bin/sh
# =============================================================================
# Menyiapkan dump world DB sebelum worldserver start.
#
# Dump world SkyFire beberapa GB dan tidak ada di repo core (worldserver.conf
# menyebutnya "intentionally external"). Ia juga tidak dimasukkan ke image:
# image harus tetap kecil dan bisa di-rebuild tanpa mengunduh ulang beberapa GB.
#
# Jadi: unduh sekali ke volume, hanya kalau world DB memang masih kosong.
# Setelah core mengimpornya, file ini boleh dihapus (volume tdb aman dibuang).
# =============================================================================
set -eu

DB_HOST="${DB_HOST:-db}"
DB_PORT="${DB_PORT:-3306}"
DB_USER="${DB_USER:-skyfire}"
DB_PASSWORD="${DB_PASSWORD:?DB_PASSWORD wajib diisi}"
DB_WORLD="${DB_WORLD:-world}"

DUMP="${WORLD_DUMP_CONTAINER:-/opt/skyfire/tdb/world_database.sql}"
URL="${WORLD_DB_URL:-}"

mysql_run() { mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" -p"$DB_PASSWORD" "$@"; }

tables=$(mysql_run -N -B -e \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='${DB_WORLD}'" 2>/dev/null || echo 0)

if [ "${tables:-0}" -gt 0 ]; then
    echo "[world-db] Database '${DB_WORLD}' sudah berisi ${tables} tabel; lewati unduhan."
    # Hemat ruang: dump hanya berguna untuk DB kosong.
    [ -f "$DUMP" ] && echo "[world-db] Catatan: ${DUMP} masih ada dan aman dihapus."
    exit 0
fi

if [ -f "$DUMP" ]; then
    echo "[world-db] Memakai dump yang sudah ada: ${DUMP} ($(du -h "$DUMP" | cut -f1))"
    exit 0
fi

if [ -z "$URL" ]; then
    cat >&2 <<'MSG'
FATAL: database world kosong dan WORLD_DB_URL tidak diisi.

Ambil URL dump world terbaru dari
  https://github.com/ProjectSkyfire/SkyFire_548/releases
lalu isi WORLD_DB_URL di .env, atau taruh file .sql-nya sendiri di volume
world-db pada path /opt/skyfire/tdb/world_database.sql.
MSG
    exit 1
fi

mkdir -p "$(dirname "$DUMP")"
tmp="$(dirname "$DUMP")/download.tmp"

echo "[world-db] Database '${DB_WORLD}' kosong. Mengunduh dump..."
echo "[world-db] $URL"
# --location: rilis GitHub selalu redirect ke CDN.
curl --fail --location --retry 3 --retry-delay 5 --progress-bar -o "$tmp" "$URL"

echo "[world-db] Mengekstrak..."
case "$URL" in
    *.sql.gz|*.gz)  gunzip -c "$tmp" > "$DUMP"; rm -f "$tmp" ;;
    *.zip)
        # Arsip rilis SkyFire berisi satu dump besar, kadang di dalam subfolder
        # dan berdampingan dengan file kecil lain. Ekstrak lalu ambil .sql
        # TERBESAR, jangan `unzip -p '*.sql'` yang menyambung semuanya jadi satu.
        xdir="$(dirname "$DUMP")/extract"
        rm -rf "$xdir"; mkdir -p "$xdir"
        unzip -q -o "$tmp" -d "$xdir"
        biggest="$(find "$xdir" -type f -name '*.sql' -printf '%s	%p
' | sort -rn | head -1 | cut -f2)"
        if [ -z "$biggest" ]; then
            echo "FATAL: tidak ada file .sql di dalam arsip." >&2
            rm -rf "$xdir" "$tmp"; exit 1
        fi
        echo "[world-db] Memakai $(basename "$biggest") dari arsip."
        mv "$biggest" "$DUMP"
        rm -rf "$xdir" "$tmp"
        ;;
    *.7z)           7zr e -so "$tmp" > "$DUMP" 2>/dev/null || 7za e -so "$tmp" > "$DUMP"; rm -f "$tmp" ;;
    *.sql)          mv "$tmp" "$DUMP" ;;
    *)
        echo "FATAL: format arsip tidak dikenali dari URL: $URL" >&2
        echo "Didukung: .sql, .sql.gz, .gz, .zip, .7z" >&2
        rm -f "$tmp"
        exit 1
        ;;
esac

if [ ! -s "$DUMP" ]; then
    echo "FATAL: hasil ekstraksi kosong: $DUMP" >&2
    rm -f "$DUMP"
    exit 1
fi

echo "[world-db] Siap: ${DUMP} ($(du -h "$DUMP" | cut -f1))"
echo "[world-db] worldserver akan mengimpornya sekarang (10-30 menit)."
