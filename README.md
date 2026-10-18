# n8n · Pterodactyl edition

Image Docker untuk **n8n** (workflow automation tool) yang dibungkus agar
langsung siap jalan sebagai server di panel **Pterodactyl / Pelican**.

Pendekatannya: image resmi n8n dijadikan base, lalu ditambah lapisan tipis supaya
cocok dengan cara Wings (daemon Pterodactyl) menjalankan container — bukan build
ulang aplikasinya dari source.

## Cara pasang di panel

1. Panel admin → **Nests** → pilih/buat nest → **Import Egg** → `egg-n8n.json`.
2. Buat server dengan egg **n8n** (disarankan RAM ≥ 1 GB, disk ≥ 2 GB).
3. Nyalakan. Setelah status **Running**, buka `http://IP:PORT` server lalu buat
   akun owner n8n.

Image: `ghcr.io/sairidev/n8n:latest`. Kalau package GHCR-nya private, node Wings
perlu login `ghcr.io` (lihat `docker.registries` di `/etc/pterodactyl/config.yml`).

### Variabel Startup

| Variabel | Fungsi |
|---|---|
| Bahasa console (`CONSOLE_LANGUAGE`) | `id` / `en` untuk banner, pesan, dan peringatan di console. Editor n8n tetap bahasa Inggris (n8n resmi hanya menyediakan `en`) |
| URL publik (`WEBHOOK_URL`) | Alamat n8n dari luar, mis. `https://n8n.domainkamu.com`. Kosong = `http://IP:PORT` server |
| HTTPS otomatis (`HTTPS_TUNNEL`) | `1` = alamat `https://xxx.trycloudflare.com` gratis lewat Cloudflare Tunnel, tanpa domain. Berubah tiap restart; n8n mendaftarkan ulang webhook trigger (Telegram dll.) sendiri |
| Token Cloudflare Tunnel (`CLOUDFLARE_TUNNEL_TOKEN`) | Domain sendiri yang tetap: Public Hostname tunnel → `http://localhost:PORT`, lalu isi URL publik dengan domain itu |
| Cookie aman (`N8N_SECURE_COOKIE`) | `true` hanya kalau dibuka lewat HTTPS. Lewat HTTP biasa harus `false`, kalau tidak login berputar terus |
| Di belakang reverse proxy (`N8N_PROXY_HOPS`) | `1` kalau lewat Nginx/Cloudflare Tunnel |
| Zona waktu (`GENERIC_TIMEZONE`) | Untuk node Schedule/Cron |

Port mengikuti alokasi server, dan batas memori Node.js mengikuti RAM server di panel.

## Bagaimana image ini bekerja

- **Dibangun otomatis di GitHub Actions** setiap push ke `main` (hanya `linux/amd64`),
  lalu diuji jalan seperti di Wings: user non-root, volume `/home/container`,
  `STARTUP`, port panel, sampai `/healthz` n8n menjawab.
- **Base image** `n8nio/n8n:stable` dari Docker Hub. `docker.n8n.io` tidak dipakai
  karena membatasi runner GitHub Actions (429 Too Many Requests). Versi lain bisa
  dipilih lewat *Run workflow* → `n8n_version`.
- **Data** (workflow, credential, database SQLite, encryption key) di
  `/home/container/.n8n` — volume server Pterodactyl, aman dari restart/update image.
- **`tini` tetap PID 1** seperti image resmi, entrypoint memakai `sh` biasa (tidak
  bergantung pada bash/apk yang bisa hilang di image n8n versi baru).

## Isi repo

| File | Fungsi |
|---|---|
| `Dockerfile` | Bungkus image resmi n8n agar cocok jalan di bawah user/volume Pterodactyl |
| `entrypoint.sh` | Banner info, port & URL publik, batas memori, parsing `{{EGG_VAR}}` dari `STARTUP` |
| `egg-n8n.json` | Egg Pterodactyl siap import |
| `docker-compose.yml` | Untuk menjalankan/testing image di luar Pterodactyl |
| `.github/workflows/docker-publish.yml` | Build & push ke GHCR, lalu uji jalan seperti Wings |

## Lisensi

n8n sendiri berlisensi Apache-2.0 with n8n fair-code; repo ini hanya
membungkus image resminya, lihat `LICENSE` untuk repo ini.
