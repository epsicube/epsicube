#!/usr/bin/env bash
set -Eeuo pipefail

# --- Global Variables ---
CUSTOM_CONFIG="/usr/local/pgbackrest.conf"
CRON_TMP="/tmp/crontab"

# --- Functions ---

import_system_cron() {
    if [ -f /etc/crontab ]; then
        echo "System: Importing existing /etc/crontab"
        cp /etc/crontab "$CRON_TMP"
    else
        echo "System: No /etc/crontab found, creating empty task list"
        touch "$CRON_TMP"
    fi
}

handle_pgbackrest_conf() {
    local PGBACKREST_CONFIG="/etc/pgbackrest/pgbackrest.conf"
    mkdir -p /etc/pgbackrest

    if [ -f "$CUSTOM_CONFIG" ]; then
        echo "Config: Custom configuration found at $CUSTOM_CONFIG. Overwriting $PGBACKREST_CONFIG"
        cp "$CUSTOM_CONFIG" "$PGBACKREST_CONFIG"
    else
        echo "Config: No custom configuration found. Generating default $PGBACKREST_CONFIG"
        cat <<EOF > "$PGBACKREST_CONFIG"
[main]
pg1-path=${PGDATA:-/var/lib/postgresql/data}
pg1-port=5432

[global]
repo1-path=/var/lib/pgbackrest
spool-path=/spool/pgbackrest
lock-path=/spool/pgbackrest

repo1-bundle=y
repo1-bundle-limit=20MiB

archive-async=y
archive-copy=y

start-fast=y
delta=y

repo1-retention-full=${BACKUP_FULL_RETENTION:-52}
repo1-retention-diff=${BACKUP_DIFF_RETENTION:-31}
repo1-retention-archive-type=full
repo1-retention-archive=${BACKUP_ARCHIVE_RETENTION:-31}

process-max=2
compress-type=zst
compress-level=3
log-level-console=info
log-level-file=debug
EOF
        echo "Config: Default configuration written"
    fi
}

bootstrap_stanza() {
    if pgbackrest --stanza=main info 2>/dev/null | grep -q "status: ok"; then
        echo "Bootstrap: Stanza 'main' is OK"
        return
    fi

    echo "Bootstrap: Stanza missing, starting PostgreSQL without archiving"
    /usr/local/bin/docker-entrypoint.sh "$@" &
    local pg_pid=$!

    until pg_isready -q; do
        kill -0 "$pg_pid" 2>/dev/null || { echo "Bootstrap: PostgreSQL exited unexpectedly"; exit 1; }
        sleep 2
    done

    echo "Bootstrap: Running stanza-create..."

    until pgbackrest --stanza=main stanza-create; do
        kill -0 "$pg_pid" 2>/dev/null || { echo "Bootstrap: PostgreSQL exited unexpectedly"; exit 1; }
        sleep 2
    done

    until pg_isready -q; do sleep 1; done

    echo "Bootstrap: Stopping PostgreSQL (fast shutdown)"
    kill -INT "$pg_pid"
    wait "$pg_pid" || true
    echo "Bootstrap: Done, restarting with archiving enabled"
}

initialize_pgbackrest_async() {
    (
        echo "Init: Waiting for PostgreSQL to be ready..."
        until pg_isready -q; do sleep 2; done
        echo "Init: PostgreSQL is ready"

        if ! pgbackrest --stanza=main info | grep -q "full"; then
            echo "Init: Starting bootstrap backup..."
            pgbackrest --stanza=main --type=full backup
        else
            echo "Init: Existing backup found"
        fi
    ) &
}

schedule_backups() {
    [ -n "${BACKUP_FULL_CRON:-}" ] && echo "${BACKUP_FULL_CRON} pgbackrest --stanza=main --type=full backup" >> "$CRON_TMP"
    [ -n "${BACKUP_DIFF_CRON:-}" ] && echo "${BACKUP_DIFF_CRON} pgbackrest --stanza=main --type=diff backup" >> "$CRON_TMP"
    [ -n "${BACKUP_INCR_CRON:-}" ] && echo "${BACKUP_INCR_CRON} pgbackrest --stanza=main --type=incr backup" >> "$CRON_TMP"
}

# --- Main Flow ---

import_system_cron

if [ "${BACKUP_ENABLED:-false}" = "true" ]; then
    handle_pgbackrest_conf

    # Logic only for Postgres Server mode
    if [ "$1" = "postgres" ]; then
        echo "--- Mode: PostgreSQL Server with Backup ---"
        bootstrap_stanza "$@"
        initialize_pgbackrest_async
        schedule_backups

        echo "Postgres: Injecting backup runtime arguments"
        set -- "$@" \
            -c wal_level=replica \
            -c archive_mode=on \
            -c "archive_command=pgbackrest --stanza=main archive-push %p" \
            -c max_wal_senders=2 \
            -c archive_timeout=600s
    else
        echo "--- Mode: Maintenance / Custom Command ($1) ---"
    fi
else
    echo "--- Backup system disabled ---"
fi

# Handover
if [ "$1" = "postgres" ]; then
    supercronic "$CRON_TMP" &
    exec /usr/local/bin/docker-entrypoint.sh "$@"
else
    # Direct execution for restore, bash, or pgbackrest commands
    exec "$@"
fi
