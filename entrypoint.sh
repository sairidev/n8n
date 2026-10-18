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

# Bahasa pesan console image ini (bukan tampilan editor n8n): id (bawaan) / en
case "${CONSOLE_LANGUAGE:-id}" in
    en*|EN*) LANG_ID=0 ;;
    *) LANG_ID=1 ;;
esac
t() { if [ "${LANG_ID}" = 1 ]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }

# Variabel egg tetap WEBHOOK_URL, tapi n8n baru memakai N8N_WEBHOOK_URL (WEBHOOK_URL sudah usang).
WEBHOOK_URL="${N8N_WEBHOOK_URL:-${WEBHOOK_URL}}"
unset N8N_WEBHOOK_URL

# HTTPS lewat Cloudflare Tunnel (keluar dari container, tidak butuh port 443/akses root node).
# - token  : tunnel milik sendiri, domain tetap (public hostname -> http://localhost:PORT)
# - quick  : alamat https://xxx.trycloudflare.com gratis, berubah tiap restart; n8n mendaftarkan
#            ulang webhook trigger (Telegram dll.) dengan alamat baru saat start.
TUNNEL_MODE=""
TUNNEL_LOG=/tmp/cloudflared.log
if [ -n "${CLOUDFLARE_TUNNEL_TOKEN}" ]; then
    TUNNEL_TOKEN="${CLOUDFLARE_TUNNEL_TOKEN}" cloudflared tunnel --no-autoupdate run >"${TUNNEL_LOG}" 2>&1 &
    TUNNEL_MODE=token
elif [ "${HTTPS_TUNNEL}" = "1" ] || [ "${HTTPS_TUNNEL}" = "true" ]; then
    case "${WEBHOOK_URL}" in
        https://*) ;;  # sudah punya domain HTTPS sendiri
        *)
            cloudflared tunnel --no-autoupdate --url "http://127.0.0.1:${N8N_PORT}" >"${TUNNEL_LOG}" 2>&1 &
            printf '%s' "$(t 'Membuka HTTPS (Cloudflare Tunnel)...' 'Opening HTTPS (Cloudflare Tunnel)...')"
            i=0; quick=""
            while [ "${i}" -lt 30 ] && [ -z "${quick}" ]; do
                sleep 1; i=$((i + 1)); printf '.'
                quick=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "${TUNNEL_LOG}" 2>/dev/null | head -n 1)
            done
            printf '\n'
            if [ -n "${quick}" ]; then
                WEBHOOK_URL="${quick}"; TUNNEL_MODE=quick
            else
                TUNNEL_MODE=gagal
            fi
            ;;
    esac
fi
unset CLOUDFLARE_TUNNEL_TOKEN

# URL publik. N8N_HOST dipakai n8n untuk MEMBUAT url (bukan alamat listen), jadi jangan 0.0.0.0.
if [ -n "${WEBHOOK_URL}" ]; then
    case "${WEBHOOK_URL}" in */) ;; *) WEBHOOK_URL="${WEBHOOK_URL}/" ;; esac
    export N8N_WEBHOOK_URL="${WEBHOOK_URL}"
    export N8N_EDITOR_BASE_URL="${N8N_EDITOR_BASE_URL:-${WEBHOOK_URL}}"
    host="${WEBHOOK_URL#*://}"; host="${host%%/*}"; host="${host%%:*}"
    export N8N_HOST="${N8N_HOST:-${host}}"
    case "${WEBHOOK_URL}" in https://*) export N8N_PROTOCOL="https" ;; esac
elif [ -n "${SERVER_IP}" ] && [ "${SERVER_IP}" != "0.0.0.0" ]; then
    export N8N_HOST="${N8N_HOST:-${SERVER_IP}}"
elif [ -z "${N8N_HOST}" ]; then
    # Alokasi 0.0.0.0: cari IP publik node (maks 3 detik), kalau gagal n8n pakai localhost
    ip=$(node -e "fetch('https://api.ipify.org',{signal:AbortSignal.timeout(3000)}).then(r=>r.text()).then(t=>{t=t.trim();if(/^[0-9.]+$/.test(t))process.stdout.write(t)}).catch(()=>{})" 2>/dev/null)
    [ -n "${ip}" ] && export N8N_HOST="${ip}"
fi

# Batas memori Node.js mengikuti RAM server di panel (SERVER_MEMORY, MB; 0 = tanpa batas)
if [ -n "${SERVER_MEMORY}" ] && [ "${SERVER_MEMORY}" -gt 0 ] 2>/dev/null; then
    heap=$((SERVER_MEMORY * 75 / 100))
    [ "${heap}" -lt 256 ] && heap=256
    export NODE_OPTIONS="--max-old-space-size=${heap} ${NODE_OPTIONS:-}"
fi

mkdir -p "${N8N_USER_FOLDER}/.n8n" 2>/dev/null

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
case "${TUNNEL_MODE}" in
    quick) printf "${CYAN}%-12s${RESET} : %s\n" "HTTPS" "$(t 'Cloudflare Tunnel (alamat berubah tiap restart)' 'Cloudflare Tunnel (address changes on every restart)')" ;;
    token) printf "${CYAN}%-12s${RESET} : %s\n" "HTTPS" "$(t 'Cloudflare Tunnel (token sendiri)' 'Cloudflare Tunnel (own token)')" ;;
esac
printf "${CYAN}%-12s${RESET} : %s\n" "$(t 'Zona waktu' 'Timezone')" "${GENERIC_TIMEZONE}"
printf "${CYAN}%-12s${RESET} : %s/.n8n\n" "$(t 'Folder data' 'Data dir')" "${N8N_USER_FOLDER}"
printf "%b\n" "$LINE"

# Peringatan konfigurasi yang sering bikin bingung
if [ "${TUNNEL_MODE}" = "gagal" ]; then
    printf "${YELLOW}%s${RESET}\n" "$(t \
        '! Cloudflare Tunnel gagal dibuka (lihat /tmp/cloudflared.log). n8n tetap jalan tanpa HTTPS.' \
        '! Cloudflare Tunnel could not be opened (see /tmp/cloudflared.log). n8n keeps running without HTTPS.')"
    tail -n 5 "${TUNNEL_LOG}" 2>/dev/null
fi
case "${WEBHOOK_URL}" in
    https://*) ;;
    *) printf "${YELLOW}%s${RESET}\n" "$(t \
        '! URL publik bukan HTTPS: trigger Telegram & webhook layanan lain tidak bisa aktif. Nyalakan "HTTPS otomatis" di Startup, atau isi URL publik dengan https://domain.' \
        '! Public URL is not HTTPS: Telegram and other service webhooks cannot be activated. Turn on "Automatic HTTPS" in Startup, or set Public URL to https://domain.')" ;;
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
