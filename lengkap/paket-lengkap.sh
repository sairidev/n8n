#!/bin/sh
#
# paket-lengkap: n8n + Evolution API + PostgreSQL + Caddy dalam satu container Pterodactyl.
#
# Start : Postgres -> migrasi Evolution -> Evolution (diawasi, nyala ulang bila mati) -> Caddy -> n8n.
# Stop  : Ctrl+C / SIGINT / SIGTERM dari panel -> n8n -> Evolution -> Caddy -> Postgres (fast shutdown) -> keluar 0.
#         Postgres WAJIB dimatikan rapi; kalau dibunuh paksa, data tetap dipulihkan dari WAL saat start berikutnya.
#
# Port  : SERVER_PORT (alokasi utama panel) = Caddy:
#             /            -> n8n
#             /evo/...     -> Evolution API (awalan /evo dibuang)
#             /manager     -> manager Evolution (+ berkas /assets/* miliknya)
#         EVOLUTION_PORT (opsional, port tambahan) -> Evolution API utuh.
#         POSTGRES_PORT  (opsional, port tambahan) -> Postgres dibuka ke luar (sandi wajib).
#         Semua layanan lain hanya mendengar di 127.0.0.1.
#
# Data  : /home/container/.n8n           berkas n8n (kunci enkripsi kredensial!)
#         /home/container/postgres/data  database (n8n, evolution, dan database milik pengguna)
#         /home/container/evolution      sesi WhatsApp, log Evolution, tambahan.env
#         /home/container/.paket         rahasia & berkas sistem paket (jangan dihapus)
#         /home/container/kredensial.txt alamat, API key Evolution, akun Postgres (dibuat ulang tiap start)

H=/home/container
cd "$H" || exit 1
export HOME="$H"
P="$H/.paket"
mkdir -p "$P" && chmod 700 "$P"

# ------------------------------------------------------------------ tampilan console
case "${CONSOLE_LANGUAGE:-id}" in en*|EN*) LANG_ID=0 ;; *) LANG_ID=1 ;; esac
t() { if [ "$LANG_ID" = 1 ]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }
GREEN='\033[1;32m'; CYAN='\033[1;36m'; YELLOW='\033[1;33m'; RED='\033[1;31m'; GRAY='\033[0;90m'; BOLD='\033[1m'; RESET='\033[0m'
LINE="${GRAY}------------------------------------------------------------${RESET}"
info() { printf "${CYAN}[paket]${RESET} %s\n" "$1"; }
warn() { printf "${YELLOW}! %s${RESET}\n" "$1"; }
gagal() { printf "${RED}x %s${RESET}\n" "$1"; }
baris() { printf "${CYAN}%-14s${RESET}: %s\n" "$1" "$2"; }
putar_log() { [ -f "$1" ] && [ "$(wc -c < "$1")" -gt 10485760 ] && mv -f "$1" "$1.1"; return 0; }
angka() { case "$1" in ''|*[!0-9]*) return 1 ;; *) [ "$1" -ge 1 ] && [ "$1" -le 65535 ] ;; esac; }

# ------------------------------------------------------------------ uid Wings harus punya nama (syarat Postgres)
# Root filesystem Wings hanya-baca; /etc/passwd & /etc/group adalah tautan ke /tmp (tmpfs baru setiap start).
[ -s /tmp/passwd ] || cp /etc/passwd.asli /tmp/passwd 2>/dev/null
[ -s /tmp/group ] || cp /etc/group.asli /tmp/group 2>/dev/null
uid=$(id -u); gid=$(id -g)
if ! awk -F: -v u="$uid" '$3 == u { ada = 1 } END { exit !ada }' /tmp/passwd 2>/dev/null; then
    echo "container:x:${uid}:${gid}:container:${H}:/bin/sh" >> /tmp/passwd || warn "$(t 'Tidak bisa menulis /tmp/passwd.' 'Cannot write /tmp/passwd.')"
fi
if ! awk -F: -v g="$gid" '$3 == g { ada = 1 } END { exit !ada }' /tmp/group 2>/dev/null; then
    echo "container:x:${gid}:" >> /tmp/group 2>/dev/null
fi

