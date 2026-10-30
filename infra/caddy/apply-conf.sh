#!/usr/bin/env bash
# Rulează PE SERVER, trimis de workflow prin: ssh deploy 'bash -s' < infra/caddy/apply-conf.sh
# Înainte, workflow-ul a copiat infra/caddy/conf/ în ~/proiecte/caddy/conf.next/.
#
# 1. verifică faptul că Caddy are /etc/caddy montat ca DIRECTOR din ~/proiecte/caddy/conf
# 2. construiește configurația candidat: conf/ actual + sites/ din repo (cu ștergere) + Caddyfile din repo
# 3. o validează cu un container Caddy temporar (aceeași imagine); dacă pică, nu se atinge nimic
# 4. o aplică și face reload; dacă reload-ul pică, pune la loc configurația anterioară
set -euo pipefail

CADDY_DIR="$HOME/proiecte/caddy"
CONF="$CADDY_DIR/conf"
STAGE="$CADDY_DIR/conf.next"
BACKUPS="$CADDY_DIR/conf.backups"
CONTAINER="${CADDY_CONTAINER:-caddy-caddy-1}"

fail() { echo "::error::$*"; exit 1; }

# --- 1. Protecție: fără migrarea la volum-director nu facem nimic ---
if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
  fail "Containerul $CONTAINER nu există. Deploy-ul Caddy s-a oprit; nimic nu a fost modificat."
fi

mount_type=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/etc/caddy"}}{{.Type}}{{end}}{{end}}' "$CONTAINER")
mount_src=$(docker inspect -f '{{range .Mounts}}{{if eq .Destination "/etc/caddy"}}{{.Source}}{{end}}{{end}}' "$CONTAINER")

if [ -z "$mount_src" ] || [ "$(readlink -f "$mount_src")" != "$(readlink -f "$CONF")" ] || [ ! -d "$mount_src" ]; then
  echo "::error::Caddy NU are $CONF montat ca director pe /etc/caddy."
  echo "Montări curente ale lui $CONTAINER:"
  docker inspect -f '{{range .Mounts}}  {{.Type}} {{.Source}} -> {{.Destination}}{{println}}{{end}}' "$CONTAINER"
  echo "Probabil Caddyfile-ul e încă montat ca fișier singur. Fă întâi migrarea descrisă în README"
  echo "(secțiunea „Migrare Caddy la conf/”). Deploy-ul Caddy s-a oprit; nimic nu a fost modificat."
  exit 1
fi
[ "$mount_type" = "bind" ] || fail "/etc/caddy e montat ca '$mount_type', se aștepta 'bind'."
[ -f "$STAGE/Caddyfile" ] || fail "$STAGE/Caddyfile lipsește: sincronizarea din workflow nu a reușit."

# --- 2. Configurația candidat ---
CANDIDATE=$(mktemp -d)
trap 'rm -rf "$CANDIDATE"' EXIT
cp -a "$CONF/." "$CANDIDATE/"
mkdir -p "$CANDIDATE/sites"
rsync -a --delete "$STAGE/sites/" "$CANDIDATE/sites/"
cp "$STAGE/Caddyfile" "$CANDIDATE/Caddyfile"
chmod -R a+rX "$CANDIDATE"

echo "Modificări în sites/ față de server:"
diff -ru "$CONF/sites" "$CANDIDATE/sites" || true

# --- 3. Validare cu aceeași imagine ca și containerul care rulează ---
IMAGE=$(docker inspect -f '{{.Config.Image}}' "$CONTAINER")
echo "Validez cu $IMAGE ..."
if ! docker run --rm --network none -v "$CANDIDATE:/etc/caddy:ro" "$IMAGE" \
     caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile; then
  fail "caddy validate a eșuat. Configurația live NU a fost modificată."
fi

# --- 4. Aplicare ---
STAMP=$(date +%Y%m%d-%H%M%S)
mkdir -p "$BACKUPS"
PREVIOUS="$BACKUPS/$STAMP"
cp -a "$CONF" "$PREVIOUS"

if ! cmp -s "$CONF/Caddyfile" "$CANDIDATE/Caddyfile"; then
  echo "::warning::Caddyfile-ul de pe server diferă de cel din repo și va fi înlocuit. Copie: $PREVIOUS/Caddyfile"
  diff -u "$CONF/Caddyfile" "$CANDIDATE/Caddyfile" || true
fi

mkdir -p "$CONF/sites"
rsync -a --delete "$CANDIDATE/sites/" "$CONF/sites/"
cp "$CANDIDATE/Caddyfile" "$CONF/Caddyfile"

if docker exec "$CONTAINER" caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile; then
  echo "Caddy reîncărcat. Copie a configurației anterioare: $PREVIOUS"
else
  echo "::error::caddy reload a eșuat; pun la loc configurația anterioară."
  rsync -a --delete "$PREVIOUS/sites/" "$CONF/sites/"
  cp "$PREVIOUS/Caddyfile" "$CONF/Caddyfile"
  docker exec "$CONTAINER" caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile \
    || echo "::error::Și reload-ul configurației anterioare a eșuat. Verifică manual: docker logs $CONTAINER"
  exit 1
fi

# Păstrăm ultimele 10 copii.
ls -1d "$BACKUPS"/*/ 2>/dev/null | sort | head -n -10 | xargs -r rm -rf
rm -rf "$STAGE"
