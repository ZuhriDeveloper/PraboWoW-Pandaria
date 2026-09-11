# Daily Commands — PraboWoW Pandaria VPS

Shortcut untuk quick copy:
```bash
PW='-f apps/prabowow/docker-compose.yml --env-file apps/prabowow/.env'
```

---

## 1️⃣ PULL UPDATE TERBARU DAN APPLY KE WORLD

### Update Core dari Git

Di repo ini (`PraboWoW-Pandaria`):
```bash
gh workflow run deploy.yml -f core_ref=main
```

Tunggu CI selesai (~1-2 jam), lalu di VPS:

```bash
# Dapatkan SHA hasil build dari Actions
gh run view <run-id> --json conclusion,output

# Update image tag di .env
sed -i 's|^IMAGE_TAG=.*|IMAGE_TAG=<sha>|' apps/prabowow/.env

# Pull image baru dan restart
docker compose $PW pull
docker compose $PW up -d
```

### Verifikasi Update
```bash
# Check core revision
docker compose $PW exec world cat /opt/skyfire/.core-revision

# Check last applied SQL updates
docker compose $PW exec db mysql -uroot -p"$DB_ROOT_PASSWORD" world -e "SELECT filename, applied_at FROM skyfire_db_updates ORDER BY applied_at DESC LIMIT 5;"
```

---

## 2️⃣ CREATE AKUN BARU (PLAYER)

Attach ke console world server:
```bash
docker attach prabowow-world-1
```

Jalankan command:
```
account create <username> <password>
```

Contoh:
```
account create PlayerName MyPassword123
```

Keluar **tanpa matikan server**: `Ctrl+P` → `Ctrl+Q`

---

## 3️⃣ CREATE AKUN GM

Attach ke console world server:
```bash
docker attach prabowow-world-1
```

Create akun terlebih dahulu:
```
account create <username> <password>
```

Set GM level (0-3):
```
account set gmlevel <username> <level> -1
```

Level reference:
- `0` = Player
- `1` = Moderator (basic moderator tools)
- `2` = Gamemaster (full GM tools)
- `3` = Administrator (full access + server control)

Contoh lengkap:
```
account create AdminName AdminPass123
account set gmlevel AdminName 3 -1
```

Keluar: `Ctrl+P` → `Ctrl+Q`

---

## 4️⃣ RESTART WORLD

### Full world restart
```bash
docker compose $PW restart world
```

**Note:** Pemain akan disconnect, karakter tersimpan. Tunggu 2-3 menit untuk mmaps/vmaps reload.

### Auth restart saja (login server)
```bash
docker compose $PW restart auth
```

**Note:** Pemain yang sudah in-game tidak terganggu, hanya pemain baru yang tidak bisa login sementara.

### Check status
```bash
docker compose $PW ps
docker compose $PW logs -f world
```

---

## 5️⃣ GM COMMANDS YANG SERING DIPAKAI

Attach ke console:
```bash
docker attach prabowow-world-1
```

### Account Management
```
account create <username> <password>
account set gmlevel <username> <0-3> -1
account set password <username> <newpassword>
```

### Server Info & Control
```
server info                    # Info server (uptime, connected players)
server shutdown 60             # Shutdown dengan countdown 60 detik
server restart 60              # Restart dengan countdown
server motd <message>          # Set message of the day
```

### Player Management
```
kick <charname>                # Kick player
mute <username> <minutes>      # Mute player chat
unmute <username>              # Unmute player
ban account <username>         # Ban akun
unban account <username>       # Unban akun
banlist account <username>     # Check ban status
```

### Character Tools
```
character delete <charname>    # Hapus karakter
character level <charname> <level>  # Set level
character rename <charname>    # Rename character
```

### In-game Tools (ketika sudah logged in as GM)
- `.server info` — Info server
- `.account create <user> <pass>` — Create akun (dari in-game)
- `.tele <location>` — Teleport ke lokasi
- `.tele name <playername>` — Teleport ke player lain
- `.npc add <entry>` — Spawn NPC
- `.npc delete` — Delete NPC terpilih
- `.go <x> <y> <z> <map>` — Teleport koordinat

---

## 6️⃣ COMMAND PLAYER (mod-prabowow)

Bisa dipakai semua akun, tanpa GM level:

