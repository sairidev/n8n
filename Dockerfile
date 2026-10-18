# syntax=docker/dockerfile:1.7
#
# n8n · Pterodactyl edition
#
# Tidak build n8n dari source (butuh compiler untuk native module: isolated-vm,
# sqlite3, kafka-javascript — berat & lama). Image resmi n8n dipakai sebagai base,
# lalu ditambah lapisan tipis agar cocok jalan di bawah Pterodactyl/Pelican Wings:
# HOME & data dir diarahkan ke /home/container (volume server panel), port mengikuti
# alokasi panel (SERVER_PORT), dan startup command di-parse dari variabel {{EGG_VAR}}.
#
# Base diambil dari Docker Hub (n8nio/n8n), bukan docker.n8n.io: registry milik n8n
# membatasi IP runner GitHub Actions (429 Too Many Requests). Isinya image yang sama.
#
# Build dari root repo ini:
#   docker build -t n8n-pterodactyl .
#   docker build --build-arg N8N_VERSION=2.44.3 -t n8n-pterodactyl .

ARG N8N_VERSION=stable
FROM n8nio/n8n:${N8N_VERSION}

LABEL org.opencontainers.image.title="n8n-pterodactyl" \
      org.opencontainers.image.description="n8n (workflow automation) dibungkus agar siap jalan di Pterodactyl/Pelican" \
      org.opencontainers.image.licenses="Apache-2.0 WITH n8n fair-code"

USER root

# tzdata kalau package manager masih ada (image n8n versi baru bisa tanpa apk).
# Tidak wajib: zona waktu tetap jalan lewat ICU bawaan Node.js.
RUN if command -v apk >/dev/null 2>&1; then apk add --no-cache tzdata || true; fi

# cloudflared (binary statis) untuk HTTPS tanpa domain/akses root node: Telegram & layanan
# lain hanya mau mengirim webhook ke https://. Dipakai kalau HTTPS_TUNNEL=1 atau ada token.
ARG CLOUDFLARED_VERSION=2026.9.3
ADD --chmod=755 https://github.com/cloudflare/cloudflared/releases/download/${CLOUDFLARED_VERSION}/cloudflared-linux-amd64 /usr/local/bin/cloudflared

COPY entrypoint.sh /entrypoint.sh
RUN chmod 755 /entrypoint.sh \
    && mkdir -p /home/container \
    && chown -R node:node /home/container

# N8N_USER_FOLDER = folder yang BERISI .n8n (n8n sendiri yang menambahkan /.n8n).
# Nilai UNVERIFIED_PACKAGES/RUNNERS_TASK_TIMEOUT/COMPRESSION_* = bawaan n8n sekarang, ditulis
# eksplisit supaya perilaku tidak berubah saat n8n menurunkan bawaannya (dan tanpa peringatan).
ENV HOME=/home/container \
    N8N_USER_FOLDER=/home/container \
    N8N_LISTEN_ADDRESS=0.0.0.0 \
    N8N_PORT=5678 \
    N8N_PROTOCOL=http \
    N8N_DIAGNOSTICS_ENABLED=false \
    N8N_VERSION_NOTIFICATIONS_ENABLED=false \
    N8N_TEMPLATES_ENABLED=true \
    N8N_UNVERIFIED_PACKAGES_ENABLED=true \
    N8N_RUNNERS_TASK_TIMEOUT=300 \
    N8N_COMPRESSION_NODE_MAX_DECOMPRESSED_SIZE_BYTES=2147483648 \
    N8N_COMPRESSION_NODE_MAX_ZIP_ENTRIES=5000 \
    NODE_ENV=production \
    GENERIC_TIMEZONE=Asia/Jakarta \
    TZ=Asia/Jakarta

# Wings menjalankan container dengan --user sesuai uid/gid panel dan sudah
# meng-chown volume /home/container sebelum start; USER di sini hanya default
# untuk `docker run` biasa di luar Pterodactyl.
USER node
WORKDIR /home/container

EXPOSE 5678

# tini tetap PID 1 (seperti image resmi n8n): sinyal stop panel diteruskan dengan
# benar dan proses anak (task runner) yang selesai tidak jadi zombie.
STOPSIGNAL SIGTERM
ENTRYPOINT ["tini", "--", "/bin/sh", "/entrypoint.sh"]
