#!/usr/bin/env bash
# Restaurează un backup făcut de backup.sh (rulează pe server).
#
#   restore.sh <proiect> <director-backup> [--db] [--uploads] [--yes]
#   ex: restore.sh carworld ~/backups/carworld/20261030-031500 --db --uploads
#
# Fără --db/--uploads restaurează tot ce găsește în director.
# Oprește serviciile proiectului în afară de db, restaurează, apoi le pornește la loc.
set -euo pipefail

PROJECTS_DIR="${PROJECTS_DIR:-$HOME/proiecte}"
HELPER_IMAGE="alpine:3.24.3"

usage() { sed -n '2,8p' "$0"; exit 2; }
[ $# -ge 2 ] || usage

name=$1; src=${2%/}; shift 2
want_db=0; want_uploads=0; assume_yes=0
for arg in "$@"; do
  case $arg in
    --db) want_db=1 ;;
    --uploads) want_uploads=1 ;;
    --yes) assume_yes=1 ;;
    *) usage ;;
  esac
done
if [ $want_db = 0 ] && [ $want_uploads = 0 ]; then
  [ -f "$src/db.dump" ] && want_db=1
  [ -f "$src/uploads.tar.gz" ] && want_uploads=1
fi

dir="$PROJECTS_DIR/$name"
[ -d "$dir" ] || { echo "Nu există $dir"; exit 1; }
[ -d "$src" ] || { echo "Nu există $src"; exit 1; }

echo "Verific sumele de control..."
(cd "$src" && sha256sum -c SHA256SUMS)

echo "Voi restaura în proiectul '$name' din $src:"
[ $want_db = 1 ] && echo "  - baza de date (înlocuită complet cu cea din backup)"
[ $want_uploads = 1 ] && echo "  - volumul ${name}_uploads (conținutul actual se șterge)"
if [ $assume_yes = 0 ]; then
  read -r -p "Continui? Scrie numele proiectului: " answer
  [ "$answer" = "$name" ] || { echo "Anulat."; exit 1; }
fi

cd "$dir"
others=$(docker compose config --services | grep -vx db || true)
if [ -n "$others" ]; then
  echo "Opresc: $others"
  # shellcheck disable=SC2086
  docker compose stop $others
fi
trap 'echo "Pornesc serviciile la loc..."; docker compose up -d' EXIT

if [ $want_db = 1 ]; then
  [ -f "$src/db.dump" ] || { echo "Lipsește $src/db.dump"; exit 1; }
  docker compose up -d --wait db
  # Restaurăm într-o bază nouă și o înlocuim pe cea veche doar dacă pg_restore reușește;
  # astfel baza rezultată e identică cu backup-ul (fără tabele create ulterior),
  # iar un dump stricat nu lasă proiectul fără date.
  echo "pg_restore..."
  docker compose exec -T db sh -c '
    set -e
    U="$POSTGRES_USER"; DB="${POSTGRES_DB:-$POSTGRES_USER}"; TMP="${DB}_restore"
    dropdb -U "$U" --if-exists "$TMP"
    createdb -U "$U" -O "$U" "$TMP"
    if ! pg_restore -U "$U" -d "$TMP" --no-owner --single-transaction; then
      dropdb -U "$U" --if-exists "$TMP"; exit 1
    fi
    dropdb -U "$U" --force "$DB"
    psql -q -U "$U" -d postgres -c "ALTER DATABASE \"$TMP\" RENAME TO \"$DB\""
  ' < "$src/db.dump"
fi

if [ $want_uploads = 1 ]; then
  [ -f "$src/uploads.tar.gz" ] || { echo "Lipsește $src/uploads.tar.gz"; exit 1; }
  volume="${name}_uploads"
  echo "Restaurez $volume..."
  docker run --rm -i --network none -v "$volume:/data" "$HELPER_IMAGE" \
    sh -c 'find /data -mindepth 1 -delete && tar -xzf - -C /data' < "$src/uploads.tar.gz"
fi

echo "Restaurare terminată."