```
.xp                    # lihat rate XP saat ini
.xp rate <1-5>         # set rate XP karakter ini (tersimpan)
.chat <pesan>          # chat ke seluruh realm, lintas faksi
```

Otomatis tanpa command: item abu-abu terjual saat loot, semua flight path
dikenal saat login, NPC "Heirloom Vendor" di tiap titik spawn karakter baru
serta di auction house Stormwind dan Orgrimmar, dan karakter baru dapat surat
berisi tas 36 slot (item 23162).

---

## 📋 WORKFLOW LENGKAP HARI PERTAMA

1. **Pull dan apply update:**
   ```bash
   gh workflow run deploy.yml -f core_ref=main
   # tunggu CI selesai
   # kemudian di VPS:
   sed -i 's|^IMAGE_TAG=.*|IMAGE_TAG=<sha>|' apps/prabowow/.env
   docker compose $PW pull && docker compose $PW up -d
   ```

2. **Create akun admin/GM:**
   ```bash
   docker attach prabowow-world-1
   account create AdminName AdminPass123
   account set gmlevel AdminName 3 -1
   # Ctrl+P → Ctrl+Q
   ```

3. **Create akun player:**
   ```bash
   docker attach prabowow-world-1
   account create PlayerName PlayerPass123
   # Ctrl+P → Ctrl+Q
   ```

4. **Verifikasi:**
   ```bash
   docker compose $PW ps
   docker compose $PW logs -f world | grep "World initialized"
   nc -vz 145.79.10.227 3724 && nc -vz 145.79.10.227 8085
   ```

---

## 🚨 SHUTDOWN PROPERLY

**JANGAN PERNAH** gunakan `Ctrl+C` di console world — itu force kill.

Selalu gunakan:
```bash
server shutdown 60
```

atau dari docker:
```bash
docker compose $PW stop world
```

Ini memberi waktu proses save karakter (~2 menit grace period).

---

## 📊 BACKUP SEBELUM UPDATE BESAR

```bash
./scripts/backup-db.sh
```

Terutama kalau update menyentuh `sql/updates/characters/` atau `sql/updates/world/`.

Wajib juga sebelum menyalakan `PraboWoW.StartZoneSkip.*` pertama kali: fitur itu
menulis ke SETIAP karakter DK/Worgen/Goblin yang login -- quest ditandai selesai,
level naik, dan posisi mereka pindah ke ibu kota.

---

## 🔍 TROUBLESHOOTING QUICK CHECKLIST

