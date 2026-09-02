# Deployment & Runbook

Stack ini hidup di VPS `145.79.10.227` lewat repo
[vps-infra](https://github.com/ZuhriDeveloper/vps-infra) di `/srv/vps-infra`,
sebagai `apps/prabowow/`. Semua perintah di bawah dijalankan dari `/srv/vps-infra`.

Compose di sini (`deploy/docker-compose.prod.yml`) **canonical**; salinan di
`vps-infra/apps/prabowow/docker-compose.yml` adalah cermin.

---

## Pertama kali

### 1. Prasyarat

| | |
|---|---|
| VPS | Ubuntu 24.04, sudah di-bootstrap oleh `vps-infra/scripts/bootstrap.sh` |
| Data client | ~20-25 GB hasil `tools/extract-client-data.ps1`, sudah diunggah |
| Image | sudah di-push CI ke `ghcr.io/zuhrideveloper/prabowow-pandaria-server` |
| Domain | record **DNS only** (bukan proxied) mengarah ke IP VPS |

Dump world **tidak** perlu disiapkan manual — container mengunduhnya sendiri
saat boot pertama kalau database world masih kosong.

### 2. Matikan stack Cataclysm

Pandaria mengambil alih port 3724 dan 8085, jadi `renowow` harus berhenti dulu.
Volume-nya **tidak** disentuh — akun dan karakter Cataclysm tetap utuh dan bisa
dihidupkan lagi kapan saja.

```bash
docker compose -f apps/renowow/docker-compose.yml --env-file apps/renowow/.env down
```

Backup dulu sebelum berpindah, selagi datanya masih mudah diambil:

```bash
./scripts/backup-db.sh
```

### 3. Isi `.env` dan jalankan

```bash
cp apps/prabowow/.env.example apps/prabowow/.env && chmod 600 apps/prabowow/.env && $EDITOR apps/prabowow/.env
```

Yang wajib diisi: `DB_ROOT_PASSWORD`, `DB_PASSWORD`, `REALM_ADDRESS`.

```bash
docker compose -f apps/prabowow/docker-compose.yml --env-file apps/prabowow/.env pull
```

```bash
docker compose -f apps/prabowow/docker-compose.yml --env-file apps/prabowow/.env up -d
```

```bash
docker compose -f apps/prabowow/docker-compose.yml --env-file apps/prabowow/.env logs -f world
```

Boot pertama menjalankan seluruh setup database sendiri:

1. `db` membuat `auth`/`world`/`characters` + user aplikasi (utf8mb3)
2. `auth` meng-install `sql/base/auth_database.sql` + `sql/updates/auth/*`,
   lalu menulis baris realmlist di background
3. `world` mengunduh dump SkyFire ke volume, mengimpornya + `stored_procs.sql`,
   lalu menerapkan seluruh `sql/updates/world/*` dan `sql/updates/characters/*`

Langkah 3 memakan **10-30 menit**; listener game baru dibuka sesudahnya. Ini
normal. Tunggu sampai log menampilkan `World initialized in ...`.

### 4. Akun GM

```bash
docker attach prabowow-world-1
```

```
account create adminku passwordku
account set gmlevel adminku 3 -1
```

Keluar **tanpa mematikan server**: `Ctrl-P` lalu `Ctrl-Q`. `Ctrl-C` mematikan
worldserver.

### 5. Verifikasi

```bash
nc -vz 145.79.10.227 3724 && nc -vz 145.79.10.227 8085
```

```bash
docker compose -f apps/prabowow/docker-compose.yml --env-file apps/prabowow/.env exec db mysql -uroot -p"$DB_ROOT_PASSWORD" auth -e "SELECT id, name, address, port, gamebuild FROM realmlist;"
```

`address` harus IP publik/domain, `gamebuild` harus `18414`.

```bash
docker compose -f apps/prabowow/docker-compose.yml --env-file apps/prabowow/.env exec db mysql -uroot -p"$DB_ROOT_PASSWORD" world -e "SELECT COUNT(*) FROM creature_template;"
```

Harus puluhan ribu.

```bash
docker compose -f apps/prabowow/docker-compose.yml --env-file apps/prabowow/.env exec db mysql -uroot -p"$DB_ROOT_PASSWORD" world -e "SELECT domain, COUNT(*) FROM skyfire_db_updates GROUP BY domain;"
```

Lalu tes end-to-end dari client asli — lihat [client-setup.md](client-setup.md).

### 6. Tambahkan ke backup harian

`vps-infra/scripts/backup-db.sh` sudah memuat baris untuk stack ini. Cek cron:

```bash
crontab -l | grep backup-db
```

Uji pemulihannya minimal sekali sebelum server dibuka. Backup yang belum pernah
dipulihkan belum terbukti sebagai backup.

---

## Operasi harian

Semua contoh menyingkat `-f apps/prabowow/docker-compose.yml --env-file apps/prabowow/.env`
sebagai `$PW`:

```bash
PW='-f apps/prabowow/docker-compose.yml --env-file apps/prabowow/.env'
```

### Status & log

```bash
docker compose $PW ps && docker compose $PW logs -f world
```

### Console GM

```bash
docker attach prabowow-world-1
```

Perintah yang sering dipakai:

```
account create <user> <pass>
account set gmlevel <user> <0-3> <realmid|-1>
server info
server shutdown 60
kick <charname>
```

### Restart

```bash
docker compose $PW restart world
```

Pemain terputus, karakter tersimpan. Perlu beberapa menit memuat ulang
mmaps/vmaps sebelum listener dibuka; `stop_grace_period` 120 detik menjaga
proses save tidak terpotong.

```bash
docker compose $PW restart auth
```

Pemain yang sudah in-game tidak terganggu; hanya login baru yang tertunda.

### Update core

```bash
gh workflow run deploy.yml -f core_ref=main
```

Setelah workflow selesai, di VPS:

```bash
sed -i 's|^IMAGE_TAG=.*|IMAGE_TAG=<sha>|' apps/prabowow/.env && docker compose $PW pull && docker compose $PW up -d
```

`sql/updates/*` yang baru ikut di dalam image dan otomatis diterapkan saat
startup oleh `DatabaseSetup`. Tidak ada langkah SQL manual.

Tag image memakai SHA **repo ini**, bukan SHA core. Untuk memastikan patch core
yang dimaksud benar-benar ada di image yang sedang jalan:

Commit core yang dipakai build itu juga dicetak di ringkasan workflow, baris
**Core commit**. `deploy.yml` selalu meresolve `core_ref` jadi SHA lebih dulu,
karena layer `git fetch` di Dockerfile di-cache BuildKit berdasarkan teks
perintahnya — dengan `core_ref=main` teks itu tidak pernah berubah dan build
bisa diam-diam memakai core lama dari cache.

```bash
docker compose $PW exec world cat /opt/skyfire/.core-revision
```

Dan update SQL mana saja yang sudah masuk:

```bash
docker compose $PW exec db mysql -uroot -p"$DB_ROOT_PASSWORD" world -e "SELECT filename, applied_at FROM skyfire_db_updates ORDER BY applied_at DESC LIMIT 10;"
```

File update yang **dihapus** di core aman: barisnya tertinggal di
`skyfire_db_updates` dan diabaikan, karena rencana update disusun dari file
yang ada di disk. Yang berbahaya adalah file yang sudah diterapkan lalu
**diubah isinya** -- hash-nya tidak cocok lagi dan core berhenti dengan
"already applied with a different hash" (`AllowUpdateHashMismatch = 0`,
DatabaseSetup.cpp:625-636). Perbaikannya di repo core: terbitkan file update
baru, jangan sunting yang lama.

Backup dulu kalau update menyentuh `sql/updates/characters/`:

```bash
./scripts/backup-db.sh
```

### Rollback

```bash
sed -i 's|^IMAGE_TAG=.*|IMAGE_TAG=<sha-lama>|' apps/prabowow/.env && docker compose $PW pull && docker compose $PW up -d
```

Rollback **binary** mudah, rollback **skema DB** tidak. Update SQL yang sudah
diterapkan tetap ada. Kalau versi lama tidak kompatibel dengan skema baru,
pulihkan juga DB dari backup.

### Ganti IP / domain

```bash
sed -i 's|^REALM_ADDRESS=.*|REALM_ADDRESS=<baru>|' apps/prabowow/.env && docker compose $PW up -d auth world
```

Entrypoint menulis ulang baris realmlist saat start, jadi tidak ada langkah SQL
manual. Pemain tetap harus memperbarui `realmlist` di client mereka — kecuali
kalau kamu memakai domain, yang justru alasan utama memakai domain.

### Bangun ulang world DB

World DB tidak di-backup: ia dibangun ulang dari dump rilis + `sql/updates/*`
kapan saja.

```bash
docker compose $PW stop world
```

```bash
docker compose $PW exec db mysql -uroot -p"$DB_ROOT_PASSWORD" -e "DROP DATABASE world; CREATE DATABASE world DEFAULT CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci;"
```

```bash
docker compose $PW up -d world
```

Setup otomatis berjalan lagi (10-30 menit).

---

## Diagnosa

### Realm tampak offline di client

```bash
docker compose $PW ps
```

`REALM_ID` di `.env` harus sama dengan `realmlist.id`:

```bash
grep REALM_ID apps/prabowow/.env && docker compose $PW exec db mysql -uroot -p"$DB_ROOT_PASSWORD" auth -e "SELECT id FROM realmlist;"
```

### Login berhasil tapi tersangkut di character screen

Hampir selalu `realmlist.address` mengarah ke localhost, atau domainnya
**di-proxy Cloudflare** (harus DNS only).

### Realm bisa dipilih, lalu "Logging in to game server" tertutup seketika

`realmlist.address` berisi **hostname**, bukan IPv4. Nilai kolom itu diserahkan
apa adanya ke client sebagai alamat worldserver, dan client 5.4.8 tidak
me-resolve hostname untuk koneksi tersebut. Tidak ada yang tercatat di log
worldserver karena koneksinya memang tidak pernah dibuat -- `tcpdump port 8085`
akan sunyi sementara port 3724 ramai.

`configure-realm.sh` me-resolve hostname ke IPv4 sebelum menulis baris ini, jadi
`REALM_ADDRESS` di `.env` boleh tetap domain. Kalau baris di DB terlanjur berisi
hostname, restart `auth` sudah cukup memperbaikinya.

Jangan tertukar dengan `SET realmlist` di `Config.wtf` pemain: yang itu justru
boleh hostname, karena client sendiri yang me-resolve-nya untuk menemukan auth
server.


```bash
docker compose $PW exec db mysql -uroot -p"$DB_ROOT_PASSWORD" auth -e "SELECT address, port FROM realmlist;"
```

### Container `world` mati beberapa detik setelah start

`tty: true` / `stdin_open: true` hilang dari compose. Thread CLI worldserver
membaca EOF dari stdin dan mematikan proses dengan rapi — terlihat persis
seperti crash, tapi log akan menampilkan `Halting process...` bukan stack trace.

### `world` berhenti: "update tracking table is missing on a non-empty schema"

Ada yang mengimpor dump ke DB secara manual, melewati jalur `DatabaseSetup`.
Perbaikannya: bangun ulang world DB (lihat di atas).

Jangan menyalakan `AutoBaseline` untuk menutupi ini — itu menandai seluruh
update sebagai sudah diterapkan padahal belum, dan konten yang hilang baru
ketahuan berbulan-bulan kemudian.

### `world` berhenti: folder data client hilang

```bash
ls /srv/prabowow/data
```

Harus ada `dbc db2 cameras maps vmaps mmaps`. Jalankan ulang `tools/upload-client-data.sh`.
Kalau folder ada tapi tetap gagal, cek kepemilikannya: harus `1000:1000` supaya
user `skyfire` di dalam container bisa membacanya.

```bash
sudo chown -R 1000:1000 /srv/prabowow
```

### Login gagal padahal password benar

SRP6 pada handshake GRUNT butuh legacy provider OpenSSL:

```bash
docker compose $PW exec auth openssl list -providers
```

Kalau `legacy` tidak muncul, image di-build tanpa `enable-legacy`. Build ulang
`build-deps-image.yml` lalu `deploy.yml`.

### Unduhan dump world gagal

```bash
docker compose $PW logs world | grep world-db
```

URL rilis berubah tiap kali SkyFire merilis dump baru. Ambil yang terbaru dari
<https://github.com/ProjectSkyfire/SkyFire_548/releases>, perbarui
`WORLD_DB_URL` di `.env`, lalu `docker compose $PW up -d world`.

### MySQL kena OOM kill

`DB_BUFFER_POOL` + `WORLD_MEM_LIMIT` melebihi RAM VPS.

```bash
free -h && docker stats --no-stream
```

Turunkan `DB_BUFFER_POOL` di `.env` lalu `docker compose $PW up -d db`.
