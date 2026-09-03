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
dikenal saat login, NPC "Heirloom Vendor" di tiap titik spawn karakter baru,
dan karakter baru dapat surat berisi tas 36 slot (item 23162).

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

---

## 🔍 TROUBLESHOOTING QUICK CHECKLIST

| Problem | Solution |
|---------|----------|
| Realm offline | Check `docker compose $PW ps`, pastikan `world` running |
| Player stuck character screen | Check `realmlist.address` bukan localhost; harus DNS only di Cloudflare |
| World crash saat start | Check TTY settings di compose — `tty: true` dan `stdin_open: true` harus ada |
| Legacy OpenSSL error | Build ulang deps: `gh workflow run build-deps-image.yml` |
| Can't connect (Unable to connect) | Check firewall/DNS; `realmlist` salah ketik |
