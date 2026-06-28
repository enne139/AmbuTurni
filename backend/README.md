# Backend di sincronizzazione — Ambulanza Turni

API REST (Node.js + Express + PostgreSQL) per sincronizzare i dati dell'app tra più
dispositivi, con **login** (JWT) per non rendere i dati pubblici.

## Come funziona

- I dati restano **locali** su ogni dispositivo (SQLite). La sync è opzionale.
- Ogni riga modificata localmente (`is_synced = 0`) viene inviata col **push**.
- Il **pull** scarica le modifiche fatte dagli altri dispositivi dopo l'ultima sync.
- I conflitti si risolvono **last-write-wins** in base a `updated_at` del client.
- Il server salva tutto in una tabella generica `records (table_name, id, data JSONB, …)`,
  quindi non va modificato se cambia lo schema dell'app.

## Endpoint

| Metodo | Rotta | Auth | Descrizione |
|---|---|---|---|
| GET | `/health` | no | stato del servizio |
| POST | `/auth/login` | no | `{username,password}` → `{token}` |
| POST | `/auth/users` | sì | crea un nuovo utente (solo se già loggato) |
| POST | `/sync/push` | sì | `{changes:[{table,id,data,updated_at,deleted}]}` |
| GET | `/sync/pull?since=ISO` | sì | `{records:[…], serverTime}` |

Le rotte protette richiedono l'header `Authorization: Bearer <token>`.

## Avvio con Docker / Podman

```bash
cd backend
cp .env.example .env          # personalizza credenziali e SYNC_IMAGE
podman-compose up -d          # oppure: docker compose up -d
```

Verifica:

```bash
curl http://localhost:3000/health           # {"status":"ok"}
curl -X POST http://localhost:3000/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"...";}'
```

L'utente admin viene creato al primo avvio da `ADMIN_USERNAME` / `ADMIN_PASSWORD`.

## Sviluppo locale (senza Docker)

```bash
npm install
DATABASE_URL=postgres://ambulanza:pw@localhost:5432/ambulanza \
JWT_SECRET=dev ADMIN_USERNAME=admin ADMIN_PASSWORD=admin \
npm run dev
```

## Build dell'immagine

L'immagine viene creata dalla action `.gitea/workflows/build-backend.yml` (Buildah) a ogni
push su `backend/**` e pubblicata sul **Container Registry dello stesso Gitea**. Il runner
deve avere `buildah` (o poterlo installare). Tag prodotto:

```
<REGISTRY_HOST>/<owner>/ambulanza-sync:<sha>   (+ :latest)
```

Secrets da impostare nel repo (Settings → Actions → Secrets):

| Secret | Esempio | Note |
|---|---|---|
| `REGISTRY_HOST` | `gitea.example.com` | host del registry (con porta se serve, es. `:3000`) |
| `REGISTRY_USER` | `laura` | utente Gitea con scrittura sui package |
| `REGISTRY_PASSWORD` | *(token/PAT)* | password o PAT con scope `write:package` |

Imposta poi `SYNC_IMAGE` nel `.env` con quel percorso, es.:

```
SYNC_IMAGE=gitea.miodominio.it/laura/ambulanza-sync:latest
```

> Per fare il `pull` dell'immagine, il server dove gira il compose deve poter accedere al
> registry Gitea: se è privato, esegui prima `podman login <host-gitea>`.

## Sicurezza

- Cambia **sempre** `JWT_SECRET`, `ADMIN_PASSWORD` e `POSTGRES_PASSWORD`.
- Esponi il servizio dietro HTTPS (reverse proxy) in produzione.
- Aggiungi altri utenti con `POST /auth/users` (da loggato) — uno per volontario.
