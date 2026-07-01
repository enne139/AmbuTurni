# CLAUDE.md — Guida per le chiamate IA (branch flutter-rewrite)

> **Branch sperimentale**: questo branch (`flutter-rewrite`) è un **rewrite completo in Flutter**
> dell'app originale React Native / Expo. L'app originale è sul branch `main`/`sviluppo`.
> Il backend Node+Express in `backend/` è condiviso e non cambia.

---

## ⚠️ REGOLE OPERATIVE

1. **Branch:** i commit di questo rewrite vanno su **`flutter-rewrite`**. L'app originale RN
   è su `main`/`sviluppo` e non va toccata da qui.
2. **Aggiorna sempre questo file:** ogni volta che cambi struttura, aggiungi una funzionalità
   o prendi una decisione tecnica, aggiorna `CLAUDE.md` nello **stesso commit**.
3. **Commenta il codice in italiano:** ogni funzione/widget non banale deve avere un commento
   che spiega *perché* (non il *come*: quello è già leggibile dal codice).
   I commenti vanno aggiunti **nella stessa sessione** in cui scrivi il codice.
4. **Fai il commit dopo ogni modifica:** ogni feature, fix o refactor va salvato in un commit
   subito, con messaggio in stile Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`)
   e testo in italiano. Non accumulare più modifiche in un unico commit generico.
5. **Verifica prima di chiudere:** `flutter analyze` deve uscire senza errori (`error`).
   Gli `info` warning minori sono accettabili.

---

## Stack Flutter

| Ruolo | Libreria |
|---|---|
| Framework | Flutter 3.22.3 (Dart 3.4.4) |
| DB Android | `sqflite` (SQLite nativo) |
| DB Desktop | `sqflite_common_ffi` (SQLite via FFI, usato su Windows/Linux/macOS) |
| State management | `provider` (ChangeNotifier) |
| Date | `intl` (DateFormat) |
| ID | `uuid` v4 |
| File backup | `share_plus` (export) + `file_picker` (import) |
| HTTP (sync) | `http` |
| Preferenze | `shared_preferences` |
| Build | `flutter build apk` oppure workflow Gitea |

---

## Struttura cartelle

```
lib/
├── main.dart                      entry: init DB + MultiProvider + MaterialApp
├── utils/
│   ├── theme.dart                 buildDarkTheme(), getCodiceColor(), costanti colori
│   └── format.dart                formatDate/Ore/parseOre/todayIso
├── db/
│   ├── database.dart              getDb() singleton sqflite, schema SQL, migrations
│   ├── models.dart                classi Dart (fromMap/toMap/copyWith) — 1:1 con le tabelle
│   ├── helpers.dart               TUTTE le funzioni CRUD + StatisticheData
│   └── backup.dart                exportBackup() + importBackup() via share_plus/file_picker
├── providers/
│   └── app_provider.dart          AnagraficheProvider, TurniProvider, AssistezeProvider
├── navigation/
│   └── app_navigator.dart         Scaffold con NavigationBar a 4 tab (IndexedStack)
├── widgets/
│   └── codice_chip.dart           chip colorato per codici chiamata/uscita
└── screens/
    ├── turni/
    │   ├── turni_list.dart         lista + FAB + long-press elimina + filtro assoc.
    │   ├── turno_form.dart         form crea/modifica turno (assoc., data, ore, tipol., eq.)
    │   ├── turno_detail.dart       dettaglio + lista servizi con riordino frecce
    │   └── servizio_form.dart      form crea/modifica servizio (codici, ospedale, desc.)
    ├── assistenze/
    │   ├── assistenze_list.dart
    │   ├── assistenza_form.dart
    │   └── assistenza_detail.dart
    ├── statistiche/
    │   └── statistiche_screen.dart  card statistiche + filtro associazione (chip)
    └── impostazioni/
        └── impostazioni_screen.dart CRUD assoc./persone/ospedali/tipologie + backup

