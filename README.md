# otnielcodes.com

Repo-ul are două roluri:

1. **Landing-ul** de pe `otnielcodes.com`: un catalog de proiecte în Angular 21, servit de nginx non-root.
2. **Infrastructura serverului**, o VM Azure cu Ubuntu, 1 GiB RAM + swap și Docker. Aici stau configurația Caddy (un fișier per site), evidența porturilor, șabloanele pentru proiecte noi și scripturile de backup.

```
Internet ─► :80/:443 Caddy (~/proiecte/caddy) ─► rețeaua caddy_default
                                                 ├─ landing-frontend:8080     (~/proiecte/landing)
                                                 ├─ carworld-frontend:80      (~/proiecte/carworld)
                                                 └─ carworld-backend:3000 ─► db (rețea internă)
```

Pe server rulează doar `docker compose pull` + `up -d`. Imaginile se construiesc în GitHub Actions și se publică în `ghcr.io/oti404/*`. Nu se clonează repo-uri pe server.

## Structură

| Cale | Rol |
| --- | --- |
| `src/`, `public/`, `nginx/`, `Dockerfile` | Landing-ul Angular și imaginea lui |
| `src/assets/projects.json` | Cardurile de pe landing |
| `docker-compose.yml` | Compose-ul landing-ului; deploy-ul îl copiază în `~/proiecte/landing/` |
| `infra/caddy/docker-compose.yml` | Compose-ul Caddy (conf montat ca **director**) |
| `infra/caddy/conf/Caddyfile` | Doar opțiunile globale + `import /etc/caddy/sites/*.caddy` |
| `infra/caddy/conf/sites/*.caddy` | Un fișier per site |
| `infra/caddy/apply-conf.sh` | Validare + aplicare + reload pe server (rulat de workflow) |
| `infra/PORTS.md` | Evidența proiectelor, porturilor, subdomeniilor, folderelor |
| `infra/templates/` | Șabloane pentru repo-urile proiectelor noi (compose, `.env.example`, workflow, Dockerfile-uri, `.dockerignore`, nginx); `new-project.sh --into` le copiază completate |
| `infra/scripts/backup.sh`, `restore.sh` | Backup Postgres + uploads și restaurare |
| `scripts/new-project.sh` | Înregistrează un proiect nou aici și, cu `--into`, generează fișierele în repo-ul lui |
| `.github/workflows/deploy.yml` | Build + deploy landing, deploy Caddy, sincronizare scripturi |
| `.github/workflows/status.yml` | La 30 de minute verifică `liveUrl`-urile și publică `status.json` |

## Convenții

- Fiecare proiect are două nume. `<repo>` e numele repo-ului GitHub și al imaginilor (`ghcr.io/oti404/<repo>-frontend` / `-backend`). `<nume>` e numele scurt, folosit pentru folderul `~/proiecte/<nume>/`, alias-uri, volume și fișierul `.caddy`. La car-world: `car-world` / `carworld`.
- Pe server, `~/proiecte/<nume>/` conține doar `docker-compose.yml`, adus de deploy, și `.env` (chmod 600). Workflow-ul proiectului face `cd` **exact** în acest folder.
- Subdomeniul este `<nume>.otnielcodes.com`. DNS-ul are wildcard `*.otnielcodes.com`, deci nu trebuie atins.
- Porturile publice sunt doar 22, 80 și 443. Proiectele nu publică porturi. Frontend-ul și backend-ul intră pe `caddy_default` cu alias-uri unice: `<nume>-frontend` și `<nume>-backend`. Baza de date stă doar pe rețeaua internă a proiectului.
- Intervalele de porturi din `infra/PORTS.md` servesc doar la debug local, cu bind pe `127.0.0.1`.
- Fiecare serviciu are `mem_limit` și healthcheck pe `127.0.0.1`, nu pe `localhost`.
- Imaginile au versiuni fixate (ex. `nginxinc/nginx-unprivileged:1.30.6-alpine3.24`).

## Rulare locală (landing)

