#!/usr/bin/env bash
# =============================================================================
# upload-client-data.sh -- kirim hasil ekstraksi client dari PC lokal ke VPS.
#
# Jalankan dari Git Bash di PC yang punya client WoW 5.4.8, SETELAH
# tools/extract-client-data.ps1 selesai (termasuk mmaps, tahap terlama).
#
#   ./tools/upload-client-data.sh /d/wow-extracted root@145.79.10.227
#
# Total ~20-25 GB. rsync resumable: koneksi putus tidak mengulang dari nol,
# cukup jalankan ulang perintah yang sama.
#
# Data ini turunan dari client berhak cipta: tidak pernah masuk git, tidak
# pernah masuk image, dan di-bind mount read-only ke container.
# =============================================================================
set -euo pipefail

SRC="${1:-}"
VPS_SSH="${2:-}"
DEST="${3:-/srv/prabowow/data}"

if [ -z "$SRC" ] || [ -z "$VPS_SSH" ]; then
    cat >&2 <<'USAGE'
Pemakaian:
  ./tools/upload-client-data.sh <folder-hasil-ekstraksi> <user@host> [tujuan]

Contoh:
  ./tools/upload-client-data.sh /d/wow-extracted root@145.79.10.227
  ./tools/upload-client-data.sh /d/wow-extracted root@145.79.10.227 /srv/prabowow/data
USAGE
    exit 1
fi

SRC="${SRC%/}"
DEST="${DEST%/}"

# Verifikasi kelengkapan SEBELUM mengirim 20 GB. worldserver menolak start
# tanpa keempat folder ini (entrypoint.sh memeriksanya).
missing=()
for d in dbc maps vmaps mmaps; do
    [ -d "${SRC}/${d}" ] || missing+=("$d")
done
if [ "${#missing[@]}" -gt 0 ]; then
    echo "FATAL: folder berikut tidak ada di ${SRC}: ${missing[*]}" >&2
    echo "Jalankan tools/extract-client-data.ps1 sampai selesai." >&2
    exit 1
fi

echo "Akan dikirim dari ${SRC}:"
for d in dbc maps vmaps mmaps; do
    printf '  %-8s %s\n' "$d" "$(du -sh "${SRC}/${d}" 2>/dev/null | cut -f1)"
done
echo "Tujuan: ${VPS_SSH}:${DEST}"
read -r -p "Lanjut? [y/N] " ok
[ "$ok" = "y" ] || [ "$ok" = "Y" ] || { echo "Dibatalkan."; exit 1; }

ssh "$VPS_SSH" "mkdir -p '${DEST}'"

# --partial --append-verify: lanjutkan file yang terputus, bukan mulai ulang.
rsync -avh --progress --partial --append-verify \
    "${SRC}/dbc" "${SRC}/maps" "${SRC}/vmaps" "${SRC}/mmaps" \
    "${VPS_SSH}:${DEST}/"

# uid/gid 1000 harus cocok dengan user `skyfire` di dalam image; tanpa ini
# mount jadi milik root dan server tidak bisa membaca satu map pun.
echo "Menyamakan kepemilikan ke uid/gid 1000 (user skyfire di container)..."
ssh "$VPS_SSH" "sudo chown -R 1000:1000 '$(dirname "$DEST")' 2>/dev/null || sudo chown -R 1000:1000 '${DEST}'"

echo ""
echo "Selesai. Verifikasi di VPS:"
echo "  ssh ${VPS_SSH} 'du -sh ${DEST}/*'"
