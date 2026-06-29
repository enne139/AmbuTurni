# CLAUDE.md — Guida per le chiamate IA

> App **React Native + Expo (SDK 52)** per la gestione di **turni** e **assistenze** in
> ambulanza. Offline‑first (SQLite locale), Android + Web, tema scuro.
> Questo file viene caricato automaticamente a ogni sessione: **leggilo e tienilo aggiornato.**

---

## ⚠️ REGOLE OPERATIVE (sempre, non negoziabili)

1. **Branch:** fai SEMPRE i commit sul branch **`sviluppo`**. Non committare mai direttamente
   su `main`. Se `sviluppo` non esiste, crealo da `main` (`git checkout -b sviluppo`).
   `main` resta stabile; si aggiorna solo con merge da `sviluppo`.
2. **Tieni aggiornato questo file:** ogni volta che cambi struttura, aggiungi/modifichi una
   funzionalità o prendi una decisione tecnica, aggiorna `CLAUDE.md` nello stesso commit.
3. **Commenta sempre il codice:** ogni funzione, componente, hook e query non banale deve avere
   un commento in **italiano** che spiega *cosa* fa e *perché* (non il come ovvio). Mantieni lo
   stile dei commenti già presenti.
4. **Verifica prima di chiudere:** `npx tsc --noEmit` deve passare senza errori. Quando possibile
   verifica anche che il bundle web compili e che l'app si carichi.
5. **Convenzione commit (Conventional Commits):** `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`.
   Messaggi in italiano, chiari, una riga di sintesi + eventuale corpo.
6. **Vincoli di stack:** NON usare WatermelonDB/Realm/ORM, NON usare Expo Router. Solo le
   librerie già presenti (vedi sotto). TypeScript strict, tipi espliciti, niente `any` evitabili.

---

## Stack

| Ruolo | Libreria |
|---|---|
| Framework | React Native 0.76 + Expo SDK 52 |
| DB native | `expo-sqlite` (API async) |
| DB web | `sql.js` (SQLite in WebAssembly) — vedi sotto |
| Navigazione | `@react-navigation` native / bottom-tabs / native-stack |
| UI | `react-native-paper` (MD3 dark) |
| Icone | `@expo/vector-icons` (MaterialCommunityIcons) |
| Date | `@react-native-community/datetimepicker` (native) / `<input type=date>` (web) |
| ID | `uuid` + `react-native-get-random-values` |
| File backup | `expo-file-system` + `expo-sharing` + `expo-document-picker` (native) / DOM (web) |
| Linguaggio | TypeScript strict |
| Build | EAS (`preview` → APK, `production` → app-bundle) |

---

## Struttura cartelle

```
App.tsx                 entry: init DB + PaperProvider + NavigationContainer
index.ts                registerRootComponent (+ polyfill get-random-values via App.tsx)
src/
├── components/
│   ├── DateField.tsx            selettore data cross-platform (picker native / input web)
│   ├── EquipaggioBlock.tsx      doppio equipaggio (1ª/2ª parte) con switch "cambio a metà"
│   ├── SelectableField.tsx      campo "####": modal ricerca + "Aggiungi: [testo]"
│   ├── MultiSelectableField.tsx versione multi-valore con chip
│   ├── ServizioForm.tsx         form add/edit di un singolo servizio (codici/ospedale/descr.)
│   └── ServiziManager.tsx       lista servizi nel DETTAGLIO turno: add/edit/delete/riordino
├── db/
│   ├── schema.ts               SCHEMA SQL condiviso (native + web)
│   ├── index.ts                backend NATIVE (expo-sqlite) + getDb/initDatabase
│   ├── index.web.ts            backend WEB (sql.js) con persistenza su localStorage
│   ├── migrations.ts           migrazioni idempotenti + ricalcolo numerazione
│   ├── helpers.ts              TUTTE le funzioni CRUD + tipi TypeScript
│   └── backup.ts               export/import JSON di tutte le tabelle
├── navigation/AppNavigator.tsx tab (Turni/Assistenze/Statistiche/Impostazioni) + stack
├── screens/
│   ├── turni/                  TurniList / TurnoDetail / TurnoForm
│   ├── assistenze/             AssistezeList + AssistenzaScreens (Form + Detail)
│   ├── statistiche/            StatisticheScreen
│   └── impostazioni/           ImpostazioniScreen (anagrafiche + backup)
├── sync/syncManager.ts         client di sincronizzazione (login JWT, push/pull, apply)
├── types/sql.js.d.ts           dichiarazione tipi per sql.js
└── utils/
    ├── theme.ts                colori, tema Paper, getCodiceColor (case-insensitive)
    ├── format.ts               formatDate / formatOre / parseOre
    ├── backupIO.ts             salva/scegli file backup — NATIVE
    └── backupIO.web.ts         salva/scegli file backup — WEB (DOM)

backend/                        API di sincronizzazione (Node + Express + PostgreSQL)
├── src/{index,db,auth,sync}.js server, schema PG, login JWT, push/pull
├── Dockerfile, .dockerignore
├── docker-compose.yml          postgres + api
└── .env.example, README.md
.gitea/workflows/build-backend.yml  action (Docker) build+push immagine
```