# ------------------------------------------------------------------ port
PORT="${SERVER_PORT:-8080}"
angka "$PORT" || PORT=8080
EVO_PORT=""
if [ -n "${EVOLUTION_PORT:-}" ]; then
    if angka "$EVOLUTION_PORT" && [ "$EVOLUTION_PORT" != "$PORT" ]; then EVO_PORT="$EVOLUTION_PORT"
    else warn "$(t "EVOLUTION_PORT ($EVOLUTION_PORT) tidak valid atau sama dengan port utama, diabaikan." "EVOLUTION_PORT ($EVOLUTION_PORT) is invalid or equals the main port, ignored.")"; fi
fi
PG_PUBLIK=""
if [ -n "${POSTGRES_PORT:-}" ]; then
    if angka "$POSTGRES_PORT" && [ "$POSTGRES_PORT" != "$PORT" ] && [ "$POSTGRES_PORT" != "$EVO_PORT" ]; then PG_PUBLIK="$POSTGRES_PORT"
    else warn "$(t "POSTGRES_PORT ($POSTGRES_PORT) tidak valid atau bentrok dengan port lain, diabaikan." "POSTGRES_PORT ($POSTGRES_PORT) is invalid or clashes with another port, ignored.")"; fi
fi
# port dalam container dipilih supaya tidak bentrok dengan port dari panel
dipakai=" $PORT $EVO_PORT $PG_PUBLIK "
pilih() { _p=$1; while case "$dipakai" in *" $_p "*) true ;; *) false ;; esac; do _p=$((_p + 1)); done; dipakai="$dipakai$_p "; }
pilih 5678; N8N_DALAM=$_p
pilih 5679; N8N_BROKER=$_p
pilih 8081; EVO_DALAM=$_p
if [ -n "$PG_PUBLIK" ]; then PG_PORT=$PG_PUBLIK; else pilih 5432; PG_PORT=$_p; fi

# ------------------------------------------------------------------ rahasia (dibuat sekali, disimpan di .paket)
acak() { tr -dc 'a-f0-9' < /dev/urandom | head -c "${1:-40}"; }
R="$P/rahasia.env"
[ -f "$R" ] || : > "$R"
chmod 600 "$R"
. "$R"
simpan_rahasia() { printf '%s=%s\n' "$1" "$2" >> "$R"; }
[ -n "${PG_SUPER_PASSWORD:-}" ] || { PG_SUPER_PASSWORD=$(acak 40); simpan_rahasia PG_SUPER_PASSWORD "$PG_SUPER_PASSWORD"; }
[ -n "${PG_N8N_PASSWORD:-}" ] || { PG_N8N_PASSWORD=$(acak 40); simpan_rahasia PG_N8N_PASSWORD "$PG_N8N_PASSWORD"; }
[ -n "${PG_EVO_PASSWORD:-}" ] || { PG_EVO_PASSWORD=$(acak 40); simpan_rahasia PG_EVO_PASSWORD "$PG_EVO_PASSWORD"; }
[ -n "${PG_APP_PASSWORD:-}" ] || { PG_APP_PASSWORD=$(acak 40); simpan_rahasia PG_APP_PASSWORD "$PG_APP_PASSWORD"; }
[ -n "${EVO_KEY_OTOMATIS:-}" ] || { EVO_KEY_OTOMATIS=$(acak 32); simpan_rahasia EVO_KEY_OTOMATIS "$EVO_KEY_OTOMATIS"; }
EVO_KEY="${EVOLUTION_API_KEY:-$EVO_KEY_OTOMATIS}"

# ------------------------------------------------------------------ memori (SERVER_MEMORY dari panel, MB)
MEM="${SERVER_MEMORY:-0}"; angka "$MEM" || MEM=0
HEAP_N8N=""; HEAP_EVO=""
if [ "$MEM" -gt 0 ]; then
    HEAP_N8N=$((MEM * 45 / 100)); [ "$HEAP_N8N" -lt 256 ] && HEAP_N8N=256
    HEAP_EVO=$((MEM * 20 / 100)); [ "$HEAP_EVO" -lt 160 ] && HEAP_EVO=160
    PG_SB=$((MEM / 10))
else
    PG_SB=128
fi
[ "$PG_SB" -lt 32 ] && PG_SB=32
[ "$PG_SB" -gt 512 ] && PG_SB=512

TZ_PAKET="${GENERIC_TIMEZONE:-${TZ:-Asia/Jakarta}}"
export GENERIC_TIMEZONE="$TZ_PAKET" TZ="$TZ_PAKET"

