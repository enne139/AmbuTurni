# Backend ospedali — AmbuTurni

API REST (Go + PostgreSQL) che espone un elenco condiviso di ospedali
(nome, via, città, regione, coordinate), scaricabile per città o regione
dall'app AmbuTurni (tool "Lista ospedali"), i link ai fogli Google Sheets
del piano turni mensile (sincronizzati automaticamente dal tool "Piano
turni") e il catalogo condiviso dei nomi materiali (tool "Materiali usati"),
tutto gestibile da una pagina admin statica con login.

**Non è un backend di sincronizzazione**: i dati dell'app (turni, persone,
associazioni…) restano solo locali sul device, trasferibili tra dispositivi
col backup JSON di Impostazioni. Questo backend serve solo a condividere
l'anagrafica ospedali tra installazioni/associazioni diverse.

In produzione **non gira da solo**: il binario è incorporato nell'immagine
Docker della versione web (`Dockerfile` alla radice del repo), che lancia
sia nginx (file statici Flutter) sia questo backend, con nginx che fa da
reverse proxy — pass-through, nessun prefisso tolto — su `/api/*`. Il
`Dockerfile`/`docker-compose.yml` di questa cartella servono solo per
sviluppare/testare il backend **da solo**, senza dover compilare tutta la
web app Flutter.

Le rotte API vivono sotto `/api/` **sempre**, anche testando il backend da
solo (senza nginx davanti): il client Flutter (`utils/backend_api.dart`)
chiama sempre `$baseUrl/api/...`, quindi `curl http://localhost:3000/health`
(senza `/api/`) risponde 404 — è normale, usa `/api/health`. Solo
`/admin/` fa eccezione (percorso diretto, non sotto `/api/`).

## Endpoint

| Metodo | Rotta | Auth | Descrizione |
|---|---|---|---|
| GET | `/api/health` | no | stato del servizio |
| POST | `/api/auth/login` | no | `{username,password}` → `{token}` |
| POST | `/api/auth/users` | sì | crea un nuovo utente admin (solo se già loggato) |
| GET | `/api/ospedali?citta=&regione=` | no | elenco ospedali, filtrato per città o regione (città ha priorità se entrambe indicate) |
| POST | `/api/ospedali` | sì | `{nome,via,citta,regione,lat,lng}` → crea un ospedale |
| PUT | `/api/ospedali/:id` | sì | `{nome,via,citta,regione,lat,lng}` → sostituisce tutti i campi |
| POST | `/api/ospedali/import` | sì | `[{nome,via,citta,regione,lat,lng},...]` o `{"ospedali":[...]}` → upsert per nome in blocco |
| DELETE | `/api/ospedali/:id` | sì | elimina un ospedale |
| GET | `/api/citta` | no | città che hanno almeno un ospedale, ordinate alfabeticamente |
| GET | `/api/regioni` | no | regioni che hanno almeno un ospedale, ordinate alfabeticamente |
| GET | `/api/fogli` | no | link ai fogli del piano turni mensile, come `[{chiave,url},...]` (chiave "aaaa-mm") |
| POST | `/api/fogli` | sì | `{chiave,url}` → crea o aggiorna il link di un mese |
| DELETE | `/api/fogli/:chiave` | sì | elimina il link di un mese |
| GET | `/api/materiali` | no | catalogo condiviso dei nomi materiali |
| POST | `/api/materiali` | sì | `{nome}` → crea un materiale |
| PUT | `/api/materiali/:id` | sì | `{nome}` → rinomina un materiale |
| POST | `/api/materiali/import` | sì | `[{nome},...]` o `{"materiali":[...]}` → upsert per nome in blocco |
| DELETE | `/api/materiali/:id` | sì | elimina un materiale |
| GET | `/admin/` | no (poi login nella pagina) | interfaccia web per gestire ospedali, fogli turni e materiali |

Le rotte protette richiedono l'header `Authorization: Bearer <token>`.
`GET /api/ospedali` è pubblica di proposito: è quella che chiama l'app, che
non ha (e non deve avere) credenziali.

## Sviluppo locale con Docker / Podman

```bash
cd backend
cp .env.example .env          # personalizza le credenziali
docker compose up --build     # (oppure: podman-compose up --build)
```

Verifica:

```bash
curl http://localhost:3000/api/health                        # {"status":"ok"}
curl -X POST http://localhost:3000/api/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"..."}'
```

Apri `http://localhost:3000/admin/` per la pagina di gestione ospedali,
fogli turni e materiali. L'utente admin viene creato al primo avvio da
`ADMIN_USERNAME`/`ADMIN_PASSWORD`. Nell'app Flutter, l'indirizzo del server
da configurare (Impostazioni → Backend condiviso) è la base senza `/api/`,
es. `http://localhost:3000` o `http://<IP-del-PC>:3000` da telefono: è
l'app ad aggiungere `/api/` da sola.

## Sviluppo locale senza Docker

Richiede Go ≥ 1.22 e un PostgreSQL raggiungibile.

```bash
go run . # legge le variabili d'ambiente sotto
```

Variabili principali (vedi `.env.example` per l'elenco completo):
`DATABASE_URL`, `JWT_SECRET`, `ADMIN_USERNAME`, `ADMIN_PASSWORD`, `PORT`.

## Build dell'immagine

Questo backend **non ha più una sua immagine pubblicata separatamente**: è
compilato ed eseguito dentro l'immagine web (vedi `.github/workflows/build-web.yml`
e il `Dockerfile` alla radice). `backend/Dockerfile` in questa cartella serve
solo per lo sviluppo locale via `docker compose` sopra.

## Sicurezza

- Cambia **sempre** `JWT_SECRET`, `ADMIN_PASSWORD` e `POSTGRES_PASSWORD`.
- `GET /api/ospedali` è volutamente pubblica (nessun dato sensibile): non
  richiede autenticazione né in sviluppo né in produzione.
- Aggiungi altri utenti admin con `POST /api/auth/users` (da loggato).
