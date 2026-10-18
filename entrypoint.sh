#!/bin/sh
#
# n8n · Pterodactyl edition entrypoint (POSIX sh, tidak butuh bash)
#
# 1. Data n8n (.n8n: workflow, credential, database, encryption key) di
#    /home/container = volume server Pterodactyl, aman saat restart/update image.
# 2. Port mengikuti alokasi panel (SERVER_PORT), listen di 0.0.0.0.
# 3. URL publik (webhook & editor) dari WEBHOOK_URL kalau diisi, kalau tidak dari
#    IP:port alokasi server.
# 4. Variabel {{EGG_VAR}} pada STARTUP (standar egg Pterodactyl) di-parse lalu dijalankan.
# 5. Tanpa Pterodactyl (docker run / compose tanpa STARTUP) -> langsung `n8n start`.

cd /home/container 2>/dev/null || cd "${HOME:-/home/node}" || true
export HOME="${HOME:-/home/container}"

# Folder yang BERISI .n8n (n8n menambahkan /.n8n sendiri) -> data di /home/container/.n8n
export N8N_USER_FOLDER="${N8N_USER_FOLDER:-/home/container}"
export N8N_PORT="${SERVER_PORT:-${N8N_PORT:-5678}}"
export N8N_LISTEN_ADDRESS="${N8N_LISTEN_ADDRESS:-0.0.0.0}"
export GENERIC_TIMEZONE="${GENERIC_TIMEZONE:-${TZ:-Asia/Jakarta}}"
export TZ="${GENERIC_TIMEZONE}"

# URL publik. N8N_HOST dipakai n8n untuk MEMBUAT url (bukan alamat listen), jadi jangan 0.0.0.0.
if [ -n "${WEBHOOK_URL}" ]; then
    case "${WEBHOOK_URL}" in */) ;; *) WEBHOOK_URL="${WEBHOOK_URL}/" ;; esac
    export WEBHOOK_URL
    export N8N_EDITOR_BASE_URL="${N8N_EDITOR_BASE_URL:-${WEBHOOK_URL}}"
    host="${WEBHOOK_URL#*://}"; host="${host%%/*}"; host="${host%%:*}"
    export N8N_HOST="${N8N_HOST:-${host}}"
    case "${WEBHOOK_URL}" in https://*) export N8N_PROTOCOL="https" ;; esac
elif [ -n "${SERVER_IP}" ] && [ "${SERVER_IP}" != "0.0.0.0" ]; then
    export N8N_HOST="${N8N_HOST:-${SERVER_IP}}"
fi

# Batas memori Node.js mengikuti RAM server di panel (SERVER_MEMORY, MB; 0 = tanpa batas)
if [ -n "${SERVER_MEMORY}" ] && [ "${SERVER_MEMORY}" -gt 0 ] 2>/dev/null; then
    heap=$((SERVER_MEMORY * 75 / 100))
    [ "${heap}" -lt 256 ] && heap=256
    export NODE_OPTIONS="--max-old-space-size=${heap} ${NODE_OPTIONS:-}"
fi

mkdir -p "${N8N_USER_FOLDER}/.n8n" 2>/dev/null

# --- banner ------------------------------------------------------------------
GREEN='\033[1;32m'; CYAN='\033[1;36m'; GRAY='\033[0;90m'; BOLD='\033[1m'; RESET='\033[0m'
LINE="${GRAY}------------------------------------------------------------${RESET}"

printf "${GREEN}${BOLD}"
cat <<'ART'
 _ __   ___   _ __
| '_ \ / _ \ | '_ \
| | | | (_) || | | |
|_| |_|\___/ |_| |_|
ART
printf "${RESET}\n"
printf "%b\n" "$LINE"
printf "${CYAN}n8n${RESET}          : v%s\n" "$(n8n --version 2>/dev/null || echo '?')"
printf "${CYAN}Node.js${RESET}      : %s\n" "$(node -v 2>/dev/null || echo '?')"
printf "${CYAN}Listen${RESET}       : %s:%s\n" "${N8N_LISTEN_ADDRESS}" "${N8N_PORT}"
printf "${CYAN}URL publik${RESET}   : %s\n" "${WEBHOOK_URL:-${N8N_PROTOCOL:-http}://${N8N_HOST:-localhost}:${N8N_PORT}/}"
printf "${CYAN}Timezone${RESET}     : %s\n" "${GENERIC_TIMEZONE}"
printf "${CYAN}Data dir${RESET}     : %s/.n8n\n" "${N8N_USER_FOLDER}"
printf "%b\n" "$LINE"

# 1) explicit command (docker run image sh / n8n ...)
if [ "$#" -gt 0 ]; then
    exec "$@"
fi

# 2) Pterodactyl / Pelican: startup command lewat $STARTUP, {{VAR}} -> ${VAR}
if [ -n "${STARTUP}" ]; then
    MODIFIED_STARTUP=$(printf '%s' "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')
    printf "${GREEN}${BOLD}Menjalankan:${RESET} %s\n" "$(eval "printf '%s' \"${MODIFIED_STARTUP}\"")"
    printf "%b\n" "$LINE"
    eval "exec ${MODIFIED_STARTUP}"
fi

# 3) plain docker (docker run / docker-compose tanpa STARTUP): langsung start
printf "${GREEN}${BOLD}Menjalankan n8n (mode standalone)...${RESET}\n"
exec n8n start