# ------------------------------------------------------------------ URL publik (+ HTTPS lewat Cloudflare Tunnel)
WEBHOOK_URL="${N8N_WEBHOOK_URL:-${WEBHOOK_URL:-}}"
unset N8N_WEBHOOK_URL
TUNNEL_MODE=""; TUNNEL_PID=""; TUNNEL_LOG="$P/cloudflared.log"
if [ -n "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]; then
    # tunnel milik sendiri: public hostname di Cloudflare diarahkan ke http://localhost:<port server>
    TUNNEL_TOKEN="${CLOUDFLARE_TUNNEL_TOKEN}" cloudflared tunnel --no-autoupdate run > "$TUNNEL_LOG" 2>&1 &
    TUNNEL_PID=$!; TUNNEL_MODE=token
elif [ "${HTTPS_TUNNEL:-0}" = 1 ] || [ "${HTTPS_TUNNEL:-0}" = true ]; then
    case "$WEBHOOK_URL" in
        https://*) ;;
        *)
            cloudflared tunnel --no-autoupdate --url "http://127.0.0.1:${PORT}" > "$TUNNEL_LOG" 2>&1 &
            TUNNEL_PID=$!
            printf '%s' "$(t 'Membuka HTTPS (Cloudflare Tunnel)...' 'Opening HTTPS (Cloudflare Tunnel)...')"
            i=0; cepat=""
            while [ "$i" -lt 30 ] && [ -z "$cepat" ]; do
                sleep 1; i=$((i + 1)); printf '.'
                cepat=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' "$TUNNEL_LOG" 2>/dev/null | head -n 1)
            done
            printf '\n'
            if [ -n "$cepat" ]; then WEBHOOK_URL="$cepat"; TUNNEL_MODE=quick; else TUNNEL_MODE=gagal; fi
            ;;
    esac
fi
unset CLOUDFLARE_TUNNEL_TOKEN

if [ -n "$WEBHOOK_URL" ]; then
    case "$WEBHOOK_URL" in */) ;; *) WEBHOOK_URL="$WEBHOOK_URL/" ;; esac
    URL_PUBLIK="$WEBHOOK_URL"
    HOST_PUBLIK="${WEBHOOK_URL#*://}"; HOST_PUBLIK="${HOST_PUBLIK%%/*}"; HOST_PUBLIK="${HOST_PUBLIK%%:*}"
else
    ip="${SERVER_IP:-}"
    if [ -z "$ip" ] || [ "$ip" = 0.0.0.0 ]; then
        # alokasi 0.0.0.0: cari IP publik node (maks 3 detik)
        ip=$(node -e "fetch('https://api.ipify.org',{signal:AbortSignal.timeout(3000)}).then(r=>r.text()).then(t=>{t=t.trim();if(/^[0-9.]+$/.test(t))process.stdout.write(t)}).catch(()=>{})" 2>/dev/null)
        [ -n "$ip" ] || ip=localhost
    fi
    HOST_PUBLIK="$ip"
    URL_PUBLIK="http://${ip}:${PORT}/"
fi
unset WEBHOOK_URL
case "$URL_PUBLIK" in https://*) PROTO=https ;; *) PROTO=http ;; esac

if [ -n "${EVOLUTION_URL:-}" ]; then EVO_URL="${EVOLUTION_URL%/}"
elif [ -n "$EVO_PORT" ]; then EVO_URL="http://${HOST_PUBLIK}:${EVO_PORT}"
else EVO_URL="${URL_PUBLIK%/}/evo"; fi
if [ -n "$EVO_PORT" ] && [ -z "${EVOLUTION_URL:-}" ]; then MANAGER_URL="${EVO_URL}/manager"; else MANAGER_URL="${URL_PUBLIK%/}/manager"; fi

# ------------------------------------------------------------------ banner
V_N8N=$(node -p "require('/usr/local/lib/node_modules/n8n/package.json').version" 2>/dev/null)
V_EVO=$(node -p "require('/opt/evolution/package.json').version" 2>/dev/null)
V_PG=$(postgres --version 2>/dev/null | awk '{print $3}')
printf "${GREEN}${BOLD}"
cat <<'ART'
 _ __   ___   _ __      ___ __   __ ___
