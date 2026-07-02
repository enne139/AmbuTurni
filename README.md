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