backend/                            API sync Node+Express+PostgreSQL (invariata)
.gitea/workflows/build-backend.yml  CI Docker per il backend (invariata)
windows/                            progetto CMake generato da flutter create --platforms windows
```

---

## Schema DB

Identico all'app React Native (stesse tabelle, stessi CHECK, stessi indici) — così un
import/export JSON è compatibile tra le due versioni dell'app.

Tabelle principali: `associazioni`, `persone`, `ospedali`, `tipologie_turno`,
`tipologie_assistenza`, `turni`, `servizi`, `assistenze`, `sync_meta`, `deletions`.

Il DB è un singleton (`getDb()` in `database.dart`) aperto all'avvio in `main()`.
Le migrazioni sono idempotenti: `CREATE TABLE IF NOT EXISTS` a ogni apertura.

### Desktop (Windows/Linux/macOS)

`getDb()` rileva la piattaforma e chiama `sqfliteFfiInit()` + imposta
`databaseFactory = databaseFactoryFfi` prima di aprire il DB. Su Android usa il
driver nativo; nessuna distinzione nel resto del codice.

---

## Avvio & verifica

```bash
flutter pub get
flutter analyze          # deve passare senza errori (exit 0)
flutter run              # su device Android connesso o emulatore
flutter run -d windows   # per test rapido su Windows (richiede Visual Studio)
flutter build apk        # APK debug/release
```

## Gradle / Java

La build Android richiede **Gradle 8.10.2** (`gradle-wrapper.properties`) per la
compatibilità con Java 23. Il workflow Gitea (`build-android.yml`) andrà aggiornato
per usare `flutter build apk` invece di expo/Gradle diretto — TODO.

## Decisioni tecniche rilevanti

- **sqflite_common_ffi**: aggiunto per Windows; su Android è un no-op ma mantiene
  un codice identico su tutte le piattaforme.
- **ConflictAlgorithm.replace** negli insert: upsert idiomatico di sqflite; equivale a
  `INSERT OR REPLACE INTO` e funziona sia per create che per update.
- **tipologie_extra**: `List<String>` in Dart, serializzata come `TEXT` JSON nel DB
  (`jsonEncode`/`jsonDecode` in `models.dart`). Stessa scelta dell'app RN originale.
- **byId\* con try/catch**: `firstWhere` lancia `StateError` se non trova nulla;
  usiamo try/catch invece di `firstWhereOrNull` per evitare il package `collection`.
- **Combobox con ricerca (`PersonaPicker` / `OspedalePicker`)**: nei campi equipaggio e
  ospedale si usa `RawAutocomplete<T>` con controller+focus esterni; filtra la lista
  in tempo reale e include una voce fissa "Aggiungi..." in fondo che apre un dialog di
  creazione inline. L'aggiornamento del campo dopo la creazione avviene in `didUpdateWidget`
  via `addPostFrameCallback` per evitare modifiche al controller durante il build.
- **PRAGMA foreign_keys = OFF** durante l'import backup: permette di svuotare tutte
  le tabelle nell'ordine corretto senza violare i vincoli FK durante il delete.

---

## Funzionalità implementate

- ✅ Turni: lista ordinata per data desc, filtro associazione, create/edit/delete, form
  completo (assoc. obbligatoria, data, ore, tipologia + extra chip, equipaggio 1ª/2ª parte).
- ✅ Equipaggio: UI a colonna singola con label del ruolo sempre visibile a sinistra
  (redesign rispetto alla griglia 2-colonne originale in cui le label sparivano dopo selezione).
- ✅ Servizi nel dettaglio turno: aggiunta, modifica, eliminazione, riordino con frecce.
- ✅ Assistenze: identico ai turni ma senza tipologia né servizi.
- ✅ Statistiche: 6 card (turni, servizi, ore turni, assistenze, ore assist., ore totali)
  con filtro per associazione (chip).
- ✅ Impostazioni: CRUD associazioni, persone (cognome+nome), ospedali (nome+città),
  tipologie turno (rinominabili, non eliminabili come da spec originale).
  Ogni sezione è collassata di default, con badge contatore sempre visibile,
  pulsante + accessibile senza espandere, e campo ricerca integrato nell'espanso.
- ✅ Backup export/import JSON: export via share_plus, import via file_picker con conferma.
- ✅ Combobox con ricerca per equipaggio e ospedale: `PersonaPicker` e `OspedalePicker`
  in `widgets/anag_pickers.dart` permettono di filtrare la lista digitando e di creare
  nuove voci al volo tramite "Aggiungi..." (auto-selezione dopo creazione inclusa).
- ✅ Numerazione progressiva: ricalcolata automaticamente a ogni save/delete nel DB.
- ✅ Supporto Windows desktop (per test rapido senza emulatore Android).

## TODO (differenze rispetto all'app originale)

- [ ] Sincronizzazione backend (syncManager) — tabelle `sync_meta` e `deletions` già esistono
- [ ] Workflow CI build-android.yml aggiornato per Flutter (`flutter build apk`)
- [ ] Tipologie assistenza (tabella esiste, UI in impostazioni non ancora implementata)
- [ ] `cambio_meta` (campo per equipaggio a cambio metà turno)
- [ ] Long-press + Dismissible sulle card per eliminazione più rapida
- [ ] Test unitari per `helpers.dart`
