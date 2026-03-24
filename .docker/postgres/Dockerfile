FROM postgres:18.1-alpine3.23

RUN apk add --no-cache pgbackrest \
    && mkdir -p /var/lib/pgbackrest /var/log/pgbackrest /etc/pgbackrest /spool/pgbackrest \
    && chown -R postgres:postgres /var/lib/pgbackrest /var/log/pgbackrest /etc/pgbackrest /spool/pgbackrest \
    && chmod 750 /var/lib/pgbackrest

ENV SUPERCRONIC_URL=https://github.com/aptible/supercronic/releases/download/v0.2.44/supercronic-linux-amd64 \
    SUPERCRONIC_SHA1SUM=6eb0a8e1e6673675dc67668c1a9b6409f79c37bc \
    SUPERCRONIC=supercronic-linux-amd64

RUN apk add --no-cache curl  \
    && curl -fsSLO "$SUPERCRONIC_URL" \
    && echo "${SUPERCRONIC_SHA1SUM}  ${SUPERCRONIC}" | sha1sum -c - \
    && chmod +x "$SUPERCRONIC" \
    && mv "$SUPERCRONIC" "/usr/local/bin/${SUPERCRONIC}" \
    && ln -s "/usr/local/bin/${SUPERCRONIC}" /usr/local/bin/supercronic


# Configuration and scripts
COPY --chown=postgres:postgres entrypoint-wrapper.sh /usr/local/bin/entrypoint-wrapper.sh
RUN chmod +x /usr/local/bin/entrypoint-wrapper.sh

# Volumes declaration
# /var/lib/pgbackrest: Persistent backup storage
# /spool/pgbackrest: High-frequency I/O for async archiving and locks
VOLUME ["/var/lib/pgbackrest", "/spool/pgbackrest"]

# Default backup schedules
ENV BACKUP_ENABLED=false
ENV BACKUP_FULL_CRON="0 3 * * 0"
ENV BACKUP_DIFF_CRON="0 3 * * 1-6"
ENV BACKUP_INCR_CRON="0 0-2,4-23 * * *"
ENV BACKUP_FULL_RETENTION=52
ENV BACKUP_DIFF_RETENTION=31
ENV BACKUP_ARCHIVE_RETENTION=31


USER postgres
ENTRYPOINT ["entrypoint-wrapper.sh"]
CMD ["postgres"]
