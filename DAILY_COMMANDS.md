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
| Tidak ada portal ke Pandaria di Stormwind / Orgrimmar | Portalnya sebenarnya BERDIRI di kedua kota — SFDB memasangnya sejak rilis 10_to_11. Yang tidak ada itu tujuannya: spell di `data0` tidak punya baris `spell_target_position`. Ukur dengan `audit_pandaria_loot.sql` bagian 7, perbaiki dengan `2026_09_11_world_00.sql` (sudah dipromosikan, sudah jalan) |
| Portal Pandaria diklik tapi pemain tidak pindah | Gejala yang sama persis dengan baris di atas, dan sebabnya juga sama. `spell_punya_tujuan` = 0 di bagian 7 audit memastikannya |
| Portal Pandaria tenggelam separuh ke dalam tanah | Z di baris spawn SFDB persis setinggi tanah, dan `GameObject.cpp:179` memakainya apa adanya tanpa penyesuaian. Dinaikkan `@Z_LIFT` di `2026_09_12_world_00.sql` (sudah dipromosikan). Tinggi pastinya dicari di client — lihat "Menyetel tinggi portal" |
| Portal Pandaria Orgrimmar menghadap arah yang salah | `rotation3` = 1 di baris SFDB membuat `UpdateRotationFields` (`GameObject.cpp:2192`) mengabaikan `orientation`, karena ia hanya menghitung sendiri kalau `rotation2` DAN `rotation3` dua-duanya nol. `2026_09_12_world_00.sql` menolkan keduanya. Hanya Orgrimmar yang kena — `orientation` Stormwind memang 0, jadi (0, 1) di sana kebetulan sudah benar |
| Quest "The King's Command" / "The Art of War" diambil tapi tidak pernah bisa diserahkan | Tiga cacat sekaligus, semuanya di data: 29547 tidak punya penutup sama sekali, objective-nya tipe 0 yang cuma bisa dikredit lewat `KilledMonsterCredit`, dan kredit yang SFDB pasang menempel di NPC yang melayang di udara. Diperbaiki `2026_09_12_world_04.sql` — lihat "Rantai quest intro Pandaria" |
| "Find Grand Admiral Jes-Tereth in the war room" tapi tidak ada siapa-siapa di sana | Benar, ia memang tidak ada: 55579 di SFDB cuma nama + model, npcflag 0, level 1, **tanpa satu pun baris `creature`**. `prabowow_kings_command_jes_tereth.sql` memunculkannya di samping Rell Nightwind dan memindahkan penutup 29547 ke dia — lihat "Jes-Tereth dan 'The King's Command'" |
| "The Mission" / "All Aboard!" minta naik kapal yang tidak bisa dinaiki | Skyfire dan kapal Horde bukan transport di DB ini, cuma kru yang diparkir di ketinggian 358 (map 0) dan 443 (map 1). Sesudah `2026_09_12_world_04.sql`, menerima quest-nya langsung memindahkan pemain ke titik mendarat Jade Forest — pola yang sama dengan Emissary Windsong di Hyjal |
| Mau bikin quest langsung selesai begitu diterima | Jangan setel `quest_template`.`Method` = 0. Jalur autocomplete di `CanCompleteQuest` (`PlayerQuestState.cpp:297`) dijaga `CanTakeQuest`, yang lewat `SatisfyQuestStatus` (`:1143`) sudah `false` begitu quest-nya masuk log — dan `AddQuest` menyetel status INCOMPLETE (`:512`) sebelum memanggilnya (`:559`). Yang bekerja: **hapus baris `quest_objective`-nya**. Tanpa objective, loop-nya tidak punya apa pun untuk digagalkan. Quest 31853 "All Aboard!" memang begitu dari sananya |
| Quest "Unleash Hell" / "Paint it Red!" mentok di Jade Forest | Memang belum bisa selesai dan bukan bug baru: objective-nya bunny kredit tanpa spawn plus mob di phase 1740 yang tidak bisa dimasuki pemain. Tidak ada satu quest pun yang menjadikannya PrevQuestId, jadi questline Jade Forest tetap terbuka — tinggalkan saja di log |
| Mob Pandaria terlalu tebal / lama dibunuh | `2026_09_11_world_01.sql` menurunkan `Health_mod` map 870 jadi 30%. Rate di config tidak bisa dipakai — ia berlaku untuk seluruh realm, tanpa varian per-map |
| Mob Pandaria tidak menjatuhkan apa pun | Jangan langsung menyalin solusi zona Cataclysm. Pandaria konten asli SFDB, bukan hasil port, jadi lootnya bisa saja utuh. Ukur dulu dengan `audit_pandaria_loot.sql` bagian 1 |
| Tidak bisa belajar Wisdom of the Four Winds di pelatih Pandaria | Jendela pelatihnya memang kosong sama sekali: Skydancer Shun (60167) dan Cloudrunner Leng (60166) tidak punya satu pun baris `npc_trainer`, jadi `SendTrainerList` (`NPCHandler.cpp:125`) keluar tanpa mengirim SMSG_TRAINER_LIST. 115913 juga tidak ada di blok referensi mana pun. Diperbaiki `prabowow_pandaria_flying_trainers.sql` — lihat "Pelatih terbang Pandaria" |
| Teleport mage cast-nya jalan tapi pemain tidak pindah | Baris `spell_target_position` untuk spell itu tidak ada di dump SFDB, dan `Spell.cpp:1400-1416` diam-diam memakai posisi pemain sendiri sebagai tujuan. Enam tujuan yang hilang diisi `prabowow_mage_teleport_target_positions.sql` — lihat "Teleport mage dan Roll monk" |
| Roll monk tidak menggerakkan karakter | Bukan data: `spell_monk_roll` memang tidak pernah memanggil API gerak apa pun, seluruh geraknya diserahkan ke efek DBC yang core ini tidak proses. Perbaikannya di C++, jadi butuh build CI dan deploy image baru |

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
| 85-90 | Pandaria | Quest intronya kini dipasang di papan tugas (`prabowow_pandaria_intro_board_and_travel.sql`) plus tumpangan ke Jade Forest, portal ibu kotanya diperbaiki (`2026_09_11_world_00.sql` + `2026_09_12_world_00.sql`), dan rantai quest intronya bisa diselesaikan sampai pemain berdiri di Pandaria (`2026_09_12_world_04.sql`, plus `prabowow_kings_command_jes_tereth.sql` yang masih pending). Kelengkapan spawn **sudah diukur** dan zonanya berisi — lihat "Hasil ukur Pandaria" di bawah |

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

