#!/usr/bin/env bash
set -Eeuo pipefail

# --- Global Variables ---
CUSTOM_CONFIG="/usr/local/pgbackrest.conf"
CRON_TMP="/tmp/crontab"
CURRENT_PGDATA="${PGDATA:-/var/lib/postgresql/data}"

# --- Functions ---

import_system_cron() {
    if [ -f /etc/crontab ]; then
        echo "System: Importing existing /etc/crontab"
        cp /etc/crontab "$CRON_TMP"
    else
        echo "System: No existing /etc/crontab found, creating empty task list"
        touch "$CRON_TMP"
    fi
}

handle_pgbackrest_conf() {
    local PGBACKREST_CONFIG="/etc/pgbackrest/pgbackrest.conf"

    # Ensure the configuration directory exists
    mkdir -p /etc/pgbackrest

    if [ -f "$CUSTOM_CONFIG" ]; then
        echo "Config: Custom configuration found at $CUSTOM_CONFIG. Overwriting $PGBACKREST_CONFIG"
        cp "$CUSTOM_CONFIG" "$PGBACKREST_CONFIG"
    else
        echo "Config: No custom configuration found. Generating default $PGBACKREST_CONFIG"
        cat <<EOF > "$PGBACKREST_CONFIG"
[main]
pg1-path=${CURRENT_PGDATA}
pg1-port=5432

[global]
repo1-path=/var/lib/pgbackrest
spool-path=/spool/pgbackrest
lock-path=/spool/pgbackrest
repo1-bundle=y
repo1-bundle-limit=20MiB
archive-async=y
archive-copy=y
repo1-retention-full=30
repo1-retention-archive-type=full
process-max=2
compress-type=zst
compress-level=3
log-level-console=info
log-level-file=debug
EOF
        echo "Config: Default configuration written"
    fi
}

initialize_pgbackrest_async() {
    (
        echo "Init: Waiting for PostgreSQL to be ready..."
        until pg_isready -q; do sleep 2; done
        echo "Init: PostgreSQL is ready for commands"

        # Stanza initialization
        if ! pgbackrest info | grep -q "status: ok"; then
            echo "Init: Stanza 'main' is missing or broken. Running stanza-create..."
            pgbackrest --stanza=main stanza-create
        else
            echo "Init: Stanza 'main' already exists and is OK"
        fi

        # Bootstrap full backup
        if ! pgbackrest --stanza=main info | grep -q "full"; then
            echo "Init: No full backup found in repository. Starting bootstrap..."
            pgbackrest --stanza=main --type=full backup
            echo "Init: Bootstrap backup finished successfully"
        else
            echo "Init: Repository already contains a full backup. Skipping bootstrap"
        fi

        echo "Init: pgBackRest setup is complete"
    ) &
}

schedule_backups() {
    if [ -n "${BACKUP_FULL_CRON:-}" ]; then
        echo "Cron: Adding FULL backup schedule -> ${BACKUP_FULL_CRON}"
        echo "${BACKUP_FULL_CRON} pgbackrest --stanza=main --type=full backup" >> "$CRON_TMP"
    else
        echo "Cron: Variable BACKUP_FULL_CRON is empty, skipping"
    fi

    if [ -n "${BACKUP_INCR_CRON:-}" ]; then
        echo "Cron: Adding INCR backup schedule -> ${BACKUP_INCR_CRON}"
        echo "${BACKUP_INCR_CRON} pgbackrest --stanza=main --type=incr backup" >> "$CRON_TMP"
    else
        echo "Cron: Variable BACKUP_INCR_CRON is empty, skipping"
    fi
}

# --- Main Flow ---

import_system_cron

if [ "${BACKUP_ENABLED:-false}" = "true" ]; then
    echo "--- Backup system activation sequence started ---"

    handle_pgbackrest_conf
    initialize_pgbackrest_async
    schedule_backups

    echo "Postgres: Adding backup runtime arguments (-c)"
    set -- "$@" \
        -c wal_level=replica \
        -c archive_mode=on \
        -c "archive_command=pgbackrest --stanza=main archive-push %p" \
        -c max_wal_senders=2 \
        -c archive_timeout=600s
else
    echo "--- Backup system remains disabled (BACKUP_ENABLED is not true) ---"
fi

echo "System: Launching Supercronic scheduler"
supercronic "$CRON_TMP" &

echo "System: Executing PostgreSQL entrypoint script"
exec /usr/local/bin/docker-entrypoint.sh "$@"
