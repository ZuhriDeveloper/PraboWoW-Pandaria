# PraboWoW Pandaria

Server World of Warcraft **Mists of Pandaria 5.4.8 (build 18414)**, dijalankan
sebagai stack Docker di VPS.

Core-nya ada di [Prabowow-PandaCore](https://github.com/ZuhriDeveloper/Prabowow-PandaCore)
— fork dari [Project SkyFire](https://github.com/ProjectSkyfire/SkyFire_548) —
dan di-*pin* per commit lewat tag image, bukan submodule. Repo ini yang
membungkusnya jadi image dan mendefinisikan cara ia dijalankan.

Menggantikan stack Cataclysm (`renowow`) di VPS `145.79.10.227`, memakai port
standar 3724/8085 yang sebelumnya dipakai stack itu.

## Bentuknya

`deploy/docker-compose.prod.yml` di repo ini **canonical**. Salinan cerminnya
ada di `vps-infra/apps/prabowow/docker-compose.yml` — ubah di sini dulu, lalu
salin ke sana bersama `mysql-init/`. Pola yang sama dipakai Materia dan
PraboWoW Cataclysm.

```
db     mysql:8          internal, tanpa port publik
auth   :3724            client login di sini
world  :8085            dunia game
```

Satu image, dua peran: `command: ["authserver"]` atau `["worldserver"]`.

**Bukan HTTP.** WoW bicara TCP mentah, jadi Caddy tidak terlibat. Kalau realm
address berupa domain, record DNS-nya harus **DNS only** — proxy Cloudflare
hanya untuk HTTP dan diam-diam merusak koneksi game.

**Tidak ada port 8086.** Koneksi world kedua adalah mekanisme Cataclysm
(`SendConnectToInstance` / `InstanceServerPort`); SkyFire 5.4.8 tidak punya
config itu dan `CMSG_AUTH_CONTINUED_SESSION` hanya stub yang mencatat error
([WorldSession.cpp:692](https://github.com/ZuhriDeveloper/Prabowow-PandaCore/blob/main/src/server/game/Server/WorldSession.cpp#L692)).
MoP memakai satu koneksi.

## Layout

| Path | Isi |
|---|---|
| `docker/deps.Dockerfile` | Base image: GCC 14 + Boost 1.91 + OpenSSL 4.0 (+legacy provider) |
| `docker/Dockerfile` | Multi-stage: compile core → runtime slim |
| `docker/entrypoint/` | Dispatch peran, render config, realmlist, unduh dump world |
| `config/*.overrides.conf` | Hanya key yang diubah dari `.conf.dist` core — di-bake ke image |
| `deploy/` | **Canonical** compose + `.env.example` + `mysql-init/` |
| `docker/tools.Dockerfile` | Image extractor data client |
| `deploy/docker-compose.tools.yml` | Ekstraksi + unggah data client, keduanya dalam container |
| `tools/` | Alternatif native Windows, kalau toolchain-nya sudah terpasang |
| `docs/deployment.md` | Runbook operasional |

## Alur pertama kali

```bash
# 1. Image aplikasi. Base image dependency (Boost 1.91 + OpenSSL 4.0 dari
#    source) dibangun OTOMATIS oleh job `deps` kalau belum ada di GHCR, jadi
#    run pertama memakan ~2-3 jam dan run berikutnya ~1 jam.
gh workflow run deploy.yml -f core_ref=main
```

Push ke `main`/`master` yang menyentuh `docker/**` atau `config/**` juga
men-trigger `deploy.yml` dengan sendirinya.

```bash
# 2. Image extractor data client (sekali). Berjalan PARALEL dengan langkah 1.
gh workflow run build-tools-image.yml
```

```bash
# 3. Ekstrak data client di PC yang punya client. Tahap mmaps 4-12 jam —
#    ini bottleneck jadwalnya, mulai sedini mungkin.
cp deploy/.env.tools.example deploy/.env.tools    # lalu isi
docker compose -f deploy/docker-compose.tools.yml --env-file deploy/.env.tools run --rm extract
```

```bash
# 4. Kirim ~20 GB ke VPS langsung dari volume (resumable)
docker compose -f deploy/docker-compose.tools.yml --env-file deploy/.env.tools run --rm upload
```

Sisanya di VPS lewat `vps-infra` — lihat [docs/deployment.md](docs/deployment.md).

## Kenapa override, bukan salin `.conf` penuh

`worldserver.conf.dist` sekitar 3300 baris dan bertambah tiap rilis core.
`docker/entrypoint/render-config.sh` menggabungkan `config/*.overrides.conf`
di atas dist bawaan image saat container start, sehingga:

- opsi baru dari upstream otomatis terpakai dengan default-nya
- diff repo ini tetap terbaca manusia (±40 baris, bukan 3300)
- password tidak pernah ditulis ke repo — hanya `${VAR}` dari environment

## Setup database

Base install **tidak** dilakukan dengan `mysql < dump.sql`. Core punya jalur
`DatabaseSetup` sendiri yang meng-install base lalu menerapkan `sql/updates/*`
di atasnya dan mencatatnya di tabel `skyfire_db_updates`.

Import manual menghasilkan schema terisi **tanpa** tabel tracking, dan core
menolak start dengan *"update tracking table is missing on a non-empty schema"*
(`DatabaseSetup.cpp:593-599`).

Konsekuensinya bagus: `sql/updates/*` yang baru **otomatis diterapkan saat
restart**. Itulah mekanisme upgrade DB — tidak ada langkah SQL manual.

SQL khusus server ini juga ditulis sebagai `sql/updates/<db>/` **di repo core**,
bukan di sini, supaya ikut dilacak dan diverifikasi hash-nya.

## Fitur pemain (mod-prabowow)

Semua fitur di bawah hidup di modul `modules/mod-prabowow` repo core dan
dinyalakan lewat key `PraboWoW.*` di `config/worldserver.overrides.conf`.

| Fitur | Cara pakai |
|---|---|
| Rate XP per karakter | `.xp` lihat rate, `.xp rate <1-5>` ganti. Dikalikan di atas `RATE_XP`. |
| Chat satu realm | `.chat <pesan>` -- sampai ke semua pemain, kedua faksi. Cooldown 3 detik, hormati mute. |
| Auto-jual item abu-abu | Otomatis saat loot; uangnya langsung masuk. |
| Semua flight path | Dikenal saat login, sesuai faksi. |
| Vendor heirloom | NPC "Heirloom Vendor" berdiri di tiap titik spawn karakter baru; harga `HEIRLOOM_PRICE_GOLD` (default 500g). |
| Surat karakter baru | Item 23162 (tas 36 slot) x1 lewat mailbox. |

Command pemain butuh RBAC permission 1100-1102 (auth) dan tabel
`character_xp_rate` (characters); keduanya `sql/updates/*` di repo core dan
diterapkan otomatis saat world start.

## Playerbots (mod-playerbots)

Bot pemain untuk menghidupkan realm: dibuat otomatis, login sendiri, bisa
di-invite ke party, follow, dan bertarung dengan rotasi per-spec MoP (34 spec,
monk termasuk). Modulnya `modules/mod-playerbots` di repo core, vendor dari
[DigiD702/mod-playerbots](https://github.com/DigiD702/mod-playerbots) -- satu-
satunya playerbot yang ditulis untuk SkyFire 5.4.8. `mod-playerbots` versi
AzerothCore **tidak bisa dipakai** di sini: itu WotLK 3.3.5a dan butuh fork
AzerothCore.

Dinyalakan lewat `.env` di VPS (default image: **mati**):

| Var | Default | Arti |
|---|---|---|
| `PLAYERBOTS_ENABLE` | `0` | Saklar tunggal: modul, pool bot acak, dan pembuatan akun saat boot. |
| `PLAYERBOTS_ACCOUNT_PASSWORD` | *(kosong)* | Password akun `RNDBOT1..n`. **Wajib** saat `ENABLE=1`; entrypoint menolak start kalau kosong. |
| `PLAYERBOTS_MAX_BOTS` | `10` | Bot online sekaligus. Tiap bot = satu `Player` penuh di world thread -- naikkan setelah melihat CPU/RAM. |
| `PLAYERBOTS_ACCOUNTS` | `5` | Akun bot yang dibuat, 4 karakter per akun, level acak 1-90. |
| `PLAYERBOTS_JOIN_LFG` | `0` | Bot acak ikut mengisi antrean dungeon finder pemain. Nyalakan setelah stabil. |

Key lain di `config/playerbots.overrides.conf`; referensi semua opsi di
`modules/mod-playerbots/conf/playerbots.conf.dist` repo core.

Perintah GM (console atau in-game; lengkapnya `modules/mod-playerbots/COMMANDS.md`):

| Perintah | Fungsi |
|---|---|
| `.playerbots status` | Hitungan bot acak / aktif / kandidat. |
| `.playerbots create` | Buat akun+karakter bot yang masih kurang (idempoten). |
| `.playerbots add <nama>` / `remove <nama>` | Login / logout satu bot. |
| `.playerbots init [<nama>] [tank\|healer\|dps]` | Gear + spec + glyph ulang; ganti role. |
| `.playerbots summon` | Teleport semua bot di party ke posisi kamu. |
| `.playerbots self` | AI cast-only menempel ke karaktermu sendiri. |

Perintah chat ke bot (whisper atau party): `follow`, `stay`, `attack`, `pull`,
`flee`, `grind`, `passive`, `sell`, `mount`, `co +heal`, dan lainnya.

Yang perlu diketahui:

- Bot **tidak pernah** memakai karakter pemain asli -- hanya akun ber-prefix `RNDBOT`.
- `Playerbots.DeleteRandomBotAccounts` menghapus semua akun itu saat startup.
  Sengaja `0` dan tidak diekspos ke `.env`; pakai `.playerbots wipe confirm`.
- Tabel `playerbots_preferred_mounts` (characters) dibuat modul sendiri saat load;
  SQL-nya juga dilacak di `sql/` repo core.
- Repo modul upstream tidak menyertakan file LICENSE. Untuk server pribadi ini
  bukan masalah praktis; jangan redistribusi image-nya.

## Catatan yang mahal kalau terlewat

- **`REALM_ADDRESS` harus IP publik/hostname VPS.** Kalau `127.0.0.1`, pemain
  berhasil login tapi tersangkut di character screen. `configure-realm.sh`
  menolak jalan kalau nilainya localhost.
- **`RealmID` = 1.** Dist core ship `RealmID = 0`, sementara
  `auth_database.sql:362` men-seed realm `id=1`. Diperbaiki di
  `config/worldserver.overrides.conf` + `configure-realm.sh`.
- **`tty: true` dan `stdin_open: true` load-bearing.** Thread CLI worldserver
  membaca stdin; tanpa TTY ia menerima EOF dan mematikan proses beberapa detik
  setelah start — persis terlihat seperti crash.
- **OpenSSL legacy provider wajib aktif** — SRP6 pada handshake login
  membutuhkannya. `docker/Dockerfile` memverifikasi ini saat build.
- **`sql_mode` MySQL harus dilonggarkan sebelum import pertama**, bukan sesudah.
