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
| `tools/` | Ekstraksi data client (Windows) + unggah ke VPS |
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

```powershell
# 3. Ekstrak data client di PC Windows — PARALEL dengan langkah 1-2.
#    mmaps butuh 4-12 jam, ini bottleneck jadwalnya.
.\tools\extract-client-data.ps1 -ClientPath "C:\Games\World of Warcraft 5.4.8" -ToolsPath C:\SkyFire_Files\Server\bin -OutputPath D:\wow-extracted
```

```bash
# 4. Unggah ~20 GB ke VPS (resumable)
./tools/upload-client-data.sh /d/wow-extracted root@145.79.10.227
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