```bash
npm ci
npm start                 # http://localhost:4200
npm run build             # dist/otnielcodes-landing/browser

docker build -t otnielcodes-landing:local .
docker run --rm --read-only --tmpfs /tmp -p 8080:8080 otnielcodes-landing:local
```

## Cum funcționează deploy-ul

La push pe `main`, `.github/workflows/deploy.yml` rulează doar job-urile afectate de modificări:

| Job | Când rulează | Ce face |
| --- | --- | --- |
| `build` → `deploy-landing` | `src/`, `nginx/`, `Dockerfile`, `package*.json`, `docker-compose.yml` etc. | Construiește imaginea (`:<sha>` și `:latest`, cache GHA, `linux/amd64`). Copiază `docker-compose.yml` în `~/proiecte/landing/`, apoi rulează `TAG=<sha> docker compose pull && up -d --wait` și `docker image prune -f` |
| `deploy-caddy` | `infra/caddy/**` | Urcă `infra/caddy/conf/` în `~/proiecte/caddy/conf.next/` și rulează `apply-conf.sh` |
| `sync-scripts` | `infra/scripts/**` | Copiază scripturile în `~/proiecte/scripts/` |

Cu *Run workflow* (manual) rulează toate job-urile. `concurrency` asigură că două deploy-uri nu ajung niciodată pe server în același timp.

### Ce face `apply-conf.sh`

1. **Se oprește cu un mesaj clar** dacă Caddy nu are `~/proiecte/caddy/conf` montat ca director pe `/etc/caddy`, adică înainte de migrare. În cazul ăsta nu se modifică nimic.
2. Construiește configurația candidat într-un director temporar, pornind de la `conf/` de pe server:
   - `sites/` se sincronizează cu `--delete`: un site șters din repo dispare și de pe server;
   - `Caddyfile` se înlocuiește cu cel din repo. Dacă cel de pe server era diferit, apar un `::warning::` cu diff-ul și o copie de siguranță;
   - alte fișiere din `conf/` nu sunt atinse.
3. Rulează `caddy validate` într-un container temporar, pe **aceeași imagine** ca a Caddy-ului care rulează. Dacă validarea pică, se oprește și site-urile live nu sunt afectate.
4. Copiază configurația în `conf/` și face `caddy reload`. Dacă reload-ul pică, pune la loc versiunea anterioară și reîncarcă din nou.

Copiile anterioare stau în `~/proiecte/caddy/conf.backups/<data>/` (se păstrează ultimele 10).

## Rollback

**Landing sau orice proiect**, pe server:

```bash
cd ~/proiecte/landing            # sau ~/proiecte/<nume>
TAG=<sha-vechi> docker compose up -d
```

SHA-urile le găsești în istoricul Git sau în GHCR → *Packages*. Următorul push pe `main` face din nou deploy cu ultimul commit, deci pentru un rollback permanent folosește `git revert` + push.

**Caddy**: fie faci `git revert` + push, fie, pe server:

```bash
cp -a ~/proiecte/caddy/conf.backups/<data>/. ~/proiecte/caddy/conf/
docker exec caddy-caddy-1 caddy reload --config /etc/caddy/Caddyfile --adapter caddyfile
```

## Deploy proiect nou: pas cu pas

Rețeta e cea din car-world, care e proiectul de referință. Urmează pașii în ordine. Fiecare pas spune unde se execută: 💻 calculatorul tău, 🌐 GitHub, 🖥️ server.

### 0. Valorile proiectului

Le alegi o dată și le folosești peste tot. Exemplu complet:

| Valoare | Exemplu | Unde apare |
| --- | --- | --- |
| `<repo>` | `notes-app` | repo-ul `Oti404/<repo>` și imaginile `ghcr.io/oti404/<repo>-frontend` / `-backend`. Doar litere mici, cifre, `.`, `_`, `-` |
| `<nume>` | `notes` | folderul `~/proiecte/<nume>`, alias-urile `<nume>-frontend` / `<nume>-backend`, volumele `<nume>_db-data` / `<nume>_uploads`, `infra/caddy/conf/sites/<nume>.caddy` |
| `<subdomeniu>` | `notes` | `https://<subdomeniu>.otnielcodes.com` (DNS-ul wildcard există deja) |
| `<port-start>` | `10200` | intervalul `<port-start>`–`<port-start+99>` din `infra/PORTS.md`: următorul multiplu de 100 liber |