| Problem | Solution |
|---------|----------|
| Realm offline | Check `docker compose $PW ps`, pastikan `world` running |
| Player stuck character screen | Check `realmlist.address` bukan localhost; harus DNS only di Cloudflare |
| World crash saat start | Check TTY settings di compose — `tty: true` dan `stdin_open: true` harus ada |
| Legacy OpenSSL error | Build ulang deps: `gh workflow run build-deps-image.yml` |
| Can't connect (Unable to connect) | Check firewall/DNS; `realmlist` salah ketik |
| Zona 80-90 kosong, tidak ada mob & quest | Jalankan audit di bagian CEK KONTEN LEVELING; zona dengan `quest` besar tapi `pemberi_terspawn` 0 belum diport |
| Quest "Hero's Call / Warchief's Command: Mount Hyjal!" tidak selesai setelah teleport ke Moonglade | Buka saja jendela Emissary Windsong di Nighthaven — quest ditandai selesai saat jendelanya dibuka. Emissary ibu kota juga menyelesaikannya sebelum teleport sejak perbaikan ini masuk |
| Quest "As Hyjal Burns" mentok di Moonglade | Batalkan lalu ambil lagi dari Emissary Windsong — teleportnya menyala saat quest diterima |
| Mob Hyjal/Deepholm/Uldum/Twilight Highlands tidak drop apa pun, mayatnya tidak berkilau | `lootid` dan `maxgold` sama-sama nol di dump 4.3.4 dan ikut terbawa. Ukur dengan `audit_loot_coverage.sql` bagian 1, perbaiki dengan `prabowow_cataclysm_zone_loot_and_gold.sql` |
| Mob Hyjal/Deepholm/Uldum/Twilight Highlands cuma menjatuhkan gold, tidak pernah ada item | Keadaan yang lain: `maxgold` > 0 sudah cukup membuat mayatnya berkilau, tapi `lootid` = 0 berarti tidak ada satu item pun. Berasal dari baris `creature_template` milik SFDB sendiri, bukan dari port. Ukur dengan `audit_loot_coverage.sql` bagian 1d dan 1e, perbaiki dengan `prabowow_cataclysm_zone_loot_and_gold.sql` yang sama |
| Papan tugas tidak menawarkan quest Pandaria di level 85 | Bukan gerbang expansion — quest 29547/29611 memang tidak punya baris `gameobject_queststarter` di SFDB. Lihat `prabowow_pandaria_intro_board_and_travel.sql` |
| Tidak ada portal ke Pandaria di Stormwind / Orgrimmar | Portalnya sebenarnya BERDIRI di kedua kota — SFDB memasangnya sejak rilis 10_to_11. Yang tidak ada itu tujuannya: spell di `data0` tidak punya baris `spell_target_position`. Ukur dengan `audit_pandaria_loot.sql` bagian 7, perbaiki dengan `prabowow_pandaria_city_portals.sql` |
| Portal Pandaria diklik tapi pemain tidak pindah | Gejala yang sama persis dengan baris di atas, dan sebabnya juga sama. `spell_punya_tujuan` = 0 di bagian 7 audit memastikannya |
| Portal Pandaria tenggelam separuh ke dalam tanah | Z di baris spawn SFDB persis setinggi tanah, dan `GameObject.cpp:179` memakainya apa adanya tanpa penyesuaian. Dinaikkan `@Z_LIFT` di bagian 3b `prabowow_pandaria_city_portals.sql`. Tinggi pastinya dicari di client — lihat "Menyetel tinggi portal" |
| Portal Pandaria menghadap arah yang salah | `rotation3` = 1 di baris SFDB membuat `UpdateRotationFields` (`GameObject.cpp:2192`) mengabaikan `orientation`, karena ia hanya menghitung sendiri kalau `rotation2` DAN `rotation3` dua-duanya nol. Bagian 3b menolkan keduanya |
| Mob Pandaria terlalu tebal / lama dibunuh | `prabowow_pandaria_mob_health.sql` menurunkan `Health_mod` map 870 jadi 30%. Rate di config tidak bisa dipakai — ia berlaku untuk seluruh realm, tanpa varian per-map |
| Mob Pandaria tidak menjatuhkan apa pun | Jangan langsung menyalin solusi zona Cataclysm. Pandaria konten asli SFDB, bukan hasil port, jadi lootnya bisa saja utuh. Ukur dulu dengan `audit_pandaria_loot.sql` bagian 1 |

---

## 🧭 CEK KONTEN LEVELING 80-90

Dump dasar SFDB tidak ada di repo mana pun; ia diunduh sekali ke volume Docker.
Jadi satu-satunya cara tahu zona mana yang benar-benar kosong adalah bertanya ke
DB yang sedang jalan.

```bash
docker compose $PW exec -T db mysql -uroot -p"$DB_ROOT_PASSWORD" world \
    < audit_leveling_coverage.sql
```

File-nya ada di repo core: `tools/dev/audit_leveling_coverage.sql`. Semua
statement-nya SELECT, aman dijalankan kapan saja.

Dua audit yang lebih dalam ada di folder yang sama, dipakai kalau audit umum di
atas menunjukkan ada yang aneh:

```bash
# mob yang mayatnya tidak bisa di-loot sama sekali, per blok guid zona hasil port
docker compose $PW exec -T db mysql -uroot -p"$DB_ROOT_PASSWORD" world \
    < audit_loot_coverage.sql   > audit_loot.txt

# jalan masuk quest Pandaria lewat papan tugas, plus isi zonanya
docker compose $PW exec -T db mysql -uroot -p"$DB_ROOT_PASSWORD" world \
    < audit_pandaria_intro.sql  > audit_pandaria.txt
```

Yang dibaca duluan bagian 2. Satu zona baru bisa dimainkan kalau
`pemberi_terspawn` dan `penutup_terspawn` mendekati `quest`. Kalau `quest` besar
tapi keduanya 0, quest-nya ada di DB tapi tidak ada satu pun NPC-nya — itu
kondisi Mount Hyjal sebelum diport, dan artinya zona itu perlu port spawn.

### Status jalur 80-90