| '_ \ / _ \ | '_ \    / _ \\ \ / // _ \
| | | | (_) || | | |  |  __/ \ V /| (_) |
|_| |_|\___/ |_| |_|   \___|  \_/  \___/
ART
printf "${RESET}\n%b\n" "$LINE"
baris "n8n" "v${V_N8N:-?}"
baris "Evolution API" "v${V_EVO:-?}"
baris "PostgreSQL" "${V_PG:-?}"
baris "$(t 'URL n8n' 'n8n URL')" "$URL_PUBLIK"
baris "Evolution API" "$EVO_URL"
baris "Manager" "$MANAGER_URL"
case "$TUNNEL_MODE" in
    quick) baris "HTTPS" "$(t 'Cloudflare Tunnel (alamat berubah tiap restart)' 'Cloudflare Tunnel (address changes on every restart)')" ;;
    token) baris "HTTPS" "$(t 'Cloudflare Tunnel (token sendiri)' 'Cloudflare Tunnel (own token)')" ;;
esac
baris "$(t 'Kredensial' 'Credentials')" "kredensial.txt"
printf "%b\n" "$LINE"

[ "$TUNNEL_MODE" = gagal ] && { warn "$(t 'Cloudflare Tunnel gagal dibuka (.paket/cloudflared.log). Lanjut tanpa HTTPS.' 'Cloudflare Tunnel could not be opened (.paket/cloudflared.log). Continuing without HTTPS.')"; tail -n 5 "$TUNNEL_LOG" 2>/dev/null; }
[ "$PROTO" = https ] || warn "$(t 'URL publik bukan HTTPS: webhook Telegram/TikTok dan layanan lain butuh https://. Isi URL publik dengan domain HTTPS atau nyalakan "HTTPS otomatis" di Startup.' 'Public URL is not HTTPS: Telegram/TikTok and other webhooks need https://. Set the Public URL to an HTTPS domain or turn on "Automatic HTTPS" in Startup.')"
[ "${N8N_SECURE_COOKIE:-false}" = true ] && [ "$PROTO" != https ] && warn "$(t 'Cookie aman = true tapi URL bukan HTTPS: login n8n akan gagal. Ubah ke false.' 'Secure cookie = true but the URL is not HTTPS: n8n login will fail. Set it to false.')"
[ "$MEM" -gt 0 ] && [ "$MEM" -lt 1024 ] && warn "$(t "RAM server ${MEM} MB: n8n + Evolution + Postgres butuh minimal 1 GB, disarankan 2 GB." "Server RAM ${MEM} MB: n8n + Evolution + Postgres need at least 1 GB, 2 GB recommended.")"

# ------------------------------------------------------------------ PostgreSQL
export PGDATA="$H/postgres/data"
PGRUN="$H/postgres/run"
PGLOG="$H/postgres/postgres.log"
mkdir -p "$PGRUN"
putar_log "$PGLOG"
if [ ! -s "$PGDATA/PG_VERSION" ]; then
    info "$(t 'Menyiapkan PostgreSQL pertama kali...' 'Initializing PostgreSQL for the first time...')"
    mkdir -p "$PGDATA"; chmod 700 "$PGDATA"
    pw="$P/.pw-awal"; printf '%s\n' "$PG_SUPER_PASSWORD" > "$pw"; chmod 600 "$pw"
    if ! initdb -D "$PGDATA" -U postgres --pwfile="$pw" --auth-local=trust --auth-host=scram-sha-256 \
            --encoding=UTF8 --locale=C > "$P/initdb.log" 2>&1; then
        rm -f "$pw"
        gagal "$(t 'initdb gagal:' 'initdb failed:')"; tail -n 15 "$P/initdb.log"; exit 1
    fi
    rm -f "$pw"
    printf "\n# pengaturan paket (dibuat ulang tiap start)\ninclude_if_exists = 'paket.conf'\n" >> "$PGDATA/postgresql.conf"
    printf "\n# akses dari luar bila POSTGRES_PORT diisi (dibuat ulang tiap start)\ninclude_if_exists paket_hba.conf\n" >> "$PGDATA/pg_hba.conf"
fi
if [ "$(cat "$PGDATA/PG_VERSION")" != "${V_PG%%.*}" ]; then
    gagal "$(t "Data Postgres versi $(cat "$PGDATA/PG_VERSION"), program versi ${V_PG}. Perlu upgrade data (pg_upgrade/pg_dump); server tidak dinyalakan supaya data aman." "Postgres data is version $(cat "$PGDATA/PG_VERSION"), program is ${V_PG}. The data needs an upgrade (pg_upgrade/pg_dump); not starting so the data stays safe.")"
    exit 1