Lima perubahan yang berdiri sendiri. Kelimanya **sudah dipromosikan** ke
`sql/updates/world/` dan sudah jalan sendiri saat worldserver naik:

| Dulu, saat masih pending | Sekarang, sesudah dipromosikan |
|--------------------------|-------------------------------|
| `prabowow_pandaria_city_portals.sql` | `2026_09_11_world_00.sql` |
| `prabowow_pandaria_mob_health.sql` | `2026_09_11_world_01.sql` |
| `prabowow_pandaria_mob_loot_and_gold.sql` | `2026_09_11_world_02.sql` |
| `prabowow_pandaria_city_portal_geometry.sql` | `2026_09_12_world_00.sql` |
| `prabowow_pandaria_intro_chain.sql` | `2026_09_12_world_04.sql` |

⚠️ **File yang sudah dipromosikan tidak boleh diubah lagi.** Hash isinya
tercatat di `skyfire_db_updates`, dan `WorldDatabase.AllowUpdateHashMismatch = 0`
di `config/worldserver.overrides.conf` membuat ketidakcocokan itu **fatal** —
worldserver berhenti di `was already applied with a different hash` dan tidak
pernah naik. Perbaikan susulan selalu masuk ke file pending BARU.

Yang masih pending dari rangkaian ini tinggal satu,
`prabowow_kings_command_jes_tereth.sql` — susulan untuk rantai quest intronya,
di bawah. Karena `WorldDatabase.ImportPendingUpdates = 0`, ia tidak jalan
sendiri — lihat "Menjalankan file pending dengan tangan" di bawah.

**Portal ke Jade Forest** (`2026_09_11_world_00.sql`). Portalnya tidak
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
salah**. Keduanya diperbaiki di `2026_09_12_world_00.sql`, file terpisah --
`2026_09_11_world_00.sql` sudah dipromosikan dan tidak boleh disentuh lagi.

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

⚠️ **`.gobject move` tidak memperbaiki arah hadap.** `SaveToDB`
(`GameObject.cpp:742-743`) menulis rotasi dari nilai yang sedang berlaku, dan
nilai itu (0, 1) yang keliru tadi — jadi memindahkan portal justru menyimpannya
kembali. Yang memperbaikinya `.gobject turn`, yang memanggil
`UpdateRotationFields()` tanpa argumen (`cs_gobject.cpp:406`) sehingga core
menghitung ulang dari `orientation`. Atau cukup jalankan filenya.