| Band | Zona | Status |
|------|------|--------|
| 80-82 | Mount Hyjal | Diport (`2026_09_08_world_02/03.sql`) + tumpangan Moonglade→Nordrassil |
| 80-83 | Vashj'ir | **Belum** — sengaja dilewat, sejajar dengan Hyjal dan paling berat scriptnya |
| 82-83 | Deepholm | Diport |
| 83-84 | Uldum | Diport |
| 84-85 | Twilight Highlands | Diport |
| 85-90 | Pandaria | Quest intronya kini dipasang di papan tugas (`prabowow_pandaria_intro_board_and_travel.sql`) plus tumpangan ke Jade Forest, dan portal ibu kotanya diperbaiki (`prabowow_pandaria_city_portals.sql`). Kelengkapan spawn **sudah diukur** dan zonanya berisi — lihat "Hasil ukur Pandaria" di bawah |

**Drop mob zona hasil port.** File perbaikannya masih ada di
`sql/pending_updates/world/`, dan `WorldDatabase.ImportPendingUpdates = 0` di
`config/worldserver.overrides.conf`, jadi ia TIDAK pernah ikut jalan sendiri saat
worldserver naik. Selama belum dipromosikan ke `sql/updates/world/` (atau
dijalankan dengan tangan ke DB yang jalan), keadaan di bawah masih apa adanya.

Ada dua keluhan yang berbeda, dan keduanya ditangani file yang sama:

- `lootid` = 0 DAN `maxgold` = 0 -- mayatnya tidak bisa diklik sama sekali.
- `lootid` = 0 tapi `maxgold` > 0 -- mayatnya berkilau, gold keluar, item tidak
  pernah ada. Ini datang dari baris `creature_template` milik SFDB sendiri: port
  memakai `INSERT IGNORE`, jadi untuk entry yang sudah dikenal SFDB nilai yang
  hidup adalah nilai SFDB. Versi pertama file perbaikannya melewatkan kelompok
  ini karena lingkupnya memakai AND; sekarang OR.

Sampai `prabowow_cataclysm_zone_loot_and_gold.sql` masuk, sebagian besar mob
keempat zona di atas tidak menjatuhkan apa pun — bukan "loot-nya kosong", mayatnya tidak
bisa diklik sama sekali. Sebabnya `lootid` dan `maxgold` sama-sama nol di dump
4.3.4 dan ikut terbawa apa adanya; `Unit.cpp:6688` baru memasang
`UNIT_DYNFLAG_LOOTABLE` kalau salah satunya bukan nol. Ukur dengan
`audit_loot_coverage.sql` bagian 1.

Port zona baru dibuat dengan `tools/dev/port_zone_spawns.py --zone <nama>` di
repo core, dari dump world TrinityCore 4.3.4. Dump itu tidak punya konten
Pandaria sama sekali, jadi kalau audit menunjukkan Pandaria juga kosong,
sumbernya harus dicari di tempat lain — bukan dari dump 4.3.4.

**Catatan phasing.** Semua spawn hasil port dipasang di phase 0 supaya terlihat
semua pemain. Zona Cataclysm aslinya berubah bentuk mengikuti kemajuan quest
lewat script C++ yang tidak ada di SkyFire; tanpa perataan itu zonanya tetap
terlihat kosong. Harganya: beberapa versi area yang sama tampil bersamaan, dan
quest yang kemajuannya bergantung pada perubahan fase tidak akan selesai.

### Hasil ukur Pandaria

Pandaria **tidak** kosong seperti Hyjal. Diukur dengan `audit_pandaria_intro.sql`
bagian 10 dan 11 pada dump dasar SFDB:

| Zona | quest | pemberi_terspawn | penutup_terspawn |
|------|-------|------------------|------------------|
| The Jade Forest | 325 | 151 | 140 |
| Valley of the Four Winds | 295 | 197 | 177 |
| Krasarang Wilds | 159 | 85 | 81 |
| Kun-Lai Summit | 182 | 109 | 111 |
| Townlong Steppes | 166 | 76 | 75 |
| Dread Wastes | 116 | 64 | 58 |
| Vale of Eternal Blossoms | 188 | 16 | 30 |

Map 870 berisi 29.696 creature dan 8.250 gameobject. Jadi mengantar pemain ke
Jade Forest tidak membuang mereka ke zona kosong, dan `port_zone_spawns.py`
bukan alat untuk Pandaria — dump 4.3.4 memang tidak punya map 870 sama sekali.

