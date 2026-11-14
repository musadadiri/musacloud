#!/usr/bin/env bash
# MusaCloud backup script: encrypted backups to Amazon S3 using restic.
#
#   sudo ./backup.sh init           first time only: create the encrypted backup repository
#   sudo ./backup.sh                run a backup
#   sudo ./backup.sh snapshots      list your backups
#   sudo ./backup.sh test-restore   restore the latest backup to /tmp to prove it works

set -euo pipefail

# Always run from the project folder, even when started by cron
cd "$(dirname "$(readlink -f "$0")")"

if [[ ! -f .env ]]; then
  echo "No .env file found. Copy .env.example to .env and fill it in first." >&2
  exit 1
fi

# Load passwords and AWS keys from .env
set -a
source .env
set +a

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
occ() { docker compose exec -T -u www-data app php occ "$@"; }

case "${1:-backup}" in
  init)
    restic init
    log "Backup repository created in S3."
    ;;

  snapshots)
    restic snapshots
    ;;

  test-restore)
    target=/tmp/musacloud-restore-test
    rm -rf "$target"
    restic restore latest --target "$target"
    log "Restored $(find "$target" -type f | wc -l) files to $target"
    log "Open a few photos and documents in there to confirm they work."
    ;;

  backup)
    log "Turning on maintenance mode (pauses syncing so the backup is consistent)"
    occ maintenance:mode --on
    # Always turn maintenance mode back off, even if a step below fails
    trap 'log "Turning off maintenance mode"; occ maintenance:mode --off' EXIT

    log "Saving the database"
    mkdir -p db-dump
    docker compose exec -T db pg_dump -U "$POSTGRES_USER" "$POSTGRES_DB" > db-dump/nextcloud.sql

    log "Uploading encrypted backup to S3"
    restic backup nextcloud db-dump --tag musacloud

    log "Deleting old backups (keeping 7 daily, 4 weekly, 6 monthly)"
    restic forget --keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune

    log "Backup finished"
    ;;

  *)
    echo "Unknown command: ${1:-}" >&2
    echo "Use: init | snapshots | test-restore | (nothing) to back up" >&2
    exit 1
    ;;
esac
