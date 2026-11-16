#!/bin/bash
set -euo pipefail
umask 077

resources="$(cd "$(dirname "$0")" && pwd -P)"
state="${MU_SOLO_STATE_DIR:-$HOME/Library/Application Support/MU Solo}"
pg="$resources/PostgreSQL/bin"
data="$state/database"
log="$state/logs"
server="$resources/OpenMU/MUnique.OpenMU.Startup"
port=55436

mkdir -p "$log"
chmod 700 "$state"
exec >>"$log/launcher.log" 2>&1

if [[ ! -f "$state/postgres-password" ]]; then
    /usr/bin/openssl rand -hex 24 >"$state/postgres-password.new"
    mv "$state/postgres-password.new" "$state/postgres-password"
fi

if [[ ! -f "$data/PG_VERSION" ]]; then
    # Keep an interrupted initialization separate from the permanent database.
    staging="$(mktemp -d "$state/database-init.XXXXXX")"
    "$pg/initdb" -D "$staging" -U postgres --auth-host=scram-sha-256 \
        --auth-local=reject --pwfile="$state/postgres-password" --locale=C --encoding=UTF8
    [[ ! -e "$data" ]] || { echo "Database directory exists without PG_VERSION."; exit 1; }
    mv "$staging" "$data"
fi

game_pid=
postgres_started=0
cleanup() {
    trap '' TERM INT
    if [[ -n "$game_pid" ]]; then
        kill -TERM "$game_pid" 2>/dev/null || true
        wait "$game_pid" || true
    fi
    if [[ "$postgres_started" == 1 ]]; then
        "$pg/pg_ctl" -D "$data" -m fast -w stop
    fi
}
trap cleanup EXIT
trap 'exit 0' TERM INT

"$pg/pg_ctl" -D "$data" -l "$log/postgres.log" -w \
    -o "-h 127.0.0.1 -p $port -c unix_socket_directories=" start
postgres_started=1

export MU_SOLO_LOCAL=1
export DB_HOST=127.0.0.1
export DB_ADMIN_USER=postgres
export ASPNETCORE_URLS=http://127.0.0.1:0
DB_ADMIN_PW="$(cat "$state/postgres-password")"
export DB_ADMIN_PW
cd "$resources/OpenMU"
"$server" -autostart -version:season6 -adminpanel:disabled -resolveIP:127.0.0.1 \
    >>"$log/server.log" 2>&1 &
game_pid=$!
wait "$game_pid"