Karena itu file geometrinya memakai dua UPDATE dengan penjaga yang berbeda:

| Yang diperbaiki | Penjaganya | Akibatnya |
|-----------------|------------|-----------|
| Rotasi | `rotation2` atau `rotation3` belum nol | Selalu benar, aman diulang, aman juga sesudah `.gobject turn` |
| Tinggi | Z masih persis nilai asli SFDB (toleransi 0.05) | Naik tepat sekali; portal yang sudah kamu pindahkan tangan **tidak** akan ditimpa |

Penjaga tingginya sengaja **bukan** rotasi. Versi pertama file ini memakai sidik
jari `rotation3` = 1 dengan anggapan `.gobject move` akan menghapusnya — anggapan
yang salah, dan akibatnya Z akan naik dua kali di atas posisi yang sudah benar.

**HP mob Pandaria** (`2026_09_11_world_01.sql`). Menurunkan
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

**Loot mob Pandaria** (`2026_09_11_world_02.sql`). ⚠️ Ini
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

### Rantai quest intro Pandaria

`2026_09_12_world_04.sql` (sudah dipromosikan). Quest intronya sudah sampai
ke papan tugas sejak `2026_09_10_world_01.sql`, tapi rantai di belakangnya tidak
jalan: quest diambil, lalu berhenti di situ selamanya.

⚠️ Sisi Alliance-nya disusul `prabowow_kings_command_jes_tereth.sql` — penutup
29547 pindah dari Rell Nightwind ke Grand Admiral Jes-Tereth, dan quest-nya
selesai begitu diterima. Baca dua bagian ini berurutan; yang di bawah menang.

| | Alliance | Horde |
|---|---|---|
| Breadcrumb papan | 29547 The King's Command | 29611/29612 The Art of War |
| Lanjutannya | 29548 The Mission | 31853 All Aboard! |
| Sesudah itu | 31732 Unleash Hell | 29690 Into the Mists → 31765 Paint it Red! |

Rantainya lewat `NextQuestIdChain`; `PrevQuestId` nol di semuanya, jadi tidak
ada yang saling mengunci.

**Empat cacat, semuanya di data.**

1. 29547 **tidak punya penutup sama sekali** — bukan creature, bukan
   gameobject. Satu-satunya quest di rantai itu yang begitu.
2. Semua objective di rantai ini `quest_objective`.`type` = 0
   (`QUEST_OBJECTIVE_TYPE_NPC`), dan core ini cuma mengkreditnya dari
   `Player::KilledMonsterCredit` (`PlayerQuestState.cpp:1850`).
   `Player::TalkedToCreature` (`:2004`) hanya melayani tipe 3
   (`NPC_INTERACT`). Jadi "Stormwind Keep visited" dan "Report to Grommash
   Hold" **tidak bisa** didapat dengan masuk ruangannya atau mengajak bicara —
   keduanya butuh kill credit, dan tidak ada satu pun di DB yang memicunya.
   Bunny 55567 bahkan tidak punya spawn.
3. SFDB sebenarnya sudah memasang dua kreditnya — tapi di NPC yang tidak bisa
   didatangi. Sky Admiral Rogers (66292) dan General Nazgrim (55054) punya
   script gossip-select yang mengkredit objective lalu memindahkan pemain ke
   Pandaria (itulah tumpangan gunship/kapal versi retail). Rogers berdiri di
   dek Skyfire pada `(-7879.8, 1279.5, 358.6)` map 0, Nazgrim pada
   `(1862.3, -5461.9, 443.8)` map 1. Dua-duanya melayang di atas ibu kota, dan
   kapalnya bukan transport di DB ini — cuma kru yang diparkir, 74 NPC di dek
   Skyfire, semuanya phase 0.
4. Penutup 31853 dan pemberi 29690 adalah Nazgrim yang melayang itu juga, jadi
   rantai Horde tetap buntu walau kreditnya sudah jalan. Alliance lebih
   beruntung: Rogers punya spawn kedua tanpa phase di
   `(-664.9, -1483.3, 130.2)` map 870, empat yard dari titik mendarat portal.

**Perbaikannya** mengikuti bentuk yang sama dengan breadcrumb Hyjal di
`2026_09_09_world_07.sql` — penerbangan yang tidak bisa diport diganti teleport
saat quest diterima:

