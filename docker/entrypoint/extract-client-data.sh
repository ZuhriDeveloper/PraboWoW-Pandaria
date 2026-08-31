#!/bin/bash
# =============================================================================
# Ekstraksi data client 5.4.8 di dalam container.
#
#   extract-client-data.sh [tahap ...]
#
# Tahap: maps vmaps assemble mmaps   (default: semuanya, berurutan)
# Sebutkan tahap tertentu untuk melanjutkan setelah terhenti, mis:
#   docker compose ... run --rm extract mmaps
#
# Setiap tahap MELEWATI dirinya sendiri kalau outputnya sudah ada, jadi
# menjalankan ulang perintah yang sama aman dan langsung lanjut ke tahap
# yang belum selesai.
# =============================================================================
set -euo pipefail

CLIENT="${CLIENT_DIR:-/client}"
OUT="${OUTPUT_DIR:-/out}"
THREADS="${MMAP_THREADS:-0}"

STEPS=("$@")
[ "${#STEPS[@]}" -eq 0 ] && STEPS=(maps vmaps assemble mmaps)

has() { for s in "${STEPS[@]}"; do [ "$s" = "$1" ] && return 0; done; return 1; }
say() { printf '\n=== %s ===\n' "$1"; }

[ -f "${CLIENT}/Data/world.MPQ" ] || {
    echo "FATAL: ${CLIENT}/Data/world.MPQ tidak ada." >&2
    echo "Bind mount folder ROOT client (yang berisi Wow.exe dan Data/) ke ${CLIENT}." >&2
    exit 1
}

mkdir -p "$OUT"
cd "$OUT"
started=$(date +%s)

# --- 1. dbc + maps + Cameras -------------------------------------------------
if has maps; then
    if [ -d "${OUT}/maps" ] && [ -d "${OUT}/dbc" ]; then
        say "1/4 mapextractor -- SUDAH ADA, dilewati"
    else
        say "1/4 mapextractor -> dbc/ maps/ Cameras/   (~20 menit, ~2 GB)"
        # -i memakai ROOT client: tool menambahkan "/Data/" sendiri
        # (map_extractor/System.cpp:1224). Beda dari vmap4extractor di bawah.
        mapextractor -i "$CLIENT" -o "$OUT"
    fi
fi

# --- 2. vmaps mentah ---------------------------------------------------------
if has vmaps; then
    if [ -d "${OUT}/vmaps" ]; then
        say "2/4 vmap4extractor -- vmaps/ sudah ada, dilewati"
    else
        say "2/4 vmap4extractor -> Buildings/   (~30 menit)"
        # Tool menolak jalan kalau output dir sudah "kotor"
        # (vmapexport.cpp:534-547), jadi bersihkan agar aman diulang.
        rm -rf "${OUT}/Buildings"
        # -d memakai folder Data/ ITU SENDIRI, bukan root client
        # (vmapexport.cpp:169 menyambung input_path + "world.MPQ").
        vmap4extractor -d "${CLIENT}/Data/"
    fi
fi

# --- 3. rakit vmaps ----------------------------------------------------------
if has assemble; then
    if [ -d "${OUT}/vmaps" ]; then
        say "3/4 vmap4assembler -- vmaps/ sudah ada, dilewati"
    else
        say "3/4 vmap4assembler -> vmaps/   (~20 menit, ~4 GB)"
        [ -d "${OUT}/Buildings" ] || { echo "FATAL: Buildings/ tidak ada, jalankan tahap vmaps dulu." >&2; exit 1; }
        vmap4assembler Buildings vmaps
        # Intermediate beberapa GB; tidak dipakai server dan tidak ikut diunggah.
        rm -rf "${OUT}/Buildings"
    fi
fi

# --- 4. mmaps (navmesh) ------------------------------------------------------
if has mmaps; then
    say "4/4 mmaps_generator -> mmaps/   (4-12 JAM, ~12 GB)"
    for need in maps vmaps; do
        [ -d "${OUT}/${need}" ] || { echo "FATAL: butuh ${OUT}/${need}, jalankan tahap sebelumnya." >&2; exit 1; }
    done
    echo "Tahap terlama. Biarkan berjalan; tile yang sudah jadi dilewati kalau diulang."
    if [ "$THREADS" -gt 0 ] 2>/dev/null; then
        mmaps_generator --threads "$THREADS"
    else
        mmaps_generator
    fi
fi

# --- Ringkasan ---------------------------------------------------------------
say "Ringkasan"
ok=1
for d in dbc maps vmaps mmaps; do
    if [ -d "${OUT}/${d}" ]; then
        printf '  %-8s %8s  %7s file\n' "$d" \
            "$(du -sh "${OUT}/${d}" | cut -f1)" \
            "$(find "${OUT}/${d}" -type f | wc -l)"
    else
        printf '  %-8s HILANG\n' "$d"
        ok=0
    fi
done
printf '\nTotal waktu: %s\n' "$(date -u -d "@$(( $(date +%s) - started ))" +%H:%M:%S)"

if [ "$ok" -eq 1 ]; then
    echo ""
    echo "Semua folder siap. Kirim ke VPS:"
    echo "  docker compose -f deploy/docker-compose.tools.yml run --rm upload"
else
    echo ""
    echo "Ada folder yang belum jadi. Jalankan ulang perintah yang sama --"
    echo "tahap yang sudah selesai akan dilewati." >&2
    exit 1
fi