fi
chmod 700 "$PGDATA"
if [ -n "$PG_PUBLIK" ]; then PG_LISTEN='*'; else PG_LISTEN='127.0.0.1'; fi
cat > "$PGDATA/paket.conf" <<EOF
# Dibuat ulang setiap start oleh paket-lengkap. Pengaturan sendiri: ALTER SYSTEM (postgresql.auto.conf).
listen_addresses = '${PG_LISTEN}'
port = ${PG_PORT}
unix_socket_directories = '${PGRUN}'
max_connections = 60
shared_buffers = ${PG_SB}MB
work_mem = 4MB
maintenance_work_mem = 32MB
dynamic_shared_memory_type = mmap
huge_pages = off
timezone = '${TZ_PAKET}'
log_timezone = '${TZ_PAKET}'
log_min_messages = warning
EOF
if [ -n "$PG_PUBLIK" ]; then
    printf 'host all all 0.0.0.0/0 scram-sha-256\nhost all all ::/0 scram-sha-256\n' > "$PGDATA/paket_hba.conf"
else
    : > "$PGDATA/paket_hba.conf"
fi
# Container selalu baru setiap start (PID mulai dari 1 lagi): berkas pid lama pasti basi dan bisa
# kebetulan sama dengan PID proses lain, yang membuat Postgres menolak jalan.
rm -f "$PGDATA/postmaster.pid"
info "$(t 'Menyalakan PostgreSQL...' 'Starting PostgreSQL...')"
if ! pg_ctl -D "$PGDATA" -l "$PGLOG" -w -t 120 -s start; then
    gagal "$(t 'PostgreSQL gagal menyala:' 'PostgreSQL failed to start:')"; tail -n 20 "$PGLOG"; exit 1
fi
pg_berhenti() { pg_ctl -D "$PGDATA" -m fast -w -t 90 -s stop 2>/dev/null; }

PSQL="psql -X -q -v ON_ERROR_STOP=1 -h $PGRUN -p $PG_PORT -U postgres -d postgres"
# database "app": siap dipakai workflow (node Postgres di n8n) dan aplikasi lain, terpisah dari database sistem
if ! $PSQL -v su="$PG_SUPER_PASSWORD" -v n8npw="$PG_N8N_PASSWORD" -v evopw="$PG_EVO_PASSWORD" -v apppw="$PG_APP_PASSWORD" > "$P/psql.log" 2>&1 <<'SQL'
SELECT format('ALTER ROLE postgres PASSWORD %L', :'su') \gexec
SELECT format('CREATE ROLE n8n LOGIN PASSWORD %L', :'n8npw') WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'n8n') \gexec
SELECT format('ALTER ROLE n8n PASSWORD %L', :'n8npw') \gexec
SELECT format('CREATE ROLE evolution LOGIN PASSWORD %L', :'evopw') WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'evolution') \gexec
SELECT format('ALTER ROLE evolution PASSWORD %L', :'evopw') \gexec
SELECT 'CREATE DATABASE n8n OWNER n8n' WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'n8n') \gexec
SELECT 'CREATE DATABASE evolution OWNER evolution' WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'evolution') \gexec
SELECT format('CREATE ROLE app LOGIN PASSWORD %L', :'apppw') WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app') \gexec
SELECT format('ALTER ROLE app PASSWORD %L', :'apppw') \gexec
SELECT 'CREATE DATABASE app OWNER app' WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'app') \gexec
SQL
then
    gagal "$(t 'Gagal menyiapkan user/database Postgres:' 'Failed to prepare Postgres users/databases:')"; tail -n 10 "$P/psql.log"
    pg_berhenti; exit 1
fi

# ------------------------------------------------------------------ penghentian rapi
N8N_PID=""; EVO_SUP=""; CADDY_PID=""; BERHENTI=0
tunggu_mati() { _i=0; while [ -n "$1" ] && kill -0 "$1" 2>/dev/null && [ "$_i" -lt "$2" ]; do sleep 1; _i=$((_i + 1)); done; }
berhenti() {
    [ "$BERHENTI" = 1 ] && return
    BERHENTI=1
    info "$(t 'Menghentikan n8n, Evolution API, dan PostgreSQL...' 'Stopping n8n, Evolution API, and PostgreSQL...')"
    # Proses latar di shell non-interaktif mengabaikan SIGINT, jadi semua dihentikan dengan SIGTERM.
    [ -n "$N8N_PID" ] && kill -TERM "$N8N_PID" 2>/dev/null; tunggu_mati "$N8N_PID" 40
    [ -n "$EVO_SUP" ] && kill -TERM "$EVO_SUP" 2>/dev/null; tunggu_mati "$EVO_SUP" 20
    for p in "$CADDY_PID" "$TUNNEL_PID"; do [ -n "$p" ] && kill -TERM "$p" 2>/dev/null; done
    if pg_berhenti; then info "$(t 'PostgreSQL berhenti dengan rapi.' 'PostgreSQL shut down cleanly.')"
    else warn "$(t 'PostgreSQL tidak berhenti dengan rapi; data dipulihkan otomatis saat start berikutnya.' 'PostgreSQL did not shut down cleanly; it will recover automatically on next start.')"; fi
}
trap 'berhenti; exit 0' INT TERM