- Rell Nightwind menutup "The King's Command" di Stormwind Keep, dan mengkredit
  "Stormwind Keep visited" begitu diajak bicara. Ia sudah jadi pemberi "The
  Mission", jadi serah-terima dan quest berikutnya terjadi dalam satu jendela.
- Menerima "The Mission" dari Rell memindahkan pemain ke Jade Forest, di
  sebelah Sky Admiral Rogers. Itu tumpangan Skyfire-nya.
- General Nazgrim di Grommash Hold mengkredit "Report to Grommash Hold" saat
  disapa, dan menerima "All Aboard!" darinya memindahkan pemain ke titik
  mendarat Horde. Itu kapalnya.
- General Nazgrim di titik mendarat (55135) juga menutup "All Aboard!", memberi
  "Into the Mists", dan mengkredit "Discovered Pandaria" — yang memang benar,
  pemainnya sedang berdiri di Pandaria.

Titik mendaratnya bukan tebakan: itu tujuan spell tumpangan milik SFDB sendiri,
dibaca dari `spell_target_position` (130321 Alliance, 125060 Horde), pasangan
yang sama dengan yang dipakai Pandaria Emissary.

`npcflag` tidak diubah. Rell (55789) dan kedua Nazgrim (54870, 55135) itu
npcflag 2 — questgiver tanpa bit gossip — jadi client mengirim
`CMSG_QUEST_GIVER_HELLO`, bukan gossip hello. Jalur itu tetap memanggil hook
AI-nya: `QuestHandler.cpp:147` memanggil `OnGossipHello()` sebelum menyusun menu
quest, dan `SmartAI::OnGossipHello` (`SmartAI.cpp:732`) memicu
`SMART_EVENT_GOSSIP_HELLO` lalu mengembalikan `_gossipReturn`, yang tidak pernah
diset `true` oleh apa pun di `SmartScript`. Kreditnya masuk lebih dulu, tanda
serah-terimanya muncul di jendela yang sama.

**Di mana ia berhenti, dan kenapa.** Quest yang dipegang pemain di ujungnya —
31732 Unleash Hell (Alliance) dan 31765 Paint it Red! (Horde) — adalah
pertempuran gunship yang di retail seluruhnya script C++, dan itu tidak bisa
diperbaiki dari data. 31732 menuntut dua kill credit (66400 Bladefist Reaper,
66401 Stygian Scar) yang tidak punya spawn, dan dua objective yang bisa dibunuh
(66398, 66397) cuma ada di phase 1740 — phase yang tidak bisa dimasuki pemain,
karena core ini hanya memberi phase dari aura, spell dan SmartAI, sementara
`phase_area` (`ObjectMgr.cpp:9045`) dibaca **hanya** untuk mencegah phase
dilepas. Objective 31733, 31765, 31766, 31767 dan 31769 semuanya bunny kredit
tanpa spawn juga.

Tidak ada yang hilang karena berhenti di sini: **tidak ada satu quest pun di
seluruh DB yang menjadikan rantai ini `PrevQuestId`**, dan 136 dari 150 quest
Jade Forest punya pemberi yang tidak di-phase. Questline zonanya terbuka penuh
tanpa rantai intro ini.

### Jes-Tereth dan "The King's Command"

`prabowow_kings_command_jes_tereth.sql`, masih pending. Susulan untuk sisi
Alliance-nya, karena perbaikan di atas menambal mekanismenya tapi salah orang.

Teks quest-nya sendiri yang jadi buktinya, dibaca dari dump SFDB:

| Kolom | Isi |
|-------|-----|
| `Objectives` | "Find Grand Admiral Jes-Tereth in the war room at Stormwind Keep in Stormwind City." |
| `Details` | "...Please come to Stormwind Keep immediately for a briefing with King Varian Wrynn. **I will be waiting in the King's war room.**" |
| `QuestGiverTargetName` | "Grand Admiral Jes-Tereth" |

Jadi yang dicari pemain memang Jes-Tereth, bukan Rell. `2026_09_12_world_04.sql`
menjadikan Rell penutupnya karena ia satu-satunya NPC yang benar-benar berdiri
di war room dan sudah jadi pemberi quest berikutnya — mekanismenya jalan, tapi
tidak ada yang memberi tahu pemain untuk menyapanya, jadi praktiknya tetap
buntu.

Sebabnya: **Jes-Tereth tidak pernah dimunculkan.** `creature_template` 55579 ada
— nama, model 39240 — tapi `npcflag` 0, `AIName` kosong, level 1/1, dan **nol
baris di tabel `creature`**. Ia nama dan model, tidak lebih. War room-nya
sendiri nyaris kosong: spawn terdekat dari Rell di dump SFDB ada 13 yard
jauhnya.