Bandingkan dengan tanda tangan zona yang benar-benar kosong, dari
`audit_leveling_coverage.sql` bagian 2 pada dump dasar yang sama: Mount Hyjal
161 quest / 148 punya pemberi / **1** terspawn, dan Twilight Highlands 256 /
238 / **5**. Pola itulah yang bikin keduanya perlu diport.

Pengecualiannya cuma Vale of Eternal Blossoms: dari 188 quest hanya 17 yang
punya pemberi di data sama sekali (kolom `ada_pemberi`), jadi lubangnya ada di
data quest, bukan di spawn. Port spawn tidak akan menolong zona itu.

⚠️ Deepholm (118 dari 154 terspawn) dan Uldum (55 dari 118) ternyata sudah
berisi di dump dasar, padahal keduanya tetap diport. Kalau angka serupa muncul
di DB hidup, ada kemungkinan spawn-nya dobel — `DELETE` di file port hanya
menyapu blok guid `84xxxxx` miliknya sendiri dan tidak menyentuh spawn asli
SFDB. Konfirmasi ke DB hidup dulu sebelum menyimpulkan apa pun.

### Portal, HP, dan loot Pandaria

Tiga perubahan yang berdiri sendiri, semuanya di `sql/pending_updates/world/`
repo core. Karena `WorldDatabase.ImportPendingUpdates = 0`, tidak satu pun jalan
sendiri saat worldserver naik — lihat "Menjalankan file pending dengan tangan"
di bawah.

**Portal ke Jade Forest** (`prabowow_pandaria_city_portals.sql`). Portalnya tidak
pernah hilang: SFDB sudah memasang keduanya sejak rilis 10_to_11, dan keduanya
memang berdiri di tempat yang benar.

| Entry | Nama | Kota | Map | Koordinat |
|-------|------|------|-----|-----------|
| 215424 | Portal to Honydew Village (Horde) | Orgrimmar | 1 | 2014.8, -4700.3, 28.6 |
| 215457 | Portal to Paw don Village (Alliance) | Stormwind | 0 | -8194.5, 528.1, 117.3 |

Yang tidak ada adalah tujuannya. Keduanya `type` 22 (SPELLCASTER), dan
`GameObject.cpp:1853` mengambil `data0` sebagai spell yang dirapal pemain — tapi
`data0`-nya 130698 dan 130703, dan tidak satu pun dari keduanya punya baris
`spell_target_position` di seluruh `sql/old`. Jadi portalnya berdiri, animasinya
jalan, pemainnya tidak pindah ke mana-mana.

Perbaikannya mengarahkan `data0` ke 130321 (Alliance) dan 125060 (Horde) —
dua spell teleport Jade Forest yang tujuannya memang sudah ada di DB, dipakai
SFDB sendiri untuk gossip kapal, dan titik mendaratnya sama persis dengan yang
dipakai Pandaria Emissary. Tidak ada baris baru yang ditambahkan ke tabel mana
pun.

Menambah baris `spell_target_position` untuk 130698/130703 **bukan** jalan
keluarnya: effIndex-nya ada di `Spell.dbc`, bukan di DB (130321 memakai 0,
125060 memakai 1), jadi ia tidak bisa diturunkan dari SQL dan menebak berarti
satu baris error `sql.sql` di setiap boot.

#### Menyetel tinggi portal

Baris spawn SFDB itu punya dua cacat lagi yang baru kelihatan begitu portalnya
benar-benar dipakai: **tenggelam separuh ke tanah**, dan **menghadap arah yang
salah**. Keduanya diperbaiki di bagian 3b file yang sama.

Arah hadapnya pasti benar sesudah perbaikan — `rotation2` dan `rotation3`
dinolkan supaya core menghitungnya sendiri dari `orientation`. Tingginya tidak:
`@Z_LIFT` = 2.0 itu **perkiraan**, karena tinggi pivot model 12658 ada di
`GameObjectDisplayInfo.dbc` dan tidak bisa dibaca dari SQL.

Angka pastinya dicari di client, dan hasilnya langsung tersimpan sendiri —
`.gobject move` memanggil `SaveToDB()` di akhir:

```
.gobject near 30
```

```
.gobject move <guid> <x> <y> <z>
```

