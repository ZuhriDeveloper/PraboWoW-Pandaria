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
| Quest "As Hyjal Burns" mentok di Moonglade | Batalkan lalu ambil lagi dari Emissary Windsong — teleportnya menyala saat quest diterima |

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
| 85-90 | Pandaria | Quest dan tautan quest giver ada di SFDB; kelengkapan spawn-nya **belum diukur** — jalankan audit di atas |

Port zona baru dibuat dengan `tools/dev/port_zone_spawns.py --zone <nama>` di
repo core, dari dump world TrinityCore 4.3.4. Dump itu tidak punya konten
Pandaria sama sekali, jadi kalau audit menunjukkan Pandaria juga kosong,
sumbernya harus dicari di tempat lain — bukan dari dump 4.3.4.

**Catatan phasing.** Semua spawn hasil port dipasang di phase 0 supaya terlihat
semua pemain. Zona Cataclysm aslinya berubah bentuk mengikuti kemajuan quest
lewat script C++ yang tidak ada di SkyFire; tanpa perataan itu zonanya tetap
terlihat kosong. Harganya: beberapa versi area yang sama tampil bersamaan, dan
quest yang kemajuannya bergantung pada perubahan fase tidak akan selesai.
