#!/usr/bin/env bash
# Backup pentru toate proiectele din ~/proiecte/<nume>/ (rulează pe server, din cron).
#
# Convenții (aceleași ca la carworld):
#   - baza de date: serviciul compose "db" (Postgres); pg_dump rulează ÎN containerul db,
#     cu POSTGRES_USER/POSTGRES_DB din mediul lui, deci scriptul nu are nevoie de parole;
#   - fișiere urcate: volumul Docker "<nume>_uploads" (ex. carworld_uploads).
#
# Rezultat: $BACKUP_ROOT/<nume>/<YYYYmmdd-HHMMSS>/{db.dump,uploads.tar.gz,SHA256SUMS}
# Retenție: $RETENTION_DAYS zile (implicit 7).
#
# Cron (crontab -e), zilnic la 03:15:
#   15 3 * * * $HOME/proiecte/scripts/backup.sh >> $HOME/backups/backup.log 2>&1
set -uo pipefail

PROJECTS_DIR="${PROJECTS_DIR:-$HOME/proiecte}"
BACKUP_ROOT="${BACKUP_ROOT:-$HOME/backups}"
RETENTION_DAYS="${RETENTION_DAYS:-7}"
HELPER_IMAGE="alpine:3.24.3"
SKIP="caddy scripts landing"

log() { echo "[$(date '+%F %T')] $*"; }

mkdir -p "$BACKUP_ROOT"
exec 9>"$BACKUP_ROOT/.lock"
if ! flock -n 9; then
  log "Un alt backup rulează deja; ies."
  exit 1
fi

STAMP=$(date +%Y%m%d-%H%M%S)
errors=0

for dir in "$PROJECTS_DIR"/*/; do
  name=$(basename "$dir")
  [[ " $SKIP " == *" $name "* ]] && continue
  [ -f "$dir/docker-compose.yml" ] || [ -f "$dir/compose.yml" ] || continue

  partial="$BACKUP_ROOT/$name/.$STAMP.partial"
  final="$BACKUP_ROOT/$name/$STAMP"
  mkdir -p "$partial"
  did_something=0
  ok=1

  # --- Postgres ---
  db_id=$(cd "$dir" && docker compose ps --status running -q db 2>/dev/null || true)
  if [ -n "$db_id" ]; then
    log "$name: pg_dump"
    if (cd "$dir" && docker compose exec -T db sh -c \
          'pg_dump -U "$POSTGRES_USER" -d "${POSTGRES_DB:-$POSTGRES_USER}" -Fc') > "$partial/db.dump" \
       && [ -s "$partial/db.dump" ]; then
      did_something=1
    else
      log "$name: EROARE la pg_dump"; ok=0
    fi
  fi

  # --- Uploads ---
  volume="${name}_uploads"
  if docker volume inspect "$volume" >/dev/null 2>&1; then
    log "$name: arhivez volumul $volume"
    if docker run --rm --network none -m 64m -v "$volume:/data:ro" "$HELPER_IMAGE" \
         tar -czf - -C /data . > "$partial/uploads.tar.gz" \
       && [ -s "$partial/uploads.tar.gz" ]; then
      did_something=1
    else
      log "$name: EROARE la arhivarea $volume"; ok=0
    fi
  fi

  if [ "$did_something" = 0 ] && [ "$ok" = 1 ]; then
    rm -rf "$partial"
    continue
  fi

  if [ "$ok" = 1 ]; then
    (cd "$partial" && sha256sum -- * > SHA256SUMS)
    chmod -R go-rwx "$partial"
    mv "$partial" "$final"
    log "$name: OK -> $final ($(du -sh "$final" | cut -f1))"
  else
    rm -rf "$partial"
    errors=$((errors + 1))
  fi
done

# --- Retenție: doar directoare de backup finalizate (nume de forma YYYYmmdd-HHMMSS) ---
find "$BACKUP_ROOT" -mindepth 2 -maxdepth 2 -type d -name '[0-9]*-[0-9]*' \
  -mtime +"$((RETENTION_DAYS - 1))" -print -exec rm -rf {} + | sed 's/^/șters: /'
find "$BACKUP_ROOT" -mindepth 2 -maxdepth 2 -type d -name '.*.partial' -mtime +1 -exec rm -rf {} +

if [ "$errors" -gt 0 ]; then
  log "Terminat cu $errors erori."
  exit 1
fi
log "Terminat."