La car-world: `<repo>` = `car-world`, `<nume>` = `carworld`, `<subdomeniu>` = `carworld`, `<port-start>` = `10000`.

### 1. 🖥️ Verifici că ai memorie

```bash
free -h                       # coloana "available"
docker stats --no-stream      # cât consumă proiectele existente
```

Un proiect nou din șablon consumă ~60–100 MiB în repaus, iar limitele lui (`mem_limit`) însumează 416 MiB. Dacă `available` e sub ~250 MiB, nu face deploy. Mai întâi micșorezi limitele altor proiecte sau mărești VM-ul.

### 2. 💻 Structura cerută repo-ului proiectului

Șabloanele presupun structura de la car-world:

- **frontend Angular în rădăcina repo-ului** (`package.json`, `angular.json`, `src/`). Este servit de nginx non-root pe portul **8080**;
- **backend Node în `server/`**, cu `server/package.json`, `server/package-lock.json` și `server/index.js`, care:
  - ascultă pe `process.env.PORT` (3000);
  - răspunde la `GET /api/health` cu 200 doar când merge și conexiunea la DB (pentru healthcheck);
  - citește baza din `process.env.DATABASE_URL`;
  - scrie fișierele urcate în `/app/uploads`, care e volumul `<nume>_uploads`, inclus automat în backup;
- toate rutele API sunt sub `/api/*`, iar fișierele urcate sunt servite sub `/uploads/*`. Restul URL-urilor merg la frontend.

Dacă proiectul nu are backend sau DB, scoți serviciile respective din compose și blocurile `handle /api/*` și `handle /uploads/*` din `.caddy`.

### 3. 🌐 + 💻 Repo-ul proiectului

1. Creezi `Oti404/<repo>` pe GitHub, **public**, și îl clonezi lângă acest repo: `D:\GitHub\<repo>`.
2. Din `D:\GitHub\otnielcodes.com` rulezi:
   ```bash
   scripts/new-project.sh <nume> <subdomeniu> <port-start> <repo> --into ../<repo>
   # ex: scripts/new-project.sh notes notes 10200 notes-app --into ../notes-app
   ```
   **În acest repo**, scriptul creează `infra/caddy/conf/sites/<nume>.caddy`, rândul din `infra/PORTS.md` și intrarea `"status": "wip"` din `src/assets/projects.json`.

   **În repo-ul proiectului** creează, cu toate numele completate:
   - `docker-compose.yml`
   - `.env.example`
   - `.github/workflows/deploy.yml`
   - `Dockerfile` și `.dockerignore`
   - `docker/nginx.conf`
   - `server/Dockerfile` și `server/.dockerignore`

   Pe lângă ele, adaugă `.env` în `.gitignore`. Fișierele care există deja nu sunt atinse, iar scriptul îți spune pe care trebuie să le compari manual.
3. Ajustezi ce ține de proiect:
   - variabilele de mediu ale backend-ului: secțiunea `backend.environment` din compose și `.env.example`;
   - Prisma: decomentezi liniile din `server/Dockerfile`;
   - dacă backend-ul are nevoie de alt timp de pornire: `start_period`.
4. **Test local**, în repo-ul proiectului (Docker Desktop):
   ```bash
   docker network create caddy_default            # o singură dată pe calculator
   cp .env.example .env                           # completează valori de test
   docker build -t ghcr.io/oti404/<repo>-frontend:local .
   docker build -t ghcr.io/oti404/<repo>-backend:local ./server
   TAG=local docker compose up -d --wait          # toate trebuie să ajungă "healthy"
   docker compose ps
   docker compose down                            # adaugă -v ca să ștergi și datele de test
   ```
   Dacă `up --wait` pică, `docker compose logs <serviciu>` îți arată de ce. Repari, apoi abia după aceea treci la pasul următor.