---

## Funzionalità (richieste e implementate)

- **Turni**: associazione (obbligatoria), data, ore, tipo turno (multi), descrizione, note,
  doppio equipaggio, lista servizi. Lista ordinata per **data decrescente**.
- **Assistenze**: come i turni ma senza servizi né tipologia.
- **Servizi** (gestiti nella **schermata di dettaglio del turno**, non nel form):
  - aggiungi / modifica / elimina / **riordina** (frecce su‑giù)
  - **numero progressivo per turno** (1..N, risequenziato senza buchi)
  - **codice chiamata**: `VERDE`, `GIALLO`, `ROSSO`, `DIMISSIONE`
  - **codice uscita**: `VERDE`, `GIALLO`, `ROSSO`, `NERO`, `VUOTO`, `RIFIUTO`
  - **ospedale** (nome + **città**) — opzionale, **descrizione** del servizio
- **Numerazione progressiva** di turni/assistenze = **rango per data** nell'associazione
  (il più vecchio = #1), **ricalcolata automaticamente** a ogni save/delete.
- **Statistiche**: turni totali, servizi totali, ore turni, assistenze totali, ore assistenze,
  ore totali — con **filtro per associazione** (chip).
- **Backup**: esporta/importa **JSON** di tutti i dati (Impostazioni → Backup/Dati).
  L'import **sostituisce** completamente i dati.
- **Impostazioni**: CRUD di associazioni, persone (cognome+nome), ospedali (nome+città),
  tipologie turno (rinominabili, non eliminabili). Modifica via dialog.
- **Eliminazione** turni/assistenze: pulsante nel dettaglio + long‑press sulla card in lista.

---

## Architettura / note tecniche (leggere prima di toccare il DB)

- **Doppio backend DB**: `expo-sqlite` non ha implementazione **web** in SDK 52 (lancia
  `Cannot find native module 'ExpoSQLite'`). Per il web usiamo **sql.js** in `index.web.ts`,
  che espone la **stessa API async** (`execAsync/getAllAsync/getFirstAsync/runAsync`). Metro
  risolve automaticamente `index.web.ts` sul web e `index.ts` su native. Stesso schema in
  `schema.ts`. **Non importare expo-sqlite direttamente fuori da `index.ts`.**
- **Persistenza web**: sql.js è in‑memory; lo stato viene serializzato in `localStorage`
  (base64) a ogni mutazione. Il `.wasm` è caricato da CDN jsdelivr (serve rete al 1° avvio web).
- **Migrazioni** (`migrations.ts`): idempotenti, girano su entrambi i backend dopo lo SCHEMA.
  Ricostruiscono `servizi` quando serve (nuove colonne/CHECK), inizializzano `ordine`, e
  **ricalcolano la numerazione** di turni/assistenze/servizi sui dati esistenti.
- **Codici colore**: `getCodiceColor` in `theme.ts` è **case-insensitive**.
- **Pattern UI**: i form usano `ScrollView`; le liste/dettagli ricaricano con `useFocusEffect`.
  I campi multiline hanno `numberOfLines` + `minHeight` per stabilità su web.
- **File IO backup**: `backupIO.ts` (native: FileSystem+Sharing+DocumentPicker) e
  `backupIO.web.ts` (browser: Blob download + input file). Metro sceglie la variante giusta.

---

## Backend / Sincronizzazione (cartella `backend/`)

- **Stack**: Node.js + Express + PostgreSQL. Auth con **JWT** (login utente/password,
  hash bcrypt; admin iniziale da `ADMIN_USERNAME`/`ADMIN_PASSWORD`).
- **Modello dati**: tabella generica `records (table_name, id, data JSONB, …)` — il server
  non conosce lo schema dell'app, quindi non va toccato se cambia. Conflitti **last-write-wins**.
- **Endpoint**: `/health`, `POST /auth/login`, `POST /auth/users` (protetto),
  `POST /sync/push`, `GET /sync/pull?since=ISO` (protetti da Bearer token).
- **Client** (`src/sync/syncManager.ts`): `login()`, `syncNow()` (push righe con
  `is_synced=0` → poi le marca; pull dopo `last_sync_at` → applica con FK off).
  Config in tabella `sync_meta`. UI in **Impostazioni → Sincronizzazione**.
- **Deploy**: `backend/docker-compose.yml` (postgres + api, ok con `podman-compose`).
  L'immagine è costruita dalla action `.gitea/workflows/build-backend.yml` (**Docker**),
  pubblicata sul registry della **stessa istanza Gitea**. L'host si ricava da
  `GITHUB_SERVER_URL`; per l'auth serve **un solo secret** `REGISTRY_TOKEN` (PAT con
  scope `write:package`) — il token integrato non basta. Serve un runner con Docker.

