#!/bin/sh
# =============================================================================
# render-config.sh <nama-config>
#
# Menghasilkan /opt/skyfire/etc/<nama>.conf dari:
#   1. <nama>.conf.dist  -- dist bawaan image (sumber default resmi core)
#   2. <nama>.overrides.conf -- hanya key yang kita ubah (bind mount dari repo)
#
# Kenapa merge, bukan menyalin conf penuh: worldserver.conf.dist punya ~2600
# baris dan bertambah tiap rilis core. Dengan menyimpan override saja, opsi
# baru dari upstream otomatis ikut terpakai dengan nilai default-nya, dan
# diff repo ini tetap terbaca manusia.
# =============================================================================
set -eu

NAME="$1"
ETC_DIR="${SKYFIRE_ETC:-/opt/skyfire/etc}"
OVERRIDE_DIR="${SKYFIRE_OVERRIDES:-/opt/skyfire/overrides}"

BASE="${ETC_DIR}/${NAME}.conf.dist"
OVERRIDE="${OVERRIDE_DIR}/${NAME}.overrides.conf"
OUT="${ETC_DIR}/${NAME}.conf"

[ -f "$BASE" ] || { echo "FATAL: dist config tidak ditemukan: $BASE" >&2; exit 1; }

if [ ! -f "$OVERRIDE" ]; then
    echo "WARN: $OVERRIDE tidak ada, memakai dist apa adanya." >&2
    cp "$BASE" "$OUT"
    exit 0
fi

# Ekspansi ${VAR} pada file override. Whitelist eksplisit supaya '$' yang
# kebetulan ada di nilai lain (mis. password) tidak ikut diproses.
VARS='${DB_HOST} ${DB_PORT} ${DB_USER} ${DB_PASSWORD} ${DB_AUTH} ${DB_CHARACTERS} ${DB_WORLD} ${REALM_ID} ${REALM_PORT} ${AUTH_PORT} ${DATA_DIR_CONTAINER} ${LOGS_DIR_CONTAINER} ${SQL_DIR_CONTAINER} ${WORLD_DUMP_CONTAINER} ${RATE_XP} ${RATE_DROP_ITEM_COMMON} ${RATE_DROP_ITEM_QUALITY} ${RATE_DROP_ITEM_REFERENCED} ${RATE_DROP_MONEY} ${RATE_HONOR} ${RATE_REPUTATION}'

RENDERED="$(mktemp)"
# shellcheck disable=SC2016
envsubst "$VARS" < "$OVERRIDE" > "$RENDERED"

# Merge: setiap "Key = Value" di override menggantikan baris berkunci sama di
# dist; key yang belum ada di dist di-append di akhir.
awk -v overfile="$RENDERED" '
    BEGIN {
        while ((getline line < overfile) > 0) {
            sub(/\r$/, "", line)
            if (line ~ /^[[:space:]]*#/ || line ~ /^[[:space:]]*$/) continue
            idx = index(line, "=")
            if (idx == 0) continue
            key = substr(line, 1, idx - 1)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
            if (key == "") continue
            val[key] = line
            order[++n] = key
        }
        close(overfile)
    }
    {
        l = $0
        sub(/\r$/, "", l)
        if (l ~ /^[A-Za-z_][A-Za-z0-9_.]*[[:space:]]*=/) {
            k = l
            sub(/[[:space:]]*=.*$/, "", k)
            if (k in val) {
                if (!(k in done)) { print val[k]; done[k] = 1 }
                next
            }
        }
        print l
    }
    END {
        appended = 0
        for (i = 1; i <= n; i++) {
            k = order[i]
            if (k in done) continue
            if (!appended) {
                print ""
                print "# --- ditambahkan oleh render-config.sh (tidak ada di .conf.dist) ---"
                appended = 1
            }
            print val[k]
            done[k] = 1
        }
    }
' "$BASE" > "$OUT"

rm -f "$RENDERED"

# Config berisi password DB; jangan biarkan world-readable.
chmod 600 "$OUT"
echo "render-config: $OUT siap ($(grep -c . "$OUT") baris non-kosong)"
