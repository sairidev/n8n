# n8n · Pterodactyl edition

Image Docker untuk **n8n** (workflow automation tool) yang dibungkus agar
langsung siap jalan sebagai server di panel **Pterodactyl / Pelican**.

Pendekatannya sama seperti pola `docker/Dockerfile` di 9Router edisi SAIRI:
image resmi dijadikan base, lalu ditambah lapisan tipis supaya cocok dengan
cara Wings (daemon Pterodactyl) menjalankan container — bukan build ulang
aplikasinya dari source.

## Kenapa repo ini ada

n8n resmi tidak punya varian image yang didesain untuk jalan di bawah
Pterodactyl/Pelican: user/uid dinamis dari panel, volume data yang harus
diarahkan ke `/home/container`, port yang mengikuti alokasi panel
(`SERVER_PORT`), dan startup command yang di-parse dari variabel
`{{EGG_VAR}}` ala egg Pterodactyl. Repo ini mengisi celah itu — n8n bisa
di-deploy sebagai server di panel sama gampangnya seperti egg lain, tanpa
perlu VPS terpisah atau setup manual di luar panel.

## Kenapa tidak build n8n dari source

Source n8n adalah monorepo pnpm yang berat untuk dibuild (perlu
`pnpm build:docker`) dan punya beberapa native module (`isolated-vm`,
`sqlite3`, `@confluentinc/kafka-javascript`) yang butuh toolchain C/C++ serta
waktu compile lama. Tim n8n sendiri sudah menyediakan image resmi
(`docker.n8n.io/n8nio/n8n`) yang teruji, jadi cara paling stabil dan ringan
adalah membungkus image tersebut, bukan mengompilasi ulang semuanya.

## Bagaimana image ini bekerja

- **Dibangun otomatis di GitHub Actions**, bukan di server panel — jadi
  server yang baru diinstal tidak perlu compile apa pun, cukup tarik image
  jadi dari registry.
- **Base image** tetap image resmi n8n; lapisan tambahan hanya berupa
  `bash`, `curl`, `tzdata`, pengalihan `HOME`/data ke `/home/container`, dan
  logika startup ala Pterodactyl.
- **Data** (workflow, credential, database SQLite, encryption key) disimpan
  di `/home/container/.n8n`, yaitu volume server yang sudah otomatis
  disediakan Pterodactyl — jadi aman dari reinstall/update image.
- **Multi-arch**: image dipublikasikan untuk `linux/amd64` dan
  `linux/arm64`, jadi jalan baik di panel berbasis x86 maupun ARM.

## Isi repo

| File | Fungsi |
|---|---|
| `Dockerfile` | Bungkus image resmi n8n agar cocok jalan di bawah user/volume Pterodactyl |
| `entrypoint.sh` | Banner info + parsing variabel `{{EGG_VAR}}` dari `STARTUP`, lalu jalankan n8n |
| `egg-n8n.json` | Egg Pterodactyl siap import, mendefinisikan variabel & startup command server |
| `docker-compose.yml` | Untuk menjalankan/testing image di luar Pterodactyl |
| `.github/workflows/docker-publish.yml` | Build multi-arch (amd64+arm64) & push otomatis ke GHCR |

## Lisensi

n8n sendiri berlisensi Apache-2.0 with n8n fair-code; repo ini hanya
membungkus image resminya, lihat `LICENSE` untuk repo ini.