### 4. 🌐 Secretele în repo-ul proiectului

*Settings → Secrets and variables → Actions → New repository secret*. Pui aceleași 4 valori ca la otnielcodes.com (detalii în secțiunea [Secrete GitHub](#secrete-github)):

| Secret | Valoare |
| --- | --- |
| `SSH_HOST` | IP-ul sau hostname-ul VM-ului |
| `SSH_USER` | utilizatorul de deploy |
| `SSH_KEY` | cheia privată de deploy |
| `SSH_KNOWN_HOSTS` | linia `ssh-keyscan` verificată |

GitHub nu-ți mai arată valoarea unui secret după ce l-ai salvat, așa că păstrează cele 4 valori într-un manager de parole. Altfel trebuie să generezi o cheie nouă pentru fiecare proiect nou.

### 5. 🖥️ Folderul și `.env` pe server

```bash
mkdir -p ~/proiecte/<nume> && cd ~/proiecte/<nume>
umask 077
cat > .env <<ENV
POSTGRES_USER=<nume>
POSTGRES_PASSWORD=$(openssl rand -hex 32)
POSTGRES_DB=<nume>
JWT_SECRET=$(openssl rand -hex 32)
ENV
chmod 600 .env
# adaugă aici orice altă variabilă din .env.example-ul proiectului (nano .env)
ls -la .env                    # -rw-------
```

Pe server **nu** clonezi repo-ul și nu copiezi compose-ul. Deploy-ul aduce singur `docker-compose.yml`, iar fără `.env` se oprește cu o eroare clară.

### 6. 💻 Primul deploy al proiectului

```bash
cd D:\GitHub\<repo>
git add -A && git commit -m "Add Docker deploy" && git push origin main
```

În *Actions* rulează `Build & deploy`:
- `build` publică `ghcr.io/oti404/<repo>-frontend` și `-backend`, cu tag-urile `<sha>` și `latest`;
- `deploy` copiază compose-ul și rulează `pull` + `up -d --wait`.

**La primul deploy, job-ul `deploy` pică la `docker compose pull`.** E normal: GHCR creează pachetele noi ca private. Le faci publice:
1. *github.com/Oti404?tab=packages* → `<repo>-frontend` → *Package settings* → *Change visibility* → *Public*;
2. repeți pentru `<repo>-backend`;
3. în *Actions*, pe rularea care a picat, dai *Re-run failed jobs*.

### 7. 💻 Caddy și landing-ul

În `src/assets/projects.json` completezi `description` (o propoziție), `technologies` și `"status": "live"`. Apoi:

```bash
cd D:\GitHub\otnielcodes.com
git add -A && git commit -m "Add <nume>" && git push
```

Job-ul `deploy-caddy` validează configurația și reîncarcă Caddy, iar certificatul TLS pentru subdomeniu se emite automat la primul acces. Job-urile `build` și `deploy-landing` actualizează cardul de pe `otnielcodes.com`.

### 8. 🖥️ + 💻 Verificare

```bash
# 🖥️ server
cd ~/proiecte/<nume> && docker compose ps          # frontend, backend, db: "healthy"
docker network inspect caddy_default --format '{{range .Containers}}{{.Name}} {{end}}'
free -h && docker stats --no-stream                # memoria după deploy

# 💻 oriunde
curl -sI https://<subdomeniu>.otnielcodes.com | head -1               # HTTP/2 200
curl -s  https://<subdomeniu>.otnielcodes.com/api/health              # {"status":"ok",...}
```

Dacă primești 502, folosești [checklist-ul 502](#diagnoză-502-caddy-nu-ajunge-la-proiect).

### 9. 🖥️ Backup

Nu trebuie configurat nimic. `backup.sh` găsește singur serviciul `db` și volumul `<nume>_uploads`. A doua zi verifici:

```bash
ls -la ~/backups/<nume>/
tail -20 ~/backups/backup.log
```

Dacă nu vrei să aștepți, rulezi `~/proiecte/scripts/backup.sh` imediat.

### Rezumat (pentru data viitoare)

| # | Unde | Ce |
| --- | --- | --- |
| 1 | 🖥️ | `free -h` → peste ~250 MiB available |
| 2 | 💻 | repo-ul are frontend în rădăcină, backend în `server/` cu `/api/health` |
| 3 | 🌐💻 | creezi repo-ul, apoi `scripts/new-project.sh <nume> <sub> <port> <repo> --into ../<repo>` și test local cu `up --wait` |
| 4 | 🌐 | cele 4 secrete în repo-ul proiectului |
| 5 | 🖥️ | `mkdir ~/proiecte/<nume>` și `.env` (chmod 600) |
| 6 | 💻🌐 | push în proiect → faci pachetele GHCR publice → *Re-run failed jobs* |
| 7 | 💻 | completezi `projects.json` → push în otnielcodes.com |
| 8 | 🖥️💻 | `docker compose ps`, `curl` pe subdomeniu și pe `/api/health` |
| 9 | 🖥️ | a doua zi: `ls ~/backups/<nume>/` |

### Ce NU faci

- nu publici porturi pe `0.0.0.0` și nu deschizi alte porturi în firewall/NSG;
- nu clonezi repo-uri și nu faci build pe server;
- nu refolosești un alias (`<nume>-frontend`) sau un interval de porturi deja folosit;
- nu editezi manual fișierele din `~/proiecte/caddy/conf/`, pentru că următorul deploy le suprascrie. Modifici în repo;
- nu pui `.env` sau parole în Git.

### `projects.json`

Câmpuri: `name`, `description`, `technologies`, `liveUrl`, `repoUrl`, `image` (opțional) și `status` (opțional: `live` | `beta` | `wip` | `archived`; dacă lipsește înseamnă `live`). Imaginile se pun în `src/assets/projects/`, la 16:9.

### Starea live de pe landing

`.github/workflows/status.yml` rulează la fiecare 30 de minute. Face GET pe fiecare `liveUrl` și publică `status.json` pe branch-ul `status`, cu un singur commit suprascris de fiecare dată. Landing-ul citește fișierul de pe `raw.githubusercontent.com` și afișează „Online” sau „Indisponibil”. Dacă fișierul lipsește, nu se afișează nimic. Pe server nu rulează niciun serviciu în plus. GitHub oprește workflow-urile programate după 60 de zile fără commit-uri în repo; le repornești din tab-ul *Actions*.

## Secrete GitHub

*Settings → Secrets and variables → Actions*. Se pun în acest repo și în fiecare repo de proiect. Alternativ, le poți pune o singură dată ca secrete de organizație.

| Secret | Valoare |
| --- | --- |
| `SSH_HOST` | IP-ul sau hostname-ul VM-ului |
| `SSH_USER` | utilizatorul de deploy (în grupul `docker`) |
| `SSH_KEY` | cheia privată de deploy (tot fișierul, cu `BEGIN`/`END`) |
| `SSH_KNOWN_HOSTS` | **obligatoriu**: linia de host key a serverului (vezi mai jos) |

### Cheia SSH de deploy

Pe calculatorul tău:

```bash
ssh-keygen -t ed25519 -C "github-actions-deploy" -f ./deploy_key -N ""
```

Pe server, adaugi în `~/.ssh/authorized_keys` al utilizatorului de deploy o linie cu prefixul `restrict`, fără `command=`, pentru ca rsync să funcționeze:

```
restrict ssh-ed25519 AAAA...cheia-publica... github-actions-deploy
```

`restrict` dezactivează port forwarding, agent forwarding, X11 și PTY. Comenzile, `rsync` și `ssh 'bash -s'` merg în continuare.

`SSH_KNOWN_HOSTS`: rulezi pe calculatorul tău `ssh-keyscan -t ed25519 <SSH_HOST>` și **verifici** fingerprint-ul. Compari `ssh-keyscan -t ed25519 <SSH_HOST> | ssh-keygen -lf -` cu ce dă pe server `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`. Linia de la `ssh-keyscan` o pui în secret. Fără ea, workflow-ul refuză să se conecteze.

La final ștergi `deploy_key` și `deploy_key.pub` de pe calculator.

### GHCR pe server

Varianta recomandată e să faci pachetele publice (*github.com/Oti404?tab=packages* → *Package settings* → *Public*). Dacă rămân private, autentifici serverul cu un PAT classic care are **doar** `read:packages`:

```bash
echo '<TOKEN>' | docker login ghcr.io -u Oti404 --password-stdin
```

## Diagnoză 502 (Caddy nu ajunge la proiect)

```bash
# 1. Alias-ul există pe caddy_default?
docker network inspect caddy_default \
  --format '{{range .Containers}}{{.Name}} {{.IPv4Address}}{{println}}{{end}}'
docker inspect <container> --format '{{json .NetworkSettings.Networks.caddy_default.Aliases}}'

# 2. Containerul rulează și e healthy?
cd ~/proiecte/<nume> && docker compose ps
docker compose logs --tail 50 <serviciu>

# 3. Portul din .caddy este portul INTERN pe care ascultă containerul?
docker exec caddy-caddy-1 wget -qO- -T 3 http://<nume>-frontend:<port>/ | head -c 200

# 4. Caddy vede configurația și ce spune?
docker exec caddy-caddy-1 caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
docker logs --tail 50 caddy-caddy-1
```

Cauze frecvente:
- compose-ul proiectului nu are rețeaua externă `caddy_default`, iar 502 reapare la fiecare deploy;
- alias-ul e greșit sau e folosit de două proiecte;
- în `.caddy` e trecut portul din `PORTS.md` în loc de portul intern;
- containerul e `unhealthy` sau intră în restart din lipsă de memorie (`docker inspect <c> --format '{{.State.OOMKilled}}'`).

## Backup și restaurare

`infra/scripts/backup.sh` ajunge pe server în `~/proiecte/scripts/`, adus de job-ul `sync-scripts`. Pentru fiecare proiect din `~/proiecte/*/`:

- dacă există serviciul compose `db`, rulează `pg_dump -Fc` **în** containerul db, cu `POSTGRES_USER` și `POSTGRES_DB` din mediul lui, deci fără parole în script;
- dacă există volumul `<nume>_uploads` (ex. `carworld_uploads`), îl arhivează cu `tar.gz`;
- scrie în `~/backups/<nume>/<YYYYmmdd-HHMMSS>/`, cu `SHA256SUMS`, permisiuni `700` și scriere atomică;
- păstrează backup-urile 7 zile.

Cron, cu `crontab -e` pe server:

```cron
15 3 * * * $HOME/proiecte/scripts/backup.sh >> $HOME/backups/backup.log 2>&1
```

Test manual: `~/proiecte/scripts/backup.sh && ls -la ~/backups/carworld/`.

**Restaurare:**

```bash
~/proiecte/scripts/restore.sh carworld ~/backups/carworld/<YYYYmmdd-HHMMSS>            # tot
~/proiecte/scripts/restore.sh carworld ~/backups/carworld/<YYYYmmdd-HHMMSS> --db       # doar baza
~/proiecte/scripts/restore.sh carworld ~/backups/carworld/<YYYYmmdd-HHMMSS> --uploads  # doar fișierele
```

Scriptul:
1. verifică sumele de control;
2. cere să scrii numele proiectului ca confirmare;
3. oprește serviciile în afară de `db`;
4. restaurează baza într-o bază temporară și o înlocuiește pe cea veche **doar dacă** `pg_restore` reușește (un dump stricat nu lasă proiectul fără date);
5. golește și reface volumul de uploads;
6. pornește serviciile la loc.

Fluxul a fost testat local, pe `postgres:16.10-alpine`: backup → modificare date → restaurare → verificare, plus dump corupt și retenție.

> Backup-urile stau pe aceeași VM. Dacă se pierde VM-ul, se pierd și ele. Pasul următor e o copie zilnică în afara serverului (de ex. Azure Blob Storage sau `rclone`).

## Migrare Caddy la `conf/` (o singură dată)

Până la migrare, `deploy-caddy` se oprește cu mesajul „Caddy NU are … montat ca director” și nu modifică nimic.

De ce: un `Caddyfile` montat ca fișier singur rămâne „vechi” în container după ce un script îl înlocuiește, pentru că fișierul nou are alt inode. Un director montat arată mereu conținutul curent.

Pașii 1–3 nu afectează site-urile. Downtime-ul (câteva secunde) apare doar la pasul 4.

```bash
# 1. Copie de siguranță
cd ~/proiecte/caddy
STAMP=$(date +%Y%m%d-%H%M%S)
cp -a docker-compose.yml docker-compose.yml.pre-conf-$STAMP
cp -a Caddyfile Caddyfile.pre-conf-$STAMP

# 2. Noua configurație, direct din GitHub (repo public)
RAW=https://raw.githubusercontent.com/Oti404/otnielcodes.com/main/infra/caddy
mkdir -p conf/sites
curl -fsSL $RAW/conf/Caddyfile               -o conf/Caddyfile
curl -fsSL $RAW/conf/sites/landing.caddy     -o conf/sites/landing.caddy
curl -fsSL $RAW/conf/sites/carworld.caddy    -o conf/sites/carworld.caddy
curl -fsSL $RAW/docker-compose.yml           -o docker-compose.yml.new

# 3. Verificare: noua configurație e validă și echivalentă cu cea veche
IMG=caddy:2.11.7-alpine                          # imaginea fixată din noul compose (caddy:2 = v2.11.7 acum)
docker run --rm --network none -v "$PWD/conf:/etc/caddy:ro" $IMG \
  caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
docker run --rm --network none -v "$PWD/Caddyfile:/etc/caddy/Caddyfile:ro" $IMG \
  caddy adapt --config /etc/caddy/Caddyfile > /tmp/caddy-old.json
docker run --rm --network none -v "$PWD/conf:/etc/caddy:ro" $IMG \
  caddy adapt --config /etc/caddy/Caddyfile > /tmp/caddy-new.json
diff <(python3 -m json.tool --sort-keys /tmp/caddy-old.json) \
     <(python3 -m json.tool --sort-keys /tmp/caddy-new.json) && echo "IDENTIC"
# Singura diferență așteptată: blocul test.otnielcodes.com ("Merge! Server live."), scos intenționat.
# Orice altă diferență = STOP, nu continua cu pasul 4.
diff docker-compose.yml docker-compose.yml.new
# Așteptat: imagine caddy:2.11.7-alpine, ./conf:/etc/caddy:ro în loc de ./Caddyfile, fără ./site,
# volum nou caddy_config, healthcheck și capabilități reduse. caddy_data rămâne (certificatele).

# 4. Comutarea (downtime: câteva secunde)
mv docker-compose.yml.new docker-compose.yml
docker compose up -d
docker compose ps                                # caddy: healthy
docker inspect caddy-caddy-1 -f '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{println}}{{end}}'

# 5. Verificare
curl -sI https://otnielcodes.com | head -1
curl -sI https://carworld.otnielcodes.com | head -1
curl -s  https://carworld.otnielcodes.com/api/health      # {"status":"ok","db":"connected"}
docker logs --tail 30 caddy-caddy-1
```

Rollback la migrare: `cp docker-compose.yml.pre-conf-<STAMP> docker-compose.yml && docker compose up -d`.

După migrare: în GitHub → *Actions* → ultima rulare *Build & deploy* → *Re-run jobs*. Job-ul `deploy-caddy` trebuie să treacă și să raporteze că nu sunt diferențe în `sites/`. Fișierul vechi `~/proiecte/caddy/Caddyfile` poate rămâne ca arhivă, pentru că nu mai e montat.
