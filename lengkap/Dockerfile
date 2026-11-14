# syntax=docker/dockerfile:1.7
#
# n8n + Evolution API + PostgreSQL · Pterodactyl edition (tag :evo)
#
# Pterodactyl memberi SATU container per server, jadi ketiganya jalan di container yang sama:
#   - PostgreSQL 17      127.0.0.1 (data /home/container/postgres)
#   - Evolution API      127.0.0.1 (sesi WhatsApp /home/container/evolution)
#   - n8n                127.0.0.1 (database di Postgres, berkas /home/container/.n8n)
#   - Caddy              port server (SERVER_PORT): n8n di "/", Evolution di "/evo", manager di "/manager";
#                        port kedua opsional EVOLUTION_PORT khusus Evolution.
# Program ada di image (bukan di disk server): update = tarik image baru, data pelanggan tidak tersentuh.
#
# Image n8n resmi sekarang memakai base "hardened" tanpa apk, jadi Postgres tidak bisa ditambahkan ke sana.
# n8n dipasang dari npm di node:24-alpine yang sama dengan Evolution API (keduanya butuh Node 24).
#
#   docker build -t n8n-evo lengkap/
#   docker build --build-arg N8N_VERSION=2.47.7 --build-arg EVOLUTION_VERSION=2.3.7 -t n8n-evo lengkap/

ARG NODE_IMAGE=node:24-alpine3.24

# ---------------------------------------------------------------------------- n8n (npm)
FROM ${NODE_IMAGE} AS n8n
ARG N8N_VERSION=2.47.7
# compiler hanya di tahap ini (modul native isolated-vm, sqlite3, dll.)
RUN apk add --no-cache python3 make g++ git
RUN npm install -g --omit=dev --no-audit --no-fund "n8n@${N8N_VERSION}" \
    && npm cache clean --force \
    && n8n --version

# ---------------------------------------------------------------------------- Evolution API (sumber resmi)
FROM ${NODE_IMAGE} AS evolution
ARG EVOLUTION_VERSION=2.3.7
RUN apk add --no-cache git bash openssl
WORKDIR /opt/evolution
RUN git clone --depth 1 --branch "${EVOLUTION_VERSION}" https://github.com/EvolutionAPI/evolution-api.git .
RUN npm ci --no-audit --no-fund
ENV DATABASE_PROVIDER=postgresql
# Prisma client harus ada sebelum build (tsc memeriksa tipenya), sama dengan urutan Dockerfile resmi.
RUN npm run db:generate && npm run build
# Migrasi Postgres disiapkan di sini, karena /opt/evolution hanya-baca saat jalan (bukan "npm run db:deploy").
# Prisma client dibuat ulang SETELAH prune supaya hasil generate tidak ikut terhapus.
RUN rm -rf prisma/migrations && cp -r prisma/postgresql-migrations prisma/migrations \
    && npm prune --omit=dev --no-audit --no-fund \
    && npm run db:generate \
    && rm -rf .git .github \
    && npm cache clean --force \
    && test -f dist/main.js && test -f manager/dist/index.html && test -x node_modules/.bin/prisma

# ---------------------------------------------------------------------------- image akhir
FROM ${NODE_IMAGE}

LABEL org.opencontainers.image.title="n8n-evo-pterodactyl" \
      org.opencontainers.image.description="n8n + Evolution API + PostgreSQL dalam satu container, siap jalan di Pterodactyl/Pelican" \
      org.opencontainers.image.licenses="Apache-2.0 WITH n8n fair-code; Evolution API Apache-2.0; PostgreSQL License"

# tini      : PID 1, meneruskan sinyal stop panel
# postgresql17 (+ client psql), caddy (proxy satu port), ffmpeg (audio WhatsApp di Evolution),
# git/openssh/graphicsmagick/libc6-compat/tzdata: sama dengan isi image n8n resmi
# su-exec   : hanya untuk `docker run` sebagai root di luar Pterodactyl
RUN apk add --no-cache \
        tini tzdata ca-certificates libc6-compat su-exec \
        postgresql17 postgresql17-client \
        caddy ffmpeg openssl \
        git openssh-client graphicsmagick \
    && mkdir -p /home/container /run/postgresql \
    # Postgres menolak jalan kalau uid-nya tidak ada di /etc/passwd. Uid Wings berbeda tiap node,
    # jadi skrip start menambahkan barisnya sendiri (pola yang sama dengan OpenShift).
    && chmod 666 /etc/passwd /etc/group

COPY --from=n8n /usr/local/lib/node_modules/n8n /usr/local/lib/node_modules/n8n
RUN ln -s ../lib/node_modules/n8n/bin/n8n /usr/local/bin/n8n && n8n --version

COPY --from=evolution /opt/evolution /opt/evolution

# cloudflared (binary statis) untuk HTTPS tanpa domain / akses root node (HTTPS_TUNNEL=1 atau token sendiri)
ARG CLOUDFLARED_VERSION=2026.9.3
ADD --chmod=755 https://github.com/cloudflare/cloudflared/releases/download/${CLOUDFLARED_VERSION}/cloudflared-linux-amd64 /usr/local/bin/cloudflared

COPY --chmod=755 entrypoint.sh /entrypoint.sh
COPY --chmod=755 paket-lengkap.sh /usr/local/bin/paket-lengkap

# Program Postgres 17 dipanggil dari foldernya sendiri (tidak bergantung pada symlink versi bawaan Alpine)
ENV PATH=/usr/libexec/postgresql17:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    HOME=/home/container \
    N8N_USER_FOLDER=/home/container \
    N8N_DIAGNOSTICS_ENABLED=false \
    N8N_VERSION_NOTIFICATIONS_ENABLED=false \
    N8N_TEMPLATES_ENABLED=true \
    N8N_UNVERIFIED_PACKAGES_ENABLED=true \
    N8N_RUNNERS_TASK_TIMEOUT=300 \
    N8N_COMPRESSION_NODE_MAX_DECOMPRESSED_SIZE_BYTES=2147483648 \
    N8N_COMPRESSION_NODE_MAX_ZIP_ENTRIES=5000 \
    NODE_ENV=production \
    GENERIC_TIMEZONE=Asia/Jakarta \
    TZ=Asia/Jakarta \
    CHECKPOINT_DISABLE=1 \
    PRISMA_HIDE_UPDATE_MESSAGE=1

USER node
WORKDIR /home/container
EXPOSE 8080
STOPSIGNAL SIGINT
ENTRYPOINT ["/sbin/tini", "--", "/entrypoint.sh"]