Yang dilakukan file ini:

1. **Objective 29547 dihapus**, jadi quest-nya selesai begitu diterima.
2. 55579 diberi `npcflag` bit questgiver, `AIName` SmartAI, level 90, lalu
   di-spawn 2,5 yard di sebelah Rell — posisinya diturunkan dari baris spawn
   Rell sendiri, bukan diketik. Kalau rilis SFDB berikutnya memunculkannya
   sendiri dalam radius 30 yard dari Rell, file ini mengalah dan tidak menambah
   apa-apa.
3. Penutup 29547 pindah dari Rell ke dia, dan ia ikut jadi pemberi "The
   Mission" — Rell tetap memberi juga. Karena `NextQuestIdChain` 29547 → 29548
   dan sekarang satu NPC memegang keduanya, serah-terima dan quest berikutnya
   terjadi dalam satu jendela, lalu teleport ke Jade Forest yang sama.

**Kenapa objective-nya dihapus, bukan `Method` disetel 0.** `Method` = 0 itu
jebakan yang kelihatan benar: `Quest::IsAutoComplete()` memang persis
`Method == 0` (`QuestDef.cpp:199`), dan `CanCompleteQuest` punya jalan pintas
untuknya di `PlayerQuestState.cpp:297`. Jalan pintas itu dijaga
`CanTakeQuest(qInfo, false)`, dan `CanTakeQuest` (`:249`) menjalankan
`SatisfyQuestStatus` (`:1143`) yang mengembalikan `false` begitu quest-nya ada
di log dengan status apa pun. `AddQuest` menyetel status INCOMPLETE (`:512`)
sebelum sampai ke `if (CanCompleteQuest(questId)) CompleteQuest(questId)`
(`:559`) — jadi saat dipanggil, pintasnya sudah tertutup dan yang menentukan
tinggal loop objective. Tanpa baris objective, loop itu tidak punya apa pun
untuk digagalkan: `true`, dan quest-nya selesai di detik yang sama ia diterima.
Bukan akal-akalan — quest 31853 "All Aboard!" aslinya memang tanpa objective
dan berperilaku begitu.

Baris yang dihapus bisa dikembalikan; di dump SFDB ia
`(259891, 0, 0, 55567, 1, 0, 'Stormwind Keep visited')`. Kill credit 55567 itu
sendiri tidak punya spawn dan tidak dipanggil script mana pun di seluruh DB —
itulah kenapa ia tidak pernah bisa didapat.

**Pemain yang terlanjur memegang quest-nya** tidak ikut selesai hanya karena
objective-nya hilang — tidak ada yang menjalankan ulang `CanCompleteQuest`
untuknya. Karena itu Jes-Tereth memanggil
`SMART_ACTION_CALL_AREAEXPLOREDOREVENTHAPPENS` (15) saat disapa, yang berakhir
di `if (CanCompleteQuest) CompleteQuest` (`PlayerQuestState.cpp:1722`). Jadi
cukup datangi dia. Baris sisa di `character_queststatus_objectives` mereka
dilewati saat load (`Player.cpp:13809` — id objective-nya tidak lagi menunjuk
ke quest mana pun), bukan error.

### Teleport mage dan Roll monk

Dua skill yang rusak karena dua sebab yang sama sekali berbeda. Yang satu data
yang hilang di DB, yang satu kode yang memang tidak pernah ada.

**Teleport mage** (`prabowow_mage_teleport_target_positions.sql`, masih pending).
Mage Alliance cuma bisa Teleport ke Stormwind dan Exodar; tujuan lain cast-nya
selesai, animasinya jalan, cooldown-nya jalan, tapi pemain tetap berdiri di
tempat yang sama.

Spell Teleport memakai target `TARGET_DEST_DB`: koordinatnya bukan di DBC,
melainkan di tabel `spell_target_position`. Kalau barisnya tidak ada,
`Spell::SelectImplicitCasterDestTargets` (`Spell.cpp:1400-1416`) **tidak**
menggagalkan cast — ia memakai posisi pemain sendiri sebagai tujuan. Diamnya
total: pengecekan kelengkapan saat boot dikomentari (`SpellMgr.cpp:1585-1616`)
dan miss saat cast cuma `SF_LOG_DEBUG`. Yang berisik justru baris yang ADA tapi
salah, bukan yang hilang — itu sebabnya cacat ini bertahan lama.

