# CLAUDE.md — Guida per le chiamate IA (branch flutter-rewrite)

> **Branch sperimentale**: questo branch (`flutter-rewrite`) è un **rewrite completo in Flutter**
> dell'app originale React Native / Expo. L'app originale è sul branch `main`/`sviluppo`.
> Il backend Node+Express in `backend/` è condiviso e non cambia.

---

## ⚠️ REGOLE OPERATIVE

1. **Branch:** i commit di questo rewrite vanno su **`flutter-rewrite`**. L'app originale RN
   è su `main`/`sviluppo` e non va toccata da qui.
2. **Tieni aggiornato questo file:** ogni volta che cambi struttura o prendi una decisione
   tecnica, aggiorna `CLAUDE.md` nello stesso commit.
3. **Commenta il codice in italiano:** ogni funzione/widget non banale deve avere un commento
   che spiega *cosa* fa e *perché*.
4. **Verifica prima di chiudere:** `flutter analyze` deve uscire senza errori (`error`).
   Gli `info` warning minori sono accettabili.
5. **Convenzione commit (Conventional Commits):** `feat:`, `fix:`, `chore:`, `docs:`.
   Messaggi in italiano.

---

## Stack Flutter

| Ruolo | Libreria |
|---|---|
| Framework | Flutter 3.22.3 (Dart 3.4.4) |
| DB | `sqflite` (SQLite nativo Android) |
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
│   └── helpers.dart               TUTTE le funzioni CRUD + StatisticheData
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
        └── impostazioni_screen.dart CRUD assoc./persone/ospedali/tipologie via dialog

backend/                            API sync Node+Express+PostgreSQL (invariata)
.gitea/workflows/build-backend.yml  CI Docker per il backend (invariata)
```

---

## Schema DB

Identico all'app React Native (stesse tabelle, stessi CHECK, stessi indici) — così un
eventuale import/export JSON è compatibile tra le due versioni dell'app.

Tabelle principali: `associazioni`, `persone`, `ospedali`, `tipologie_turno`,
`tipologie_assistenza`, `turni`, `servizi`, `assistenze`, `sync_meta`, `deletions`.

Il DB è un singleton (`getDb()` in `database.dart`) aperto all'avvio in `main()`.
Le migrazioni sono idempotenti: girando `CREATE TABLE IF NOT EXISTS` a ogni apertura.

---

## Avvio & verifica

```bash
flutter pub get
flutter analyze          # deve passare senza errori (exit 0)
flutter run              # su device Android connesso o emulatore
flutter build apk        # APK debug/release
```

## Gradle / Java

La build Android richiede **Gradle 8.7+** (aggiornato in `gradle-wrapper.properties`)
per la compatibilità con Java 23. Il workflow Gitea (`build-android.yml`) andrà
aggiornato per usare `flutter build apk` invece di expo/Gradle diretto — TODO.

## Funzionalità implementate

- Turni: lista ordinata per data desc, filtro associazione, create/edit/delete, form
  completo (assoc. obbligatoria, data, ore, tipologia + extra, equipaggio 1ª/2ª parte).
- Servizi nel dettaglio turno: aggiunta, modifica, eliminazione, riordino con frecce.
- Assistenze: identico ai turni ma senza tipologia né servizi.
- Statistiche: 6 card (turni, servizi, ore turni, assistenze, ore assist., ore totali)
  con filtro per associazione (chip).
- Impostazioni: CRUD associazioni, persone (cognome+nome), ospedali (nome+città),
  tipologie turno (rinominabili, non eliminabili come da spec originale).
- Numerazione progressiva: ricalcolata automaticamente a ogni save/delete nel DB.

## TODO (differenze rispetto all'app originale)

- [ ] Backup export/import JSON
- [ ] Sincronizzazione backend (syncManager)
- [ ] Workflow CI build-android.yml aggiornato per Flutter
- [ ] Tipologie assistenza (tabella esiste, UI non ancora implementata)
- [ ] `cambio_meta` (campo per equipaggio a cambio metà turno)
- [ ] Long-press + Dismissible sulle card per eliminazione più rapida
- [ ] Test unitari per helpers.dart
