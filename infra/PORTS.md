# Evidența proiectelor și a porturilor

Porturile sunt **doar pentru debug local**: dacă un serviciu trebuie expus temporar, se publică
pe `127.0.0.1` (ex. `127.0.0.1:10001:3000`), niciodată pe `0.0.0.0`. În producție proiectele
nu publică porturi; Caddy ajunge la ele prin rețeaua `caddy_default`.

Porturi publice pe server: doar 22, 80 și 443.

Rândurile noi se adaugă cu `scripts/new-project.sh`.

| Proiect | Interval porturi | Subdomeniu | Folder pe server | Imagine |
| --- | --- | --- | --- | --- |
| carworld | 10000-10099 | carworld.otnielcodes.com | ~/proiecte/carworld | ghcr.io/oti404/carworld-* |
| landing | 10100-10199 | otnielcodes.com, www.otnielcodes.com | ~/proiecte/landing | ghcr.io/oti404/otnielcodes-landing |