Dump dasar SFDB memang bolong. Enam yang tidak punya tujuan:

| Spell | Tujuan | Map | Koordinat |
|-------|--------|-----|-----------|
| 3562 | Teleport: Ironforge | 0 | -4613.71, -915.287, 501.062, o 0 |
| 3565 | Teleport: Darnassus | 1 | 9656.54, 2518.26, 1331.66, o 0 |
| 3566 | Teleport: Thunder Bluff | 1 | -967.375, 284.82, 110.773, o 3.19999 |
| 49359 | Teleport: Theramore | 1 | -3748.11, -4440.21, 30.5688, o 3.95172 |
| 88342 | Teleport: Tol Barad (A) | 732 | -369.208, 1058.73, 21.7719, o 0.634577 |
| 88344 | Teleport: Tol Barad (H) | 732 | -603.724, 1387.62, 22.0498, o 0.469644 |

Angkanya bukan tebakan. Dua sumber yang tidak berhubungan sepakat sampai digit
terakhir, termasuk `effIndex` yang semuanya 0: tabel `spell_target_position`
di dump world TrinityCore 4.3.4, dan baris "Portal Effect" MoP milik SFDB
sendiri (121849 Darnassus, 121851 Ironforge, 121858 Theramore, 121859 Thunder
Bluff, 121860/121861 Tol Barad) — yaitu titik mendarat portal grup yang sekarang
sudah jalan. Wajar keduanya sama: Teleport dan Portal ke kota yang sama memang
mendarat di titik yang sama.

Karena itu jalan buntu yang dulu membuat `2026_09_11_world_00.sql` **menolak**
menambah baris `spell_target_position` tidak berlaku di sini. Di sana
`effIndex`-nya harus ditebak; di sini terbaca dari data.

Spell **Portal** grup sengaja tidak disentuh: rantai portal MoP tidak lewat
spell itu, melainkan lewat "Portal Effect" 121847-121862 yang barisnya sudah
lengkap.

Verifikasinya berlapis. Sebelum dan sesudah, lihat isinya sendiri:

```bash
docker compose $PW exec -T db mysql -uroot -p"$DB_ROOT_PASSWORD" world -e "SELECT id, effIndex, target_map, target_position_x, target_position_y, target_position_z, target_orientation FROM spell_target_position WHERE id IN (3561,3562,3563,3565,3566,3567,32271,32272,33690,35715,49358,49359,53140,88342,88344,89597) ORDER BY id;"
```

Lalu, sesudah restart, dua hal di log: `>> Loaded N spell teleport coordinates`
(`SpellMgr.cpp:1617`) naik enam, dan `sql.sql` bersih dari
`does not have target TARGET_DEST_DB (17)` (`SpellMgr.cpp:1578`). Baris itulah
jaring pengamannya — kalau `effIndex` sebuah baris keliru, ia berteriak setiap
boot, bukan diam. Terakhir di game: Teleport ke Ironforge, Darnassus, Theramore
dan Tol Barad, dengan Stormwind sebagai pembanding yang memang sudah jalan.

**Roll monk** (core PR, bukan SQL). `spell_monk_roll` cuma memasang aura 107427
dan menyerahkan seluruh gerakan ke efek DBC yang core ini tidak proses sama
sekali — jadi cast selesai, animasi guling jalan, monk-nya diam di tempat.

Perbaikannya di C++: script-nya sekarang menggerakkan sendiri, pola yang sama
dengan Heroic Leap dan Shadowstep di fork ini. Jarak, kecepatan dan arah tinggal
di `SpellMovementMetadata` sebagai fungsi murni supaya ikut teruji
`game_domain_tests` tanpa server. Arahnya mengikuti tombol yang ditekan (mundur
menang atas strafe), dan `GetFirstCollisionPosition` menahannya di dinding.

Dipakai `MoveJump`, bukan `MoveCharge`: `MoveCharge` (`MotionMaster.cpp:395`)
diam-diam `return` kalau `MOTION_SLOT_CONTROLLED` sedang terpakai — persis cara
gerakan itu hilang lagi tanpa jejak.

Karena ini C++, ia **tidak** bisa diterapkan lewat SQL: butuh build CI lalu
image baru (`gh workflow run deploy.yml`). Chi Torpedo bentuknya sama persis dan
kemungkinan besar rusak dengan cara yang sama, tapi sengaja belum ikut — daftar
spell yang sudah bisa bergerak sendiri akan membuat pemainnya terlempar dua kali.
Uji dulu di game, baru tambahkan.

