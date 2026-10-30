#!/usr/bin/env bash
# Înregistrează un proiect nou în repo-ul de infrastructură (rulează local, din acest repo).
#
#   scripts/new-project.sh <nume> <subdomeniu> <port-start> [<repo>] [--into <cale-repo-proiect>]
#   ex: scripts/new-project.sh notes notes 10200 notes-app --into ../notes-app
#
#   <nume>   numele scurt: folder ~/proiecte/<nume>, alias-uri <nume>-frontend/-backend (ex. carworld)
#   <repo>   numele repo-ului GitHub Oti404/<repo>; imaginile sunt ghcr.io/oti404/<repo>-frontend/-backend
#            (implicit = <nume>; ex. car-world)
#
# Face (idempotent; nu suprascrie nimic existent):
#   1. infra/caddy/conf/sites/<nume>.caddy   din infra/templates/project.caddy
#   2. un rând în infra/PORTS.md              (interval <port-start>-<port-start+99>)
#   3. o intrare placeholder în src/assets/projects.json (status "wip")
#   4. cu --into: copiază în repo-ul proiectului șabloanele completate (compose, .env.example,
#      workflow, Dockerfile-uri, .dockerignore, nginx.conf); fișierele existente NU sunt atinse.
# Nu face commit și nu atinge serverul. Pașii completi: README, „Deploy proiect nou”.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SITES="$REPO_ROOT/infra/caddy/conf/sites"
PORTS="$REPO_ROOT/infra/PORTS.md"
PROJECTS="$REPO_ROOT/src/assets/projects.json"
TEMPLATES="$REPO_ROOT/infra/templates"
DOMAIN="otnielcodes.com"

die() { echo "Eroare: $*" >&2; exit 1; }
usage() { sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }

# --- Argumente ---
into=""
args=()
while [ $# -gt 0 ]; do
  case $1 in
    --into) [ $# -ge 2 ] || usage; into=$2; shift 2 ;;
    -h|--help) usage ;;
    -*) die "opțiune necunoscută: $1" ;;
    *) args+=("$1"); shift ;;
  esac