## Avvio & verifica

```bash
npm install
npx expo start --web        # se errori di rete CLI: EXPO_OFFLINE=1 npx expo start --web
npx tsc --noEmit            # type-check (deve passare)
```

Dopo modifiche allo **schema o alle migrazioni**, sul web serve un **hard refresh**
(Ctrl+Shift+R) perché il DB è già inizializzato in `localStorage` (cache `dbPromise`).

---

## Cose da migliorare / lezioni apprese (AGGIORNARE nel tempo)

- L'aggiunta *rapida* di un ospedale dal `SelectableField` salva solo il **nome**; la città si
  inserisce/corregge da Impostazioni → Ospedali.
- Bug "campi multiline su web" segnalato ma non riprodotto del tutto: tenere d'occhio.
- Web + sql.js dipende dal CDN per il `.wasm`: valutare di bundlare il wasm per offline reale.
- **Sync**: implementata (backend + client), incluse le **eliminazioni** tramite tombstone
  (tabella locale `deletions`): le delete locali registrano un tombstone, il push lo invia con
  `deleted=true`, gli altri dispositivi lo applicano col pull. Cancellando un turno si crea il
  tombstone anche per i suoi servizi (rimossi in cascata). Nota: dopo un import/restore del
  backup, eventuali tombstone pregressi potrebbero ri-eliminare dati al primo sync (caso limite).
- L'immagine del backend è pubblicata sul **registry dello stesso Gitea** dall'action
  (`.gitea/workflows/build-backend.yml`, **Docker**). Host del registry ricavato da
  `GITHUB_SERVER_URL`; login con `${{ github.actor }}` + il PAT nel secret
  **`REGISTRY_TOKEN`** (scope `write:package`). Il token integrato `GITHUB_TOKEN` dà
  `unauthorized` sul push (non ha i permessi package), quindi il PAT è obbligatorio.
  Serve un runner con accesso al daemon Docker (socket `/var/run/docker.sock` montato
  oppure Docker-in-Docker). Imposta poi `SYNC_IMAGE` nel `.env` del compose con
  `<host-gitea>/<owner>/ambulanza-sync`.
  Nota build: si costruisce con `docker buildx build --builder default --load` (immagine
  nello store locale del daemon) e si fa il `docker push` in uno step separato. Il builder
  `docker-container` non va bene qui: non carica l'immagine in locale (push → `image not
  known`) e gira in un container con rete isolata che non raggiunge il registry (push →
  `connection refused`), mentre il `docker login`/`push` dal job container funzionano.
- Possibili migliorie UX: import "merge" (oltre a "replace"), riordino drag&drop dei servizi.
- Sicurezza backend: in produzione mettere l'API dietro HTTPS (reverse proxy).
```
