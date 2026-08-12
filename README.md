# AmbuTurni

App Flutter per la gestione di turni e assistenze in ambulanza, pensata per
associazioni di volontariato (tipo Croce Verde, Pubblica Assistenza).
Offline-first, tema scuro, dati salvati in locale su SQLite.

Rewrite completo dell'app originale React Native/Expo, dismessa. Il backend
in `backend/` (Go + PostgreSQL) espone un elenco condiviso di ospedali,
scaricabile per città dal tool "Lista ospedali" — non sincronizza i dati
dell'app, che restano locali sul device (vedi Backup qui sotto).

## Funzionalità

- **Turni**: lista filtrabile per associazione con ricerca testuale, form
  completo (data, ore, tipologia + tipologie extra, equipaggio 1ª/2ª parte),
  servizi annidati (codici chiamata/uscita, ospedale, riordino).
- **Assistenze**: come i turni ma senza tipologia né servizi.
- **Statistiche**: turni, servizi, ore turni, assistenze, ore assistenze, ore
  totali — filtrabili per associazione.
- **Impostazioni**: CRUD di associazioni, persone, ospedali e tipologie turno,
  con combobox di ricerca e creazione rapida ("Aggiungi...") direttamente dai
  form di turni/assistenze.
- **Backup**: export/import JSON completo, più un export leggibile (solo
  turni, con nomi al posto degli UUID).
- Vista turni/assistenze filtrata per persona o ospedale.

## Stack

| Ruolo | Libreria |
|---|---|
| Framework | Flutter stable (>= 3.27) |
| DB | `sqflite` (Android) / `sqflite_common_ffi` (Windows/desktop) |
| State management | `provider` |
| Backup | `share_plus` + `file_picker` |
| Icona app | `flutter_launcher_icons` |

## Avvio

```bash
flutter pub get
flutter analyze          # deve passare senza errori
flutter run               # Android (device o emulatore)
flutter run -d windows    # Windows desktop (richiede Visual Studio)
flutter build apk         # APK release
```

## Backend (elenco condiviso ospedali)

Il codice sta in `backend/` (Go + PostgreSQL); i dettagli degli endpoint
sono in [`backend/README.md`](backend/README.md). In produzione **non gira
da solo**: il binario è compilato dentro l'immagine Docker della versione
web (vedi sotto), non c'è un'immagine backend separata da installare.

### Sviluppo/test locale

Con Docker (backend + Postgres insieme):

```bash
cd backend
cp .env.example .env      # personalizza le credenziali
docker compose up --build -d
curl http://localhost:3000/api/health        # {"status":"ok"}
```

Pagina di gestione ospedali: `http://localhost:3000/admin/` (login con
`ADMIN_USERNAME`/`ADMIN_PASSWORD` da `.env`).

Senza Docker (richiede Go ≥ 1.22 e un Postgres raggiungibile):

```bash
cd backend
DATABASE_URL=postgres://ambulanza:pw@localhost:5432/ambulanza \
JWT_SECRET=dev ADMIN_USERNAME=admin ADMIN_PASSWORD=admin \
go run .
```

Per far puntare l'app Flutter a questo backend locale invece che a quello di
produzione: Lista ospedali → icona ingranaggio → indirizzo del server (es.
`http://localhost:3000`, o l'IP del PC in rete locale se testi da telefono
— **senza** `/api/` finale: è l'app ad aggiungerlo da sola a ogni chiamata,
le rotte del backend vivono sotto `/api/` sia in locale sia in produzione).

### Installazione in produzione

