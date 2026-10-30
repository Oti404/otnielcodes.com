# otnielcodes.com

Pagina de pornire a domeniului **otnielcodes.com**: un catalog al proiectelor găzduite pe subdomenii.
Angular 21 (standalone, fără routing), servit de nginx non-root într-un container Docker,
pe un server Ubuntu, în spatele lui Caddy.

```
push pe main ─► GitHub Actions ─► ghcr.io/oti404/otnielcodes-landing:<sha> + :latest
                                   └─► SSH pe server ─► docker compose pull && up -d
Internet ─► Caddy (TLS) ─► rețeaua caddy_default ─► landing-frontend:8080 (nginx)
```

## Structură

| Cale | Rol |
| --- | --- |
| `src/assets/projects.json` | Lista de proiecte (singura sursă pentru carduri) |
| `src/app/` | Aplicația: `app.*` (hero, secțiune proiecte, footer), `components/`, `services/` |
| `src/styles.scss` | Variabile CSS (temele light/dark), butoane, focus, utilitare |
| `Dockerfile` | Build multi-stage: `node:22-alpine` → `nginxinc/nginx-unprivileged:alpine` |
| `nginx/` | Configurația nginx (gzip, cache, headere de securitate, fallback SPA) |
| `docker-compose.yml` | Copiat pe server în `~/proiecte/landing/` |
| `.github/workflows/deploy.yml` | Build, push în GHCR, deploy prin SSH |
| `deploy/Caddyfile.landing` | Blocul de adăugat în Caddyfile |

## Rulare locală

Necesită Node.js `^20.19`, `^22.12` sau `>=24`.

```bash
npm ci
npm start                 # http://localhost:4200
npm run build             # rezultat în dist/otnielcodes-landing/browser
```

Testarea imaginii de producție:

```bash
docker build -t otnielcodes-landing:local .
docker run --rm --read-only --tmpfs /tmp -p 8080:8080 otnielcodes-landing:local
# http://localhost:8080
```

## Adăugarea unui proiect

Adaugă un obiect în `src/assets/projects.json`, apoi fă push pe `main`:

```json
{
  "name": "nume-proiect",
  "description": "O singură propoziție despre ce face proiectul.",
  "technologies": ["Angular", "Node.js"],
  "liveUrl": "https://nume.otnielcodes.com",
  "repoUrl": "https://github.com/Oti404/nume-proiect",
  "image": "assets/projects/nume-proiect.webp"
}
```

- `liveUrl`, `repoUrl` și `image` sunt opționale (`null` sau lipsă = butonul/imaginea nu apare).
- Imaginile se pun în `src/assets/projects/`, ideal `.webp`, raport 16:9 (de ex. 1280×720).
- Ordinea din JSON este ordinea de afișare.
- `projects.json` e servit cu `Cache-Control: no-cache`, deci modificările apar imediat după deploy.

## Cum funcționează deploy-ul

La fiecare push pe `main` (sau manual, din tab-ul *Actions* → *Run workflow*):

1. **build**: construiește imaginea pentru `linux/amd64` (cu cache GitHub Actions) și o publică
   în GHCR cu două tag-uri: SHA-ul commit-ului și `latest`.
2. **deploy**: se conectează prin SSH pe server și rulează:
   ```bash
   cd ~/proiecte/landing
   TAG=<sha> docker compose pull
   TAG=<sha> docker compose up -d
   docker image prune -f
   ```

Containerul nu publică porturi; Caddy ajunge la el prin rețeaua `caddy_default`, alias `landing-frontend`.
Containerul rulează non-root, cu sistem de fișiere read-only și limită de 64 MB RAM.

## Rollback

Pe server, cu SHA-ul unui commit vechi (îl găsești în istoricul Git sau în GHCR → *Packages*):

```bash
cd ~/proiecte/landing
TAG=<sha-vechi> docker compose up -d
```

Imaginea se descarcă automat din GHCR dacă nu mai e locală. Atenție: următorul push pe `main`
face din nou deploy cu ultimul commit. Pentru un rollback permanent, fă `git revert` și push.

`docker image prune -f` șterge doar imaginile fără tag, deci imaginile vechi rămân pe disc.
Pentru curățenie ocazională: `docker image prune -a -f --filter "until=720h"`.

## Configurare manuală (o singură dată)

### 1. Cheia SSH de deploy

Pe calculatorul tău (nu pe server):

```bash
ssh-keygen -t ed25519 -C "github-actions-deploy" -f ./deploy_key -N ""
```

Pe server, pentru utilizatorul de deploy (care trebuie să fie în grupul `docker`):

```bash
mkdir -p ~/.ssh && chmod 700 ~/.ssh
cat deploy_key.pub >> ~/.ssh/authorized_keys   # conținutul cheii publice
chmod 600 ~/.ssh/authorized_keys
```

Apoi șterge `deploy_key` și `deploy_key.pub` de pe calculator după ce ai pus cheia privată în GitHub.

### 2. GitHub Secrets

Repo → *Settings* → *Secrets and variables* → *Actions* → *New repository secret*:

| Secret | Valoare |
| --- | --- |
| `SSH_HOST` | IP-ul sau hostname-ul serverului |
| `SSH_USER` | utilizatorul de deploy |
| `SSH_KEY` | conținutul complet al `deploy_key` (cheia privată, cu liniile `BEGIN`/`END`) |

Dacă SSH ascultă pe alt port decât 22, adaugă `port: ${{ secrets.SSH_PORT }}` în `deploy.yml` și secretul `SSH_PORT`.

### 3. Acces la imaginea din GHCR

După primul build, pachetul apare la *github.com/Oti404?tab=packages*. Alege una dintre variante:

- **Pachet public** (recomandat, codul e oricum public): *Package settings* → *Change visibility* → *Public*.
  Serverul face `pull` fără autentificare.
- **Pachet privat**: creează un *Personal access token (classic)* doar cu `read:packages`, apoi pe server:
  ```bash
  echo '<TOKEN>' | docker login ghcr.io -u Oti404 --password-stdin
  ```

### 4. Serverul

```bash
mkdir -p ~/proiecte/landing
# copiază docker-compose.yml din acest repo în ~/proiecte/landing/
docker network inspect caddy_default >/dev/null   # rețeaua trebuie să existe deja
```

### 5. Caddy

Adaugă în Caddyfile blocul din `deploy/Caddyfile.landing`:

```caddyfile
otnielcodes.com, www.otnielcodes.com {
	encode gzip zstd
	reverse_proxy landing-frontend:8080
}
```

Apoi reîncarcă Caddy (de ex. `docker exec <container-caddy> caddy reload --config /etc/caddy/Caddyfile`).
DNS-ul trebuie să aibă înregistrări A/AAAA pentru `otnielcodes.com` și `www.otnielcodes.com` spre server.
