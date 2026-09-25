#!/bin/bash
#
# n8n · Pterodactyl edition entrypoint
#
# 1. Arahkan HOME & data n8n (.n8n) ke /home/container -> ini volume server
#    yang disediakan Pterodactyl, jadi workflow/credentials tetap ada saat
#    reinstall/restart image.
# 2. Ikuti port yang dialokasikan panel (SERVER_PORT).
# 3. Parse variabel {{EGG_VAR}} pada STARTUP command (standar semua egg
#    Pterodactyl) lalu jalankan.
# 4. Jika dijalankan tanpa Pterodactyl (docker run biasa) -> langsung
#    `exec n8n start`.

cd /home/container 2>/dev/null || cd "${HOME:-/home/node}" || true
export HOME="${HOME:-/home/container}"

export N8N_USER_FOLDER="${N8N_USER_FOLDER:-/home/container/.n8n}"
export N8N_PORT="${SERVER_PORT:-${N8N_PORT:-5678}}"
export N8N_HOST="${N8N_HOST:-0.0.0.0}"
export N8N_PROTOCOL="${N8N_PROTOCOL:-http}"
export GENERIC_TIMEZONE="${TZ:-${GENERIC_TIMEZONE:-UTC}}"
export TZ="${GENERIC_TIMEZONE}"

mkdir -p "${N8N_USER_FOLDER}" 2>/dev/null

# --- ANSI colors -------------------------------------------------------------
RESET='\033[0m'; BOLD='\033[1m'
CYAN='\033[1;36m'; GREEN='\033[1;32m'; YELLOW='\033[1;33m'
BLUE='\033[1;34m'; GRAY='\033[0;90m'
LINE="${GRAY}$(printf '%.0s─' $(seq 1 60))${RESET}"

print_logo() {
    echo -e "${GREEN}${BOLD}"
    cat <<'ART'
 _ __   ___   _ __
| '_ \ / _ \ | '_ \
| | | | (_) || | | |
|_| |_|\___/ |_| |_|
ART
    echo -e "${RESET}"
}

show_banner() {
    local node_v n8n_v
    node_v=$(node -v 2>/dev/null || echo "Not Installed")
    n8n_v=$(n8n --version 2>/dev/null || echo "Unknown")

    [ -t 1 ] && clear
    print_logo
    echo -e "$LINE"
    echo -e "${CYAN}n8n${RESET}          : v${n8n_v}"
    echo -e "${CYAN}Node.js${RESET}      : ${node_v}"
    echo -e "${CYAN}Host:Port${RESET}    : ${N8N_HOST}:${N8N_PORT}"
    echo -e "${CYAN}Protocol${RESET}     : ${N8N_PROTOCOL}"
    echo -e "${CYAN}Timezone${RESET}     : ${GENERIC_TIMEZONE}"
    echo -e "${CYAN}Data dir${RESET}     : ${N8N_USER_FOLDER}"
    if [ -n "${WEBHOOK_URL}" ]; then
        echo -e "${CYAN}Webhook URL${RESET} : ${WEBHOOK_URL}"
    fi
    echo -e "$LINE"
}

show_banner

# 1) explicit command (docker run image bash / sh)
if [ "$#" -gt 0 ]; then
    exec "$@"
fi

# 2) Pterodactyl / Pelican: panel mengirim startup command lewat $STARTUP,
#    dengan placeholder {{VAR}} yang perlu diubah jadi ${VAR} lalu di-expand.
if [ -n "${STARTUP}" ]; then
    MODIFIED_STARTUP=$(echo "${STARTUP}" | sed -e 's/{{/${/g' -e 's/}}/}/g')
    PARSED_STARTUP=$(eval echo "${MODIFIED_STARTUP}")
    echo -e "${GREEN}${BOLD}Menjalankan:${RESET} ${PARSED_STARTUP}"
    echo -e "$LINE"
    # shellcheck disable=SC2086
    exec env ${PARSED_STARTUP}
fi

# 3) plain docker (docker run / docker-compose tanpa STARTUP): langsung start
echo -e "${GREEN}${BOLD}Menjalankan n8n (mode standalone)...${RESET}"
exec n8n start