# ------------------------------------------------------------------ Evolution API
EVO="$H/evolution"; EVO_LOG="$EVO/evolution.log"
mkdir -p "$EVO/instances" "$EVO/store"
# Evolution membaca manager/, public/, views/ dan ./package.json (versi) dari folder kerjanya;
# programnya sendiri di /opt/evolution (hanya-baca), jadi folder kerja berisi tautan ke sana.
for d in manager public views package.json; do
    if [ -e "/opt/evolution/$d" ] && { [ -L "$EVO/$d" ] || [ ! -e "$EVO/$d" ]; }; then ln -sfn "/opt/evolution/$d" "$EVO/$d"; fi
done
putar_log "$EVO_LOG"
q() { printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"; }
case "${EVOLUTION_SIMPAN_PESAN:-true}" in false|0) SIMPAN=false ;; *) SIMPAN=true ;; esac
EVO_DB_URI="postgresql://evolution:${PG_EVO_PASSWORD}@127.0.0.1:${PG_PORT}/evolution?schema=public"
cat > "$EVO/.env" <<EOF
# Dibuat ulang setiap start oleh paket-lengkap: perubahan di sini akan hilang.
# Pengaturan tambahan Evolution API (S3, Chatwoot, webhook global, dll.): tulis di evolution/tambahan.env
SERVER_NAME=evolution
SERVER_TYPE=http
SERVER_PORT=${EVO_DALAM}
SERVER_URL=$(q "$EVO_URL")
TELEMETRY_ENABLED=false
CORS_ORIGIN=*
CORS_METHODS=GET,POST,PUT,DELETE
CORS_CREDENTIALS=true
LOG_LEVEL=ERROR,WARN,INFO
LOG_COLOR=false
LOG_BAILEYS=error
DEL_INSTANCE=false
DATABASE_PROVIDER=postgresql
DATABASE_CONNECTION_URI=$(q "$EVO_DB_URI")
DATABASE_CONNECTION_CLIENT_NAME=evolution
DATABASE_SAVE_DATA_INSTANCE=true
DATABASE_SAVE_DATA_NEW_MESSAGE=${SIMPAN}
DATABASE_SAVE_MESSAGE_UPDATE=${SIMPAN}
DATABASE_SAVE_DATA_CONTACTS=true
DATABASE_SAVE_DATA_CHATS=true
DATABASE_SAVE_DATA_LABELS=true
DATABASE_SAVE_DATA_HISTORIC=${SIMPAN}
CACHE_REDIS_ENABLED=false
CACHE_LOCAL_ENABLED=true
WEBSOCKET_ENABLED=false
RABBITMQ_ENABLED=false
S3_ENABLED=false
AUTHENTICATION_API_KEY=$(q "$EVO_KEY")
AUTHENTICATION_EXPOSE_IN_FETCH_INSTANCES=true
CONFIG_SESSION_PHONE_CLIENT=$(q "${EVOLUTION_NAMA_PERANGKAT:-Evolution API}")
CONFIG_SESSION_PHONE_NAME=Chrome
QRCODE_LIMIT=30
LANGUAGE=en
EOF
chmod 600 "$EVO/.env"

info "$(t 'Memperbarui database Evolution API...' 'Updating the Evolution API database...')"
EVO_SIAP=1
if ! ( cd /opt/evolution && DATABASE_CONNECTION_URI="$EVO_DB_URI" ./node_modules/.bin/prisma migrate deploy --schema ./prisma/postgresql-schema.prisma ) > "$P/migrasi-evolution.log" 2>&1; then
    gagal "$(t 'Migrasi database Evolution API gagal; Evolution tidak dinyalakan (n8n tetap jalan):' 'Evolution API database migration failed; Evolution is not started (n8n keeps running):')"
    tail -n 15 "$P/migrasi-evolution.log"
    EVO_SIAP=0