### Pelatih terbang Pandaria

`prabowow_pandaria_flying_trainers.sql`, masih pending. Level 90 berdiri di
depan pelatih terbang di Shrine of Two Moons atau Shrine of Seven Stars dan
tidak bisa belajar Wisdom of the Four Winds — spell yang menyalakan terbang di
Pandaria. Bukan cuma spell itu yang hilang: jendelanya kosong sama sekali.

Sebabnya bukan NPC-nya. Skydancer Shun (60167) berdiri di 1555.22 890.88 478.43
dan Cloudrunner Leng (60166) di 911.60 349.37 510.97, dua-duanya map 870 tanpa
phase, faction 2481, `npcflag` 80 — UNIT_NPC_FLAG_TRAINER (0x10) plus
UNIT_NPC_FLAG_TRAINER_PROFESSION (0x40), pasangan yang sama dengan semua pelatih
tunggangan lain di dump. Yang tidak ada itu **barisnya di `npc_trainer`**: nol,
bukan kurang. `SendTrainerList` (`NPCHandler.cpp:125`) tidak menemukan data
spell untuk entry itu, menulis "Training spells not found for creature" (`:128`),
lalu keluar tanpa mengirim SMSG_TRAINER_LIST.

22 pelatih tunggangan lain di dump tidak menuliskan spell-nya satu per satu;
mereka menunjuk blok referensi — `npc_trainer`.`spell` = -200300 (darat) atau
-200301 (darat + terbang). `ObjectMgr::LoadTrainerSpell` (`:8109`) membuka blok
itu lewat `INNER JOIN npc_trainer AS b ON a.entry = -(b.spell)`, dan
`AddSpellToTrainer` (`:8026`) menolak menjadikan blok itu sendiri sebagai
pelatih karena entry-nya ≥ SKYFIRE_TRAINER_START_REF (200000). Dua pelatih
Pandaria ini memang tidak pernah ditautkan ke blok mana pun.

115913 sendiri juga tidak ada di blok mana pun. Di seluruh dump ia tidak muncul
sekali pun di `npc_trainer`, jadi tidak ada satu pelatih pun di realm ini yang
bisa mengajarkannya.

Yang perlu dipahami: memberi pemain spell itu **sudah cukup**. Tidak ada gerbang
lain di core. `Player::IsKnowHowFlyIn` (`Player.cpp:21305`) cuma mengurus map
571, Northrend. Naik tunggangan lewat `Unit::GetMountCapability`
(`Unit.cpp:3830`), yang melewatkan baris MountCapability.dbc mana pun yang
`RequiredSpell`-nya belum dimiliki pemain (`:3879`) — dan baris terbang Pandaria
menyebut 115913. Itu juga sebabnya character boost core ini menulis persis spell
itu ke `character_spell` (`CharacterBoost.h:549`). Tidak ada perubahan C++ di
sini, jadi tidak perlu build CI.

Masing-masing pelatih dapat dua baris: referensi -200301 (tangga lengkap
Apprentice sampai Master Riding, plus Flight Master's License dan Cold Weather
Flying — daftar yang sama yang dibagikan Roxi Ramrocket dan Hira Snowdawn), dan
satu baris langsung untuk 115913 seharga 2500g, level 90, skill riding (762)
nilai 225. Angka 225 itu Expert Riding, batas yang sama yang dipakai blok 200301
untuk Cold Weather Flying (54198) dan Flight Master's License (90269) — dua
pembuka terbang per-benua lainnya.

115913 ditaruh di NPC-nya, bukan di dalam blok 200301, supaya 20 pelatih yang
ikut blok itu tidak ikut berubah. Kalau nanti terbang Pandaria memang boleh
dilatih dari Azeroth juga, memindahkannya ke dalam blok cuma satu baris.

Ia juga ditulis apa adanya, bukan lewat spell "pengajar". Isi blok 200301 semua
pembungkus sisi-caster — 33389 mengajarkan 33388, 34092 mengajarkan 34090, 90266
mengajarkan 90265 — tapi pembungkus untuk 115913 tidak ada di data ini, dan
memang tidak perlu: `AddSpellToTrainer` menyetel `learnedSpell[0]` ke spell itu
sendiri kalau ia tidak punya SPELL_EFFECT_LEARN_SPELL (`:8074`), lalu
`HandleTrainerBuySpellOpcode` memanggil `Player::learnSpell` untuknya
(`NPCHandler.cpp:278`).