L'immagine `ambuturni-web` (build multi-stage: web Flutter + backend Go +
nginx, pubblicata sul GitHub Container Registry — `ghcr.io` — a ogni tag
`vX.Y.Z`) include
già il backend: serve solo un **PostgreSQL raggiungibile** dal container e
le variabili d'ambiente del backend passate al container `ambuturni-web`
(prima, quando l'immagine era solo statica, non servivano):

| Variabile | Descrizione |
|---|---|
| `DATABASE_URL` | connessione a PostgreSQL, es. `postgres://ambulanza:PASSWORD@db:5432/ambulanza` |
| `JWT_SECRET` | stringa lunga e casuale, firma i token della pagina admin |
| `ADMIN_USERNAME` / `ADMIN_PASSWORD` | credenziali admin create al primo avvio |
| `TOKEN_TTL` | opzionale, durata del token (default `30d`) |

Esempio di `docker-compose.yml` lato server:

```yaml
services:
  db:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_USER: ambulanza
      POSTGRES_PASSWORD: <password-vera>
      POSTGRES_DB: ambulanza
    volumes:
      - pgdata:/var/lib/postgresql/data

  web:
    image: ghcr.io/enne139/ambuturni-web:latest   # o un tag vX.Y.Z
    # Se il pacchetto su ghcr.io è privato serve prima un `docker login
    # ghcr.io` con un PAT (scope read:packages) sul server di produzione.
    restart: unless-stopped
    depends_on: [db]
    environment:
      DATABASE_URL: postgres://ambulanza:<stessa-password>@db:5432/ambulanza
      JWT_SECRET: <stringa-lunga-casuale>
      ADMIN_USERNAME: admin
      ADMIN_PASSWORD: <password-vera>
    ports:
      - '80:80'   # dietro il reverse proxy/TLS già in uso per il dominio

volumes:
  pgdata:
```

Il container espone solo HTTP: la terminazione TLS (es. per
`ambuturni.maratuck.com`, il default configurato nell'app) resta a un
reverse proxy davanti, come già oggi. Se il backend non riesce a connettersi
al database l'app web statica resta comunque servita — solo le chiamate
`/api/*` falliscono, verificabile nei log del container.

## Firma di release (keystore)

L'APK di release è firmato con un keystore PKCS12 dedicato. Senza keystore la
build ricade sulla firma debug: funziona in locale, ma l'APK **non va
distribuito** — gli aggiornamenti via Obtainium richiedono la stessa firma tra
una versione e l'altra.

### In locale

Il keystore vive fuori dal repository, in `%USERPROFILE%\keystores\`.
`android/app/build.gradle` lo cerca tramite `android/key.properties`
(gitignorato insieme ai file `*.keystore`):

```properties
storeFile=C:\\Users\\<utente>\\keystores\\ambuturni-release.jks
storePassword=<password>
keyAlias=ambuturni
keyPassword=<password>
```

Se `key.properties` non esiste, `flutter build apk` firma con la chiave debug
senza errori: comodo per provare la build, ma vedi l'avvertenza sopra.

### In CI (GitHub Actions)

Il workflow `build-android.yml` ricostruisce il keystore da due secret del
repository GitHub e genera `android/key.properties` prima della build:

| Secret | Contenuto |
|---|---|
| `KEYSTORE_B64` | il file `.jks` codificato in base64 |
| `KEYSTORE_PASSWORD` | password di store e chiave (alias fisso `ambuturni`) |

Impostabili da Settings → Secrets and variables → Actions → New repository
secret, o via `gh secret set NOME --repo enne139/ambuturni`.

**Keystore rigenerato dopo la violazione del vecchio server Gitea (2026-08)**:
i secret CI vivevano lì e sono considerati potenzialmente esposti — chi ha
già installato l'app (anche via Obtainium) non riceve più aggiornamenti
in-place con la nuova firma e deve disinstallare/reinstallare. Per generare
un nuovo keystore:

```bash
keytool -genkeypair -v -storetype PKCS12 \
  -keystore ambuturni-release.jks -alias ambuturni \
  -keyalg RSA -keysize 2048 -validity 10000
base64 -w0 ambuturni-release.jks   # da incollare in KEYSTORE_B64
```

## Struttura

```
lib/            codice dell'app (db/, providers/, screens/, widgets/, utils/)
android/        progetto Android nativo
windows/        progetto Windows desktop (CMake)
backend/        API Go+PostgreSQL dell'elenco condiviso ospedali
assets/icon/    sorgenti dell'icona app
test/           test unitari (DB in-memory)
```

Per i dettagli implementativi, le decisioni tecniche e le convenzioni del
progetto, vedi [`CLAUDE.md`](CLAUDE.md).
