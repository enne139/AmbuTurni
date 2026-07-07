# AmbuTurni

App Flutter per la gestione di turni e assistenze in ambulanza, pensata per
associazioni di volontariato (tipo Croce Verde, Pubblica Assistenza).
Offline-first, tema scuro, dati salvati in locale su SQLite.

Rewrite completo dell'app originale React Native/Expo — il backend
Node+Express in `backend/` è condiviso tra le due versioni e non cambia.

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

### In CI (Gitea)

Il workflow `build-android.yml` ricostruisce il keystore da due secret del
repository e genera `android/key.properties` prima della build:

| Secret | Contenuto |
|---|---|
| `KEYSTORE_B64` | il file `.jks` codificato in base64 |
| `KEYSTORE_PASSWORD` | password di store e chiave (alias fisso `ambuturni`) |

## Struttura

```
lib/            codice dell'app (db/, providers/, screens/, widgets/, utils/)
android/        progetto Android nativo
windows/        progetto Windows desktop (CMake)
backend/        API di sincronizzazione Node+Express+PostgreSQL
assets/icon/    sorgenti dell'icona app
test/           test unitari (DB in-memory)
```

Per i dettagli implementativi, le decisioni tecniche e le convenzioni del
progetto, vedi [`CLAUDE.md`](CLAUDE.md).