Kalau sudah pas, baca balik posisinya, kurangi dengan Z tanah (28.62439 di
Orgrimmar, 117.2901 di Stormwind), lalu tulis selisihnya ke `@Z_LIFT` supaya DB
yang dibangun dari nol nanti ikut benar:

```bash
docker compose $PW exec -T db mysql -uroot -p"$DB_ROOT_PASSWORD" world -e "SELECT guid, id, map, position_x, position_y, position_z, orientation, rotation2, rotation3 FROM gameobject WHERE id IN (215424, 215457);"
```

Kedua UPDATE di bagian 3b dijaga sidik jari `rotation2` = 0 **dan** `rotation3`
= 1 — tanda baris SFDB yang belum pernah disentuh. Jadi portalnya tidak akan
naik berlipat kalau filenya dijalankan ulang, dan posisi yang sudah kamu setel
sendiri lewat `.gobject move` tidak akan ditimpa.

**HP mob Pandaria** (`prabowow_pandaria_mob_health.sql`). Menurunkan
`creature_template`.`Health_mod` map 870 jadi 30% dari aslinya, semua rank
termasuk world boss. Rate di config tidak bisa dipakai untuk ini: ia berlaku
untuk seluruh realm dan tidak punya varian per-map.

Lingkupnya hanya entry yang terspawn di map 870 **dan tidak terspawn di peta
lain** — `creature_template` dipakai bersama semua peta, jadi entry yang dipakai
bersama sengaja dilewat supaya mob yang sama di Azeroth tidak ikut menipis.
Jumlah yang dilewat muncul di laporan sebagai `dipakai_peta_lain`.

Nilai asli setiap entry disimpan di tabel `prabowow_pandaria_health_backup`
sebelum apa pun ditimpa, dan UPDATE-nya selalu dihitung dari situ — jadi file
itu boleh dijalankan berapa kali pun tanpa HP-nya menyusut berlipat. Tabel itu
sengaja tidak dibuang; ia satu-satunya jalan pulang:

```sql
UPDATE `creature_template` `ct`
JOIN `prabowow_pandaria_health_backup` `b` ON `b`.`entry` = `ct`.`entry`
SET `ct`.`Health_mod` = `b`.`health_mod_asli`;
```

HP dipasang saat creature di-spawn, jadi mob yang sudah berdiri tetap tebal
sampai ia mati dan respawn, atau sampai world restart.

**Loot mob Pandaria** (`prabowow_pandaria_mob_loot_and_gold.sql`). ⚠️ Ini
satu-satunya dari ketiganya yang **belum diukur ke DB hidup**, dan ia mungkin
benar-benar tidak perlu dijalankan.

Jangan menyamakannya dengan zona Cataclysm. Zona itu rusak karena diport dari
dump TrinityCore 4.3.4 yang `lootid`-nya nol; Pandaria tidak pernah diport — ia
konten asli SFDB 5.4.8, dan `port_zone_spawns.py` tidak bisa menyentuhnya karena
dump 4.3.4 tidak punya map 870 sama sekali. Jadi sangat mungkin loot Pandaria
utuh dan keluhannya berasal dari hal lain.

Karena itu ukur dulu:

```bash
docker compose $PW exec -T db mysql -uroot -p"$DB_ROOT_PASSWORD" world \
    < audit_pandaria_loot.sql   > audit_pandaria_loot.txt
```

File-nya ada di repo core: `tools/dev/audit_pandaria_loot.sql`, semua
statement-nya SELECT. Bagian 1 adalah vonisnya. Kalau `tanpa_loot_dan_uang` dan
`uang_saja_tanpa_loot` dua-duanya nol, loot Pandaria tidak rusak, file
perbaikannya tidak perlu dijalankan, dan keluhannya harus dicari dari arah lain
— `Rate.Drop.*` di `config/worldserver.overrides.conf`, atau yang dibunuh
ternyata critter. Bagian 7 sekalian memeriksa kedua portal di atas.

Kalaupun dijalankan tanpa diukur, file itu self-scoping: ia menghitung lingkupnya
dari DB tempat ia dijalankan dan tidak menyentuh satu baris pun kalau tidak ada
yang rusak. Laporan di bagian 7 file itu yang memberi tahu mana yang terjadi.

### Menjalankan file pending dengan tangan

