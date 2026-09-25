# n8n · Pterodactyl edition

Image Docker untuk **n8n** (workflow automation) yang siap dipakai di panel
**Pterodactyl / Pelican**, dengan pola yang sama seperti [9Router](https://github.com/) edisi SAIRI:

- Build **di GitHub Actions**, bukan di server panel — jadi tidak perlu compile apa pun (n8n punya native module berat: `isolated-vm`, `sqlite3`, `kafka-javascript`) saat server pertama kali diinstal.
- Base image memakai image resmi n8n (`docker.n8n.io/n8nio/n8n`), hanya ditambah lapisan tipis: `bash`, arahkan `HOME`/data ke `/home/container` (volume Pterodactyl), dan parsing `STARTUP` command ala Pterodactyl.
- Data (workflow, credential, database SQLite, encryption key) tersimpan di `/home/container/.n8n`, yaitu volume server yang sudah otomatis disediakan Pterodactyl — aman dari reinstall image.

## Isi repo

| File | Fungsi |
|---|---|
| `Dockerfile` | Bungkus image resmi n8n agar cocok jalan di bawah user/volume Pterodactyl |
| `entrypoint.sh` | Banner info + parsing variabel `{{EGG_VAR}}` dari `STARTUP`, lalu jalankan n8n |
| `egg-n8n.json` | Egg Pterodactyl siap import |
| `docker-compose.yml` | Untuk testing image di komputer sendiri (di luar Pterodactyl) |
| `.github/workflows/docker-publish.yml` | Build multi-arch (amd64+arm64) & push otomatis ke GHCR setiap push ke `main` atau tag `vX.Y.Z` |

## Cara pakai

### 1. Push repo ini ke GitHub kamu sendiri

```bash
git init
git add .
git commit -m "n8n pterodactyl egg"
git branch -M main
git remote add origin https://github.com/USERNAME/n8n-pterodactyl.git
git push -u origin main
```

Setelah push, tab **Actions** di GitHub akan otomatis build image dan push ke
`ghcr.io/USERNAME/n8n-pterodactyl:latest` (pastikan package GHCR-nya diset
**public**, atau siapkan image pull secret di panel bila private).

### 2. Edit `egg-n8n.json`

Ganti bagian `docker_images` dari:

```json
"n8n (GHCR, latest)": "ghcr.io/USERNAME/n8n-pterodactyl:latest"
```

menjadi image GHCR kamu sendiri (ganti `USERNAME`/nama repo sesuai punyamu).

### 3. Import egg ke Pterodactyl

**Admin Panel → Nests → Import Egg** → upload `egg-n8n.json`.

Lalu buat server baru dari egg ini seperti biasa. Alokasikan minimal:
- RAM: 512 MB–1 GB (lebih besar lebih lega, n8n cukup ringan untuk workflow biasa)
- Disk: 1–2 GB (bertambah sesuai jumlah eksekusi/log yang disimpan)

### 4. Variabel penting saat membuat server

| Variabel | Wajib? | Keterangan |
|---|---|---|
| `N8N_ENCRYPTION_KEY` | **Sangat disarankan diisi manual** | String acak bebas (misal hasil `openssl rand -hex 32`). Kalau dikosongkan, n8n generate otomatis — tapi jangan sampai hilang/berubah, karena semua credential tersimpan terenkripsi dengan key ini. |
| `WEBHOOK_URL` | Opsional | Isi domain publik kalau server ini dipasang di belakang domain (untuk trigger webhook dari luar). Kosongkan kalau cuma dipakai internal via IP:Port. |
| `GENERIC_TIMEZONE` | Opsional | Default `Asia/Jakarta`, pengaruh ke node Schedule/Cron. |
| `N8N_SECURE_COOKIE` | Opsional | Set `false` (default) kalau akses masih HTTP biasa/tanpa SSL langsung — kalau dibiarkan `true` tanpa HTTPS, login akan redirect loop. |
| `DB_TYPE` + `DB_POSTGRESDB_*` | Opsional | Default `sqlite` (paling gampang, tanpa setup tambahan). Isi kalau mau pakai PostgreSQL eksternal. |

### 5. Akses n8n

Buka `http://IP-server:PORT` sesuai alokasi Pterodactyl. Setup awal akan minta
membuat akun owner (n8n user management), bukan basic auth.

## Testing lokal (tanpa Pterodactyl)

```bash
docker compose up --build
```

Buka `http://localhost:5678`.

## Update

Update = build image baru (push ke `main` atau buat tag baru `vX.Y.Z`), lalu
**Reinstall/Restart** server di panel supaya image terbaru ditarik. Data di
`/home/container/.n8n` tidak akan terhapus karena tersimpan di volume server,
bukan di dalam image.

## Kenapa tidak build n8n dari source?

Source n8n (`n8n-master.zip`) adalah monorepo pnpm ~280 MB yang perlu proses
build khusus (`pnpm build:docker`) plus kompilasi native module (`isolated-vm`,
`sqlite3`, `@confluentinc/kafka-javascript`) yang butuh toolchain C/C++ dan
waktu build lama. Tim n8n sendiri sudah menyediakan image resmi yang teruji —
jadi cara paling stabil & ringan untuk kebutuhan Pterodactyl adalah membungkus
image resmi tersebut, persis seperti pola `docker/Dockerfile` di 9Router yang
juga tidak mengompilasi ulang semuanya di panel.
