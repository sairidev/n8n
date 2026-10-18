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
# Variabel egg tetap WEBHOOK_URL, tapi n8n baru memakai N8N_WEBHOOK_URL (WEBHOOK_URL sudah usang).
WEBHOOK_URL="${N8N_WEBHOOK_URL:-${WEBHOOK_URL}}"
unset N8N_WEBHOOK_URL
if [ -n "${WEBHOOK_URL}" ]; then
    case "${WEBHOOK_URL}" in */) ;; *) WEBHOOK_URL="${WEBHOOK_URL}/" ;; esac
    export N8N_WEBHOOK_URL="${WEBHOOK_URL}"
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

# Bahasa pesan console image ini (bukan tampilan editor n8n): id (bawaan) / en
case "${CONSOLE_LANGUAGE:-id}" in
    en*|EN*) LANG_ID=0 ;;
    *) LANG_ID=1 ;;
esac
t() { if [ "${LANG_ID}" = 1 ]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }

# --- banner ------------------------------------------------------------------
GREEN='\033[1;32m'; CYAN='\033[1;36m'; YELLOW='\033[1;33m'; GRAY='\033[0;90m'; BOLD='\033[1m'; RESET='\033[0m'
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
printf "${CYAN}%-12s${RESET} : %s\n" "$(t 'URL publik' 'Public URL')" "${WEBHOOK_URL:-${N8N_PROTOCOL:-http}://${N8N_HOST:-localhost}:${N8N_PORT}/}"
printf "${CYAN}%-12s${RESET} : %s\n" "$(t 'Zona waktu' 'Timezone')" "${GENERIC_TIMEZONE}"
printf "${CYAN}%-12s${RESET} : %s/.n8n\n" "$(t 'Folder data' 'Data dir')" "${N8N_USER_FOLDER}"
printf "%b\n" "$LINE"

# Peringatan konfigurasi yang sering bikin bingung
case "${WEBHOOK_URL}" in
    https://*) ;;
    *) printf "${YELLOW}%s${RESET}\n" "$(t \
        '! URL publik bukan HTTPS: trigger Telegram & webhook layanan lain tidak bisa aktif. Isi URL publik dengan https://domain.' \
        '! Public URL is not HTTPS: Telegram and other service webhooks cannot be activated. Set Public URL to https://domain.')" ;;
esac
if [ "${N8N_SECURE_COOKIE}" = "true" ] && [ "${N8N_PROTOCOL}" != "https" ]; then
    printf "${YELLOW}%s${RESET}\n" "$(t \
        '! Cookie aman = true tapi URL publik bukan HTTPS: login lewat http://IP:PORT akan gagal. Ubah ke false.' \
        '! Secure cookie = true but Public URL is not HTTPS: logging in via http://IP:PORT will fail. Set it to false.')"
fi

# Sudah diteruskan lewat N8N_WEBHOOK_URL; WEBHOOK_URL lama tidak ikut ke n8n (peringatan usang)
unset WEBHOOK_URL

# 1) explicit command (docker run image sh / n8n ...)
if [ "$#" -gt 0 ]; then
    exec "$@"
fi

# 2) Pterodactyl / Pelican: startup command lewat $STARTUP, {{VAR}} -> ${VAR}
if [ -n "${STARTUP}" ]; then
    MODIFIED_STARTUP=$(printf '%s' "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')
    printf "${GREEN}${BOLD}%s${RESET} %s\n" "$(t 'Menjalankan:' 'Running:')" "$(eval "printf '%s' \"${MODIFIED_STARTUP}\"")"
    printf "%b\n" "$LINE"
    eval "exec ${MODIFIED_STARTUP}"
fi

# 3) plain docker (docker run / docker-compose tanpa STARTUP): langsung start
printf "${GREEN}${BOLD}%s${RESET}\n" "$(t 'Menjalankan n8n (mode standalone)...' 'Starting n8n (standalone mode)...')"
exec n8n start
