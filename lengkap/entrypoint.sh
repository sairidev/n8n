#!/bin/sh
#
# Entrypoint image n8n + Evolution API + PostgreSQL (tag :evo).
# Pterodactyl/Pelican: perintah startup egg ada di $STARTUP ({{VAR}} -> ${VAR}); bawaannya `paket-lengkap`.
# Tanpa panel (docker run tanpa STARTUP): langsung paket-lengkap.

cd /home/container 2>/dev/null || true
export HOME=/home/container

# `docker run` sebagai root di luar Pterodactyl: Postgres menolak jalan sebagai root, jadi turun ke user node.
# (Wings selalu menjalankan container dengan uid non-root, jadi cabang ini tidak dipakai di panel.)
if [ "$(id -u)" = 0 ]; then
    chown -R node:node /home/container 2>/dev/null
    exec su-exec node "$0" "$@"
fi

if [ "$#" -gt 0 ]; then
    exec "$@"
fi

if [ -n "${STARTUP}" ]; then
    MODIFIED_STARTUP=$(printf '%s' "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')
    eval "exec ${MODIFIED_STARTUP}"
fi

exec paket-lengkap