fi

evo_awasi() {
    anak=""
    trap '[ -n "$anak" ] && kill -TERM "$anak" 2>/dev/null; tunggu_mati "$anak" 15; exit 0' TERM INT
    gagal_beruntun=0
    while :; do
        mulai=$(date +%s)
        (
            cd "$EVO" || exit 1
            set -a
            . "$EVO/.env"
            [ -f "$EVO/tambahan.env" ] && . "$EVO/tambahan.env"
            SERVER_PORT=$EVO_DALAM
            set +a
            [ -n "$HEAP_EVO" ] && export NODE_OPTIONS="--max-old-space-size=${HEAP_EVO}"
            exec node /opt/evolution/dist/main.js
        ) >> "$EVO_LOG" 2>&1 &
        anak=$!
        wait "$anak"; kode=$?
        anak=""
        if [ $(( $(date +%s) - mulai )) -lt 60 ]; then gagal_beruntun=$((gagal_beruntun + 1)); else gagal_beruntun=0; fi
        warn "$(t "Evolution API berhenti (kode $kode), dinyalakan ulang. Log: evolution/evolution.log" "Evolution API stopped (code $kode), restarting. Log: evolution/evolution.log")"
        tail -n 5 "$EVO_LOG" 2>/dev/null
        if [ "$gagal_beruntun" -ge 5 ]; then
            warn "$(t 'Evolution API gagal 5 kali berturut-turut; coba lagi 2 menit lagi.' 'Evolution API failed 5 times in a row; retrying in 2 minutes.')"
            sleep 120; gagal_beruntun=0
        else
            sleep 3
        fi
    done
}
if [ "$EVO_SIAP" = 1 ]; then
    info "$(t 'Menyalakan Evolution API...' 'Starting Evolution API...')"
    evo_awasi &
    EVO_SUP=$!
fi

