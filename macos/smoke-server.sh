#!/bin/bash
set -euo pipefail

resources="$1"
export MU_SOLO_STATE_DIR
MU_SOLO_STATE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mu-solo-smoke.XXXXXX")"
state="$MU_SOLO_STATE_DIR"
launcher_pid=

stop() {
    if [[ -n "$launcher_pid" ]]; then
        kill -TERM "$launcher_pid" 2>/dev/null || true
        wait "$launcher_pid"
        launcher_pid=
    fi
}

cleanup() {
    result=$?
    if [[ "$result" != 0 ]]; then
        tail -n 100 "$state"/logs/*.log >&2 || true
    fi
    stop || true
    rm -rf -- "$state"
}
trap cleanup EXIT

start() {
    MU_SOLO_BOT_COUNT="${1:-}" bash "$resources/start-server.sh" &
    launcher_pid=$!
    for ((attempt = 0; attempt < 240; attempt++)); do
        kill -0 "$launcher_pid" 2>/dev/null || return 1
        if /usr/bin/nc -z -G 1 127.0.0.1 44406 2>/dev/null; then
            return
        fi
        sleep 1
    done
    echo "OpenMU did not start listening on port 44406." >&2
    return 1
}

query() {
    PGPASSWORD="$(cat "$state/postgres-password")" \
        "$resources/PostgreSQL/bin/psql" -X -v ON_ERROR_STOP=1 -h 127.0.0.1 \
        -p 55436 -U postgres -d openmu -Atc "$1"
}

wait_for_bots() {
    local count="$1"
    for ((attempt = 0; attempt < 90; attempt++)); do
        kill -0 "$launcher_pid" 2>/dev/null || return 1
        if /usr/bin/grep -Fq "Bot feature started $count of $count bots." "$state/logs/server.log"; then
            return
        fi
        sleep 1
    done
    echo "OpenMU did not start $count bots." >&2
    return 1
}

bot_ids() {
    query 'select "Id" from data."Account" where "IsBot" order by "LoginName" limit 12'
}

start
account_id="$(query "select \"Id\" from data.\"Account\" where \"LoginName\" = 'solo'")"
test -n "$account_id"
wait_for_bots 12
test "$(query 'select count(*) from data."Account" where "IsBot"')" -eq 12
original_bots="$(bot_ids)"
stop
if /usr/bin/nc -z -G 1 127.0.0.1 55436 2>/dev/null; then
    echo "The bundled database did not shut down." >&2
    exit 1
fi

start 3
wait_for_bots 3
test "$account_id" = "$(query "select \"Id\" from data.\"Account\" where \"LoginName\" = 'solo'")"
test "$original_bots" = "$(bot_ids)"
stop

start 0
wait_for_bots 0
test "$original_bots" = "$(bot_ids)"
stop

start 15
wait_for_bots 15
test "$original_bots" = "$(bot_ids)"
test "$(query 'select count(*) from data."Account" where "IsBot"')" -eq 15
stop
echo "Default, lower, zero and higher bot counts passed with the original accounts intact."