done
[ ${#args[@]} -eq 3 ] || [ ${#args[@]} -eq 4 ] || usage
name=${args[0]}; sub=${args[1]}; start=${args[2]}; repo=${args[3]:-${args[0]}}

# --- Validare (totul, înainte să scriem ceva) ---
[[ $name =~ ^[a-z][a-z0-9-]{1,29}$ ]] && [[ $name != *- ]] \
  || die "nume invalid '$name': litere mici, cifre, '-', 2-30 caractere, începe cu literă (ex. carworld)."
[[ $repo =~ ^[a-z0-9][a-z0-9._-]{0,99}$ ]] \
  || die "repo invalid '$repo': litere mici, cifre, '.', '_', '-' (numele imaginilor GHCR trebuie să fie cu litere mici)."
[[ $sub =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]] \
  || die "subdomeniu invalid '$sub': doar eticheta, fără .$DOMAIN (ex. notes)."
case $sub in www|api|mail|caddy) die "subdomeniul '$sub' e rezervat." ;; esac
[[ $start =~ ^[0-9]+$ ]] || die "port-start trebuie să fie număr."
(( start >= 10000 && start <= 65400 && start % 100 == 0 )) \
  || die "port-start trebuie să fie multiplu de 100, între 10000 și 65400 (ex. 10200)."
end=$((start + 99))
command -v node >/dev/null || die "node nu e instalat (necesar pentru projects.json)."
for f in "$PORTS" "$PROJECTS" "$TEMPLATES/project.caddy"; do [ -f "$f" ] || die "lipsește $f"; done
if [ -n "$into" ]; then
  [ -d "$into" ] || die "--into: directorul '$into' nu există (clonează întâi repo-ul proiectului)."
  [ -d "$into/.git" ] || die "--into: '$into' nu e un repo git."
fi

host="$sub.$DOMAIN"
site="$SITES/$name.caddy"

# Subdomeniul nu trebuie folosit de alt site.
if other=$(grep -lE "(^|[ ,])$host([ ,{]|$)" "$SITES"/*.caddy 2>/dev/null | grep -vx "$site"); then
  die "$host e deja folosit în: $other"
fi

# Intervalul nu trebuie să se suprapună cu al altui proiect.
existing_row=$(grep -E "^\| *$name *\|" "$PORTS" || true)
while IFS='|' read -r _ p range _; do
  p=$(echo "$p" | xargs); range=$(echo "$range" | xargs)
  [[ $range =~ ^([0-9]+)-([0-9]+)$ ]] || continue
  [ "$p" = "$name" ] && continue
  a=${BASH_REMATCH[1]}; b=${BASH_REMATCH[2]}
  if (( start <= b && end >= a )); then
    die "intervalul $start-$end se suprapune cu $p ($range)."
  fi
done < "$PORTS"
if [ -n "$existing_row" ] && ! grep -qE "^\| *$name *\| *$start-$end *\|" <<<"$existing_row"; then
  die "$name există deja în PORTS.md cu alt interval: $existing_row"
fi

render() {
  sed -e "s/__NAME__/$name/g" -e "s/__REPO__/$repo/g" \
      -e "s/__SUBDOMAIN__/$sub/g" -e "s/__PORTS__/$start-$end/g" "$1"
}

# --- 1. Site Caddy ---
if [ -f "$site" ]; then
  grep -qE "(^|[ ,])$host([ ,{]|$)" "$site" || die "$site există deja, dar pentru alt subdomeniu."
  echo "✓ infra/caddy/conf/sites/$name.caddy există deja (neschimbat)"
else
  render "$TEMPLATES/project.caddy" > "$site"
  echo "+ creat infra/caddy/conf/sites/$name.caddy"
fi

# --- 2. PORTS.md ---
if [ -n "$existing_row" ]; then
  echo "✓ $name există deja în PORTS.md (neschimbat)"
else
  printf '| %s | %s-%s | %s | ~/proiecte/%s | ghcr.io/oti404/%s-* |\n' \
    "$name" "$start" "$end" "$host" "$name" "$repo" >> "$PORTS"
  echo "+ adăugat rândul în infra/PORTS.md"
fi

# --- 3. projects.json ---
node - "$PROJECTS" "$name" "$host" "$repo" <<'JS'
const fs = require('fs');
const [file, name, host, repo] = process.argv.slice(2);
const projects = JSON.parse(fs.readFileSync(file, 'utf8'));
const liveUrl = `https://${host}`;
if (projects.some((p) => p.name === name || p.liveUrl === liveUrl)) {
  console.log(`✓ ${name} (${liveUrl}) există deja în projects.json (neschimbat)`);
} else {
  projects.push({
    name,
    description: 'Descriere în lucru.',
    technologies: [],
    liveUrl,
    repoUrl: `https://github.com/Oti404/${repo}`,
    image: null,
    status: 'wip',
  });
  fs.writeFileSync(file, JSON.stringify(projects, null, 2) + '\n');
  console.log('+ adăugată intrarea placeholder în src/assets/projects.json');
}
JS

# --- 4. Fișierele din repo-ul proiectului ---
if [ -n "$into" ]; then
  place() { # place <șablon> <cale relativă în repo-ul proiectului>
    local dest="$into/$2"
    if [ -e "$dest" ]; then
      echo "✓ $2 există deja în repo-ul proiectului (neschimbat; compară manual cu infra/templates/$1)"
    else
      mkdir -p "$(dirname "$dest")"
      render "$TEMPLATES/$1" > "$dest"
      echo "+ creat $2 în repo-ul proiectului"
    fi
  }
  place docker-compose.project.yml docker-compose.yml
  place project.env.example        .env.example
  place deploy-project.yml         .github/workflows/deploy.yml
  place frontend.Dockerfile        Dockerfile
  place frontend.nginx.conf        docker/nginx.conf
  place backend.Dockerfile         server/Dockerfile
  place frontend.dockerignore      .dockerignore
  place backend.dockerignore       server/.dockerignore
  if ! grep -qxE '\.env|/\.env|\*\*/\.env' "$into/.gitignore" 2>/dev/null; then
    printf '\n.env\n**/.env\n' >> "$into/.gitignore"
    echo "+ adăugat .env în .gitignore-ul proiectului"
  fi
fi

cat <<EOF

Gata pentru '$name' ($host, repo Oti404/$repo, imagini ghcr.io/oti404/$repo-*).
Urmează pașii din README.md → „Deploy proiect nou”, începând cu pasul 3.
EOF
