# Panduan Pemain — Menyambung ke Server

## Yang dibutuhkan

Client **World of Warcraft: Mists of Pandaria versi 5.4.8 build 18414**.

Versi lain tidak bisa. Server memvalidasi build number saat login dan menolak
client yang tidak cocok.

Cara mengecek versi: jalankan client, lihat pojok kiri bawah layar login.
Harus tertulis `5.4.8 (18414)`.

## Langkah

### 1. Arahkan client ke server

Buka file `WTF\Config.wtf` di folder client dengan Notepad.

Cari baris yang diawali `SET realmlist` dan ubah menjadi:

```
SET realmlist "ALAMAT_SERVER"
```

Kalau baris itu tidak ada, tambahkan saja di baris paling bawah.

Ganti `ALAMAT_SERVER` dengan alamat yang diberikan admin.

### 2. Hapus cache

Hapus folder `Cache` di dalam folder client. Folder ini dibuat ulang otomatis.

Melewatkan langkah ini adalah penyebab paling umum error aneh setelah pindah
server.

### 3. Masuk

Jalankan `Wow.exe` — **bukan** launcher. Launcher akan mencoba memperbarui
client ke versi terbaru dan merusak instalasi 5.4.8.

Masukkan username dan password akun yang dibuatkan admin.

## Kalau bermasalah

| Gejala | Penyebab biasanya |
|---|---|
| "Unable to connect" | `realmlist` salah ketik, atau server sedang mati |
| Realm abu-abu / offline | worldserver sedang restart, tunggu beberapa menit |
| Login sukses tapi macet di layar pilih karakter | Masalah di sisi server, laporkan ke admin |
| "This account has been suspended" | Salah password 5 kali, ban otomatis 10 menit |
| Versi client salah | Pastikan `5.4.8 (18414)`, jangan jalankan launcher |

## Buat akun

Registrasi lewat web belum tersedia. Minta admin membuatkan akun.
