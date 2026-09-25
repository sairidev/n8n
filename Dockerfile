# syntax=docker/dockerfile:1.7
#
# n8n · Pterodactyl edition
#
# Tidak build n8n dari source (butuh compiler untuk native module: isolated-vm,
# sqlite3, kafka-javascript — berat & lama). Sebagai gantinya image resmi n8n
# dipakai sebagai base, lalu ditambah lapisan tipis agar cocok jalan di bawah
# Pterodactyl/Pelican Wings: HOME & data dir diarahkan ke /home/container
# (volume server panel), port mengikuti alokasi panel (SERVER_PORT), dan
# startup command di-parse dari variabel {{EGG_VAR}} ala Pterodactyl.
#
# Build dari root repo ini:
#   docker build -t n8n-pterodactyl .

ARG N8N_VERSION=latest
FROM docker.n8n.io/n8nio/n8n:${N8N_VERSION}

LABEL org.opencontainers.image.title="n8n-pterodactyl" \
      org.opencontainers.image.description="n8n (workflow automation) dibungkus agar siap jalan di Pterodactyl/Pelican" \
      org.opencontainers.image.source="https://github.com/n8n-io/n8n" \
      org.opencontainers.image.licenses="Apache-2.0 WITH n8n fair-code"

USER root

# Base image n8n adalah Alpine minimal (tanpa bash). Tambahkan bash, curl,
# tzdata (untuk GENERIC_TIMEZONE) dan su-exec (jaga-jaga jika perlu drop
# privilege manual).
RUN apk add --no-cache bash curl tzdata su-exec shadow \
    && rm -rf /var/cache/apk/*

ENV HOME=/home/container \
    N8N_USER_FOLDER=/home/container/.n8n \
    N8N_HOST=0.0.0.0 \
    N8N_PROTOCOL=http \
    N8N_PORT=5678 \
    N8N_DIAGNOSTICS_ENABLED=false \
    N8N_VERSION_NOTIFICATIONS_ENABLED=false \
    N8N_TEMPLATES_ENABLED=true \
    N8N_RUNNERS_ENABLED=true \
    NODE_ENV=production \
    GENERIC_TIMEZONE=UTC \
    TZ=UTC

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh \
    && mkdir -p /home/container \
    && chown -R node:node /home/container

# Wings (daemon Pterodactyl) menjalankan container dengan --user sesuai uid/gid
# yang dikonfigurasi di panel (default 988:988 atau 999:999) dan sudah
# meng-chown seluruh volume /home/container ke uid tsb sebelum start, jadi
# USER di sini hanya default untuk `docker run` biasa di luar Pterodactyl.
USER node
WORKDIR /home/container

EXPOSE 5678

ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]