# ------------------------------------------------------------------ Caddy (satu port untuk semuanya)
mkdir -p "$P/caddy"
export XDG_DATA_HOME="$P/caddy" XDG_CONFIG_HOME="$P/caddy"
{
    cat <<EOF
{
	admin off
	auto_https off
	persist_config off
	log {
		output file ${P}/caddy.log {
			roll_size 5MiB
			roll_keep 2
		}
		level ERROR
	}
}

:${PORT} {
	# berkas halaman manager Evolution memakai /assets/... (sama dengan n8n): hanya nama berkas
	# yang benar-benar ada di manager Evolution yang diarahkan ke sana, sisanya tetap ke n8n
	@evoaset {
		path /assets/*
		file {
			root /opt/evolution/manager/dist
		}
	}
	handle @evoaset {
		root * /opt/evolution/manager/dist
		file_server
	}
	redir /evo /evo/ 308
	handle_path /evo/* {
		reverse_proxy 127.0.0.1:${EVO_DALAM}
	}
	handle /manager* {
		reverse_proxy 127.0.0.1:${EVO_DALAM}
	}
	handle {
		reverse_proxy 127.0.0.1:${N8N_DALAM}
	}
}
EOF
    if [ -n "$EVO_PORT" ]; then
        cat <<EOF

:${EVO_PORT} {
	reverse_proxy 127.0.0.1:${EVO_DALAM}
}
EOF
    fi
} > "$P/Caddyfile"
caddy run --config "$P/Caddyfile" --adapter caddyfile > "$P/caddy-start.log" 2>&1 &
CADDY_PID=$!
sleep 1
if ! kill -0 "$CADDY_PID" 2>/dev/null; then
    gagal "$(t 'Proxy (Caddy) gagal menyala:' 'The proxy (Caddy) failed to start:')"; tail -n 10 "$P/caddy-start.log"
    berhenti; exit 1
fi

# ------------------------------------------------------------------ kredensial.txt
K="$H/kredensial.txt"
{
    if [ "$LANG_ID" = 1 ]; then
        echo "# Dibuat ulang setiap server start. Jangan bagikan isi berkas ini."
        echo
        echo "n8n"
        echo "  Alamat              : ${URL_PUBLIK}"
        echo
        echo "Evolution API (WhatsApp)"
        echo "  Alamat server       : ${EVO_URL}"
        echo "  Manager (scan QR)   : ${MANAGER_URL}"
        echo "  API key global      : ${EVO_KEY}"
        echo "  Dari n8n (internal) : http://127.0.0.1:${EVO_DALAM}  (header apikey: API key di atas)"
        echo
        echo "PostgreSQL"
        echo "  Dari n8n / server   : host 127.0.0.1, port ${PG_PORT}"
        [ -n "$PG_PUBLIK" ] && echo "  Dari luar           : host ${HOST_PUBLIK}, port ${PG_PUBLIK}"
        echo "  Database data kamu  : app  (user app / ${PG_APP_PASSWORD})"
        echo "  Admin (superuser)   : postgres / ${PG_SUPER_PASSWORD}"
        echo "  Catatan             : database n8n dan evolution dipakai sistem, jangan diubah"
    else
        echo "# Regenerated on every server start. Do not share this file."
        echo
        echo "n8n"
        echo "  URL                 : ${URL_PUBLIK}"
        echo
        echo "Evolution API (WhatsApp)"
        echo "  Server URL          : ${EVO_URL}"
        echo "  Manager (scan QR)   : ${MANAGER_URL}"
        echo "  Global API key      : ${EVO_KEY}"
        echo "  From n8n (internal) : http://127.0.0.1:${EVO_DALAM}  (apikey header: the key above)"
        echo
        echo "PostgreSQL"
        echo "  From n8n / server   : host 127.0.0.1, port ${PG_PORT}"
        [ -n "$PG_PUBLIK" ] && echo "  From outside        : host ${HOST_PUBLIK}, port ${PG_PUBLIK}"
        echo "  Your data database  : app  (user app / ${PG_APP_PASSWORD})"
        echo "  Admin (superuser)   : postgres / ${PG_SUPER_PASSWORD}"
        echo "  Note                : the n8n and evolution databases are used by the system, do not change them"
    fi
} > "$K"
chmod 600 "$K"
# alamat dalam untuk alat otomatis (tanpa rahasia)
printf 'N8N_DALAM=%s\nEVO_DALAM=%s\nPG_PORT=%s\nPORT=%s\n' "$N8N_DALAM" "$EVO_DALAM" "$PG_PORT" "$PORT" > "$P/port.env"

# ------------------------------------------------------------------ n8n (proses utama)
export N8N_USER_FOLDER="$H"
mkdir -p "$H/.n8n"
if [ -f "$H/tambahan-n8n.env" ]; then set -a; . "$H/tambahan-n8n.env"; set +a; fi
export DB_TYPE=postgresdb DB_POSTGRESDB_HOST=127.0.0.1 DB_POSTGRESDB_PORT="$PG_PORT" DB_POSTGRESDB_DATABASE=n8n \
       DB_POSTGRESDB_USER=n8n DB_POSTGRESDB_PASSWORD="$PG_N8N_PASSWORD" DB_POSTGRESDB_SCHEMA=public
export N8N_LISTEN_ADDRESS=127.0.0.1 N8N_PORT="$N8N_DALAM" N8N_RUNNERS_BROKER_PORT="$N8N_BROKER" N8N_PROXY_HOPS=1
export N8N_HOST="$HOST_PUBLIK" N8N_PROTOCOL="$PROTO" N8N_WEBHOOK_URL="$URL_PUBLIK" N8N_EDITOR_BASE_URL="${N8N_EDITOR_BASE_URL:-$URL_PUBLIK}"
export N8N_SECURE_COOKIE="${N8N_SECURE_COOKIE:-false}"
export EXECUTIONS_DATA_PRUNE=true EXECUTIONS_DATA_MAX_AGE="${EXECUTIONS_DATA_MAX_AGE:-336}"
if [ -n "$HEAP_N8N" ]; then export NODE_OPTIONS="--max-old-space-size=${HEAP_N8N} ${NODE_OPTIONS:-}"; fi
# variabel egg yang tidak perlu terlihat oleh n8n
unset EVOLUTION_API_KEY CLOUDFLARE_TUNNEL_TOKEN

info "$(t 'Menyalakan n8n (start pertama bisa 1-2 menit)...' 'Starting n8n (the first start can take 1-2 minutes)...')"
printf "%b\n" "$LINE"
n8n start &
N8N_PID=$!
wait "$N8N_PID"
kode=$?
# n8n berhenti sendiri (bukan dari tombol stop): matikan yang lain dengan rapi, kode keluar diteruskan ke panel
if [ "$BERHENTI" = 0 ]; then
    warn "$(t "n8n berhenti sendiri (kode $kode)." "n8n stopped on its own (code $kode).")"
    berhenti
    exit "$kode"
fi
exit 0