`WorldDatabase.ImportPendingUpdates = 0` di `config/worldserver.overrides.conf`,
jadi isi `sql/pending_updates/world/` **tidak pernah** jalan sendiri. Selama
belum dipromosikan ke `sql/updates/world/`, satu-satunya cara menerapkannya ke
DB yang sedang jalan adalah dengan tangan.

Backup dulu — ketiganya menulis ke `creature_template`, tabel terbesar di world
DB:

```bash
./scripts/backup-db.sh
```

Lalu, urut, dan baca keluaran tiap file sebelum lanjut ke berikutnya:

```bash
docker compose $PW exec -T db mysql -uroot -p"$DB_ROOT_PASSWORD" world \
    < prabowow_pandaria_city_portals.sql
docker compose $PW exec -T db mysql -uroot -p"$DB_ROOT_PASSWORD" world \
    < prabowow_pandaria_mob_health.sql
docker compose $PW exec -T db mysql -uroot -p"$DB_ROOT_PASSWORD" world \
    < prabowow_pandaria_mob_loot_and_gold.sql
```

Ketiganya idempotent — aman diulang. Sesudahnya world perlu restart supaya
`creature_template` dan `gameobject_template` dibaca ulang:

```bash
docker compose $PW restart world
```

Portal langsung terasa sesudah restart. HP baru terasa pada mob yang respawn.

### DB acuan lokal (`sfdb_ref`) untuk audit tanpa VPS

Dump dasar SFDB tidak ada di repo mana pun, tapi ia bisa diimpor sekali ke MySQL
lokal supaya ketiga audit di atas bisa dijalankan tanpa menyentuh VPS:

```bash
mysql -h 127.0.0.1 -u root -e "CREATE DATABASE sfdb_ref DEFAULT CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci;"
mysql -h 127.0.0.1 -u root sfdb_ref < SFDB_full_548_<rilis>_Release.sql
mysql -h 127.0.0.1 -u root --table sfdb_ref < audit_leveling_coverage.sql
```

Dump-nya tidak punya `CREATE DATABASE` maupun `USE` — ia diambil dari skema
bernama `skyfire` — jadi skema tujuan wajib disebut di baris perintah. Tidak
perlu melonggarkan `sql_mode` seperti di produksi: header dump sudah menyetel
`SQL_MODE='NO_AUTO_VALUE_ON_ZERO'` untuk sesinya sendiri. Ukurannya sekitar
290 MB terimpor, 172 tabel, dua sampai lima menit.

**Batasnya.** `sfdb_ref` cuma base, tanpa `sql/updates/world/*` di atasnya.
Angkanya batas bawah, bukan kebenaran — DB yang sedang jalan tetap satu-satunya
otoritas, dan temuan apa pun yang mau dipakai mengubah konten harus
dikonfirmasi ulang ke sana. Skemanya juga bergeser antar rilis: di 24.001
kolomnya `gossip_menu_option`.`menu_id`, di 26.002 sudah `MenuID`, sehingga
`audit_pandaria_intro.sql` bagian 9 berhenti dengan `Unknown column 'MenuID'`
kalau dijalankan pada 24.001. Bagian 10 dan 11 tetap jalan.

### Rilis SFDB: jangan turun versi

| Tag | Aset | Terbit |
|-----|------|--------|
| `sf_db_26` | `SFDB_full_548_26.002_2026_008_18_Release.zip` | 2026-08-15 |
| `sf_db_25` | `SFDB_full_548_25.001_2026_007_19_Release.zip` | 2026-07-19 |
| `24.001` | `SFDB_full_548_24.001_2024_09_04_Release.zip` | 2025-08-06 |

`WORLD_DB_URL` di `.env` sudah menunjuk yang paling baru (`sf_db_26`). Nama
berkasnya memang salah ketik di hulu (`2026_008_18`, tiga digit), tapi tag dan
asetnya nyata — jangan "diperbaiki" jadi tanggal yang masuk akal, nanti malah
404 dan `curl --fail` di `bootstrap-world-db.sh` menggagalkan boot worldserver.

Rilis 24.001 lebih tua dua tingkat; jangan pernah diarahkan ke realm. Lagi pula
tidak ada jalurnya: base dump hanya bisa masuk ke skema kosong, dan seluruh
`sql/updates/world/*` sudah terkunci nama + hash di `skyfire_db_updates`, jadi
menukar base di bawah DB yang sudah jalan bukan operasi yang didukung core.