Dua pelatih pandaren di ibu kota sengaja tidak disentuh — mereka tidak berdiri
di Pandaria dan bukan yang dilaporkan, jadi perbaikannya file lain: Softpaws
(70301, Orgrimmar) cuma mengajar Apprentice dan Journeyman, dan Mei Lin (70296,
Stormwind) `npcflag`-nya 0, jadi dia bahkan bukan pelatih.

### Mencari id spell dari DBC

Berulang kali mentok di hal yang sama: `effIndex`, nama, dan id spell ada di
`Spell.dbc`, tidak di SQL, jadi tidak bisa dibaca lewat query. Jalan keluarnya
GM command, yang memang membaca DBC:

```
.lookup spell Teleport: Ironforge
.lookup spell Shrine of Two Moons
```

Ini cara baku mencari id sebelum menulis baris `spell_target_position` baru —
terutama untuk Teleport/Portal ke Shrine of Two Moons dan Shrine of Seven Stars,
yang id-nya tidak muncul di tabel mana pun di dump SFDB dan karena itu belum
dikerjakan.

### Menjalankan file pending dengan tangan

`WorldDatabase.ImportPendingUpdates = 0` di `config/worldserver.overrides.conf`,
jadi isi `sql/pending_updates/world/` **tidak pernah** jalan sendiri. Selama
belum dipromosikan ke `sql/updates/world/`, satu-satunya cara menerapkannya ke
DB yang sedang jalan adalah dengan tangan.

Lima file Pandaria di atas sudah dipromosikan, jadi worldserver yang
menerapkannya sendiri. Yang tersisa untuk dijalankan dengan tangan ada tiga:
Jes-Tereth, tujuan Teleport mage, dan pelatih terbang Pandaria.

Backup dulu:

```bash
./scripts/backup-db.sh
```

Lalu jalankan, dan baca laporan di keluarannya:

```bash
docker compose $PW exec -T db mysql -uroot -p"$DB_ROOT_PASSWORD" world \
    < prabowow_kings_command_jes_tereth.sql
```

```bash
docker compose $PW exec -T db mysql -uroot -p"$DB_ROOT_PASSWORD" world \
    < prabowow_mage_teleport_target_positions.sql
```

```bash
docker compose $PW exec -T db mysql -uroot -p"$DB_ROOT_PASSWORD" world \
    < prabowow_pandaria_flying_trainers.sql
```

File pelatih terbang idempotent — ia menghapus lalu menulis ulang empat barisnya
sendiri di `npc_trainer`. Di laporannya, kedua pelatih harus punya
`spells_via_ref` = 7 dan `spells_direct` = 1, dan tabel kedua harus memuat 115913
sekali untuk masing-masing, di `spellcost` 25000000 dengan `reqlevel` 90. Kalau
`spells_via_ref` 0, blok referensi 200301 tidak ada di DB itu dan tangga riding
biasanya ikut hilang — baris 115913-nya tetap jalan. Efeknya terasa sesudah
`.reload npc_trainer` atau restart world; tidak perlu image baru, tidak ada
perubahan C++ di sini.

File Teleport itu idempotent — ia menghapus dan menulis ulang enam
baris `spell_target_position` miliknya sendiri. Laporannya menandai setiap
spell Teleport dengan `ADA` atau `HILANG`; sesudah file ini jalan tidak boleh
ada satu pun yang `HILANG`. Efeknya terasa sesudah restart, atau langsung
dengan `.reload spell_target_position`.

File Jes-Tereth idempotent juga — aman diulang, dan spawn-nya dilewati kalau
sudah ada Jes-Tereth lain dalam radius 30 yard dari Rell. Di laporannya:
`objectives` untuk 29547 harus 0, 29547 harus punya tepat satu `enders`, 29548
dua `givers`, dan baris Jes-Tereth harus `ai` = SmartAI dengan `spawns` ≥ 1.
Kalau `spawns` 0, ia masih belum ada di dunia dan quest-nya tetap tidak bisa
diserahkan. Sesudahnya world perlu restart, karena `AIName` baru dibaca saat
creature-nya dibuat:

```bash
docker compose $PW restart world
```

Tanpa restart, `.reload creature_questender`, `.reload creature_queststarter`
dan `.reload smart_scripts` sudah memasang relasi dan script-nya, tapi NPC-nya
tetap tanpa AI sampai dibuat ulang — dan spawn baru memang cuma muncul setelah
`creature` dibaca ulang.

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
