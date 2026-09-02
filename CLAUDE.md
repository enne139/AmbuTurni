# CLAUDE.md — Guida per le chiamate IA

> Questo è il rewrite completo in Flutter dell'app originale React Native / Expo.
> Il rewrite è stato integrato su `main` (2026-07-01). Il backend in
> `backend/` (Go, dal 2026-07-14) espone l'elenco condiviso ospedali — non
> è un backend di sincronizzazione dei dati dell'app, vedi Decisioni tecniche.

---

## ⚠️ REGOLE OPERATIVE

1. **Branch:** i commit vanno su `main` (direttamente, oppure via branch di
   feature/fix mergiati e poi cancellati).
2. **Aggiorna sempre questo file:** ogni volta che cambi struttura, aggiungi una funzionalità
   o prendi una decisione tecnica, aggiorna `CLAUDE.md` nello **stesso commit**.
3. **Commenta il codice in italiano:** ogni funzione/widget non banale deve avere un commento
   che spiega *perché* (non il *come*: quello è già leggibile dal codice).
   I commenti vanno aggiunti **nella stessa sessione** in cui scrivi il codice.
4. **Fai il commit dopo ogni modifica:** ogni feature, fix o refactor va salvato in un commit
   subito, con messaggio in stile Conventional Commits (`feat:`, `fix:`, `chore:`, `docs:`)
   e testo in italiano. Non accumulare più modifiche in un unico commit generico.
   **Prima di committare codice, chiedi all'utente di verificare che l'app funzioni**
   (test manuale su device/desktop) e aspetta la sua conferma. Eccezione: modifiche
   solo a documentazione/CI, che non richiedono test manuale.
5. **Verifica prima di chiudere:** `flutter analyze` deve uscire senza errori (`error`).
   Gli `info` warning minori sono accettabili.
6. **Esegui i test prima del commit:** oltre ad `analyze`, lancia `flutter test`
   (test unitari in `test/db/helpers_test.dart`) prima di ogni commit di codice —
   `analyze` non intercetta le regressioni logiche nel CRUD. Se aggiungi o modifichi
   funzioni in `helpers.dart`, aggiorna anche i test corrispondenti.
7. **Modifiche allo schema DB = bump di versione + migrazione:** ogni cambiamento a
   uno schema che un device potrebbe già aver aperto (anche solo durante il test di
   un branch) richiede un bump della versione DB con una vera migrazione in
   `_onUpgrade`, mai un edit in-place dello schema esistente (lezione v4→v5, vedi
   Decisioni tecniche). Le nuove tabelle vanno aggiunte anche a `_backupTables` in
   `backup.dart`; i backup JSON dei formati precedenti (inclusi quelli della
   vecchia app RN) devono restare importabili — le normalizzazioni vivono in
   `importBackup`.
8. **Testa su Android reale le modifiche a DB/piattaforma:** per modifiche che
   toccano il DB, plugin nativi o comportamenti di piattaforma, verifica su un
   telefono reale via adb — il bug del PRAGMA WAL era invisibile su Windows/desktop
   e si manifestava solo su Android reale.
9. **Processo di release:** bump della versione in `pubspec.yaml` (`X.Y.Z+N`,
   incrementando entrambe le parti), commit su `main`, poi tag `vX.Y.Z`: il push
   del tag fa pubblicare al workflow GitHub Actions l'APK come artifact e
   come Release GitHub, e pubblica anche l'immagine Docker della versione
   web (build-web.yml) su `ghcr.io` con un tag pari alla versione — il
   deploy sul server resta comunque manuale.

---

## Stack Flutter

| Ruolo | Libreria |
|---|---|
| Framework | Flutter stable (>= 3.27 richiesto per CardThemeData/withValues) |
| DB Android | `sqflite` (SQLite nativo) |
| DB Desktop | `sqflite_common_ffi` (SQLite via FFI, usato su Windows/Linux/macOS) |
| State management | `provider` (ChangeNotifier) |
| Date | `intl` (DateFormat) |
| ID | `uuid` v4 |
| File backup | `share_plus` (export) + `file_picker` (import) |
| HTTP (sync) | `http` |
| Preferenze | `shared_preferences` |
| Markdown nelle note | `flutter_markdown_plus` (fork mantenuto; l'ufficiale `flutter_markdown` è discontinued) |
| Lettura XLSX (Piano turni) | `excel` |
| Eventi calendario (Piano turni) | `add_2_calendar` (intent Android, nessun permesso; assente su desktop/web) |
| Mappa (Lista ospedali) | `flutter_map` + `latlong2`, tile OpenStreetMap, nessuna API key (funziona anche su Windows/web) |
| Geocoding indirizzi (Lista ospedali) | Nominatim (OpenStreetMap), nessuna API key, chiamato solo alla creazione/modifica di un ospedale |
| Apertura navigatore esterno (Lista ospedali) | `url_launcher`, link universale Google Maps |
| Icona app | `flutter_launcher_icons` (dev dependency), genera Android+Windows+web da `assets/icon/` |
| Versione app a runtime | `package_info_plus` (legge X.Y.Z+N dalla piattaforma, mostrata in Impostazioni) |
| Localizzazione widget nativi | `flutter_localizations` (SDK), solo per `showDatePicker`: `locale` fisso `it`, il resto dell'app resta testo italiano hardcoded |
| Build | `flutter build apk` oppure workflow GitHub Actions |

Web (Chrome/Edge, `flutter run -d chrome` / `flutter build web`): DB via
`sqflite_common_ffi_web` (SQLite compilato in WASM, persistito in IndexedDB),
vedi "Piattaforma web" in Decisioni tecniche per i dettagli e i limiti.

---

## Struttura cartelle

```
lib/
├── main.dart                      entry: init DB + MultiProvider + MaterialApp
├── utils/
│   ├── theme.dart                 buildDarkTheme(), getCodiceColor(), costanti colori
│   ├── format.dart                formatDate/Ore/parseOre/dateToIso + nomi mesi/giorni it
│   ├── piano_mensile.dart         parser XLSX del piano turni mensile (Dart puro, testato)
│   ├── piano_cache.dart           cache dei piani decodificati: solo export condizionale
│   │                               (vedi Piattaforma web), impl. in piano_cache_io.dart
│   │                               (file JSON per mese) / piano_cache_web.dart
│   │                               (shared_preferences/localStorage)
│   ├── platform_check.dart        isDesktop/isMobile: export condizionale io/web di
│   │                               Platform.isX (dart:io non compila sul target web)
│   ├── geocoding_api.dart         client Dart puro di Nominatim (OpenStreetMap): risolve
│   │                               un indirizzo testuale in lat/lng per la mappa del tool
│   │                               Lista ospedali, testato con MockClient
│   ├── backend_api.dart           client Dart puro del backend condiviso ospedali (backend/,
│   │                               Go): GET /api/ospedali?citta=, testato con MockClient
│   ├── prefs_keys.dart            chiavi SharedPreferences condivise col backup
│   │                               (Piano turni + Tools attivi + indirizzo del backend
│   │                               condiviso ospedali + sincronizzazione fogli turni)
│   └── tools_config.dart          catalogo dei tool disattivabili (id, titolo, icona,
│                                   attivoDiDefault): fonte unica per ToolsScreen e
│                                   Impostazioni → Tools attivi
├── db/
│   ├── database.dart              getDb() singleton sqflite, schema SQL, migrations
│   ├── models.dart                classi Dart (fromMap/toMap/copyWith) — 1:1 con le tabelle
│   ├── helpers.dart               TUTTE le funzioni CRUD + StatisticheData
│   └── backup.dart                exportBackup() + importBackup(); il filesystem/picker è
│                                    in backup_file.dart, export condizionale io/web (vedi
│                                    Piattaforma web)
├── providers/
│   └── app_provider.dart          AnagraficheProvider, TurniProvider, AssistenzeProvider,
│                                   StatisticheProvider, ToolsProvider, NavigazioneProvider,
│                                   TutorialProvider, AccountProvider (sessione utente-app:
│                                   login/cambio password/logout, sblocca i contenuti riservati)
├── navigation/
│   └── app_navigator.dart         Scaffold con NavigationBar (2-5 tab, IndexedStack, tab
│                                   selezionata per identità con l'enum _TabId); la tab Attività
│                                   unisce Turni e Assistenze con un SegmentedButton sotto
│                                   l'AppBar e inietta lì l'icona Anagrafiche; Attività+
│                                   Statistiche sono disattivabili insieme e Piano turni può
│                                   comparire come voce propria, entrambe da Impostazioni →
│                                   Navigazione (NavigazioneProvider)
├── widgets/
│   ├── codice_chip.dart           chip colorato per codici chiamata/uscita
│   ├── anag_pickers.dart          PersonaPicker, OspedalePicker, MaterialePicker (RawAutocomplete + Aggiungi...)
│   ├── calendario_mensile.dart    CalendarioMensile<T>: vista calendario generica (turni e assistenze)
│   ├── turno_card.dart            TurnoCard: card condivisa tra turni_list e le viste filtrate
│   ├── nota_markdown.dart         NotaMarkdown: rendering markdown delle note, stile coerente col tema scuro
│   ├── tutorial_overlay.dart      avviaTutorial(): overlay spotlight a schermo intero (nessun
│   │                               package) per il tutorial di navigazione, vedi TutorialProvider
│   └── accesso_richiesto.dart     AccessoRichiesto (gate di login per un contenuto riservato,
│                                   nessuno Scaffold proprio) + LoginForm condiviso con
│                                   Impostazioni → Account
└── screens/
    ├── shared/
    │   ├── note_editor_screen.dart NoteEditorScreen: editor note a schermo intero, condiviso turno/assistenza
    │   └── cambia_password_screen.dart CambiaPasswordScreen (pagina, uso volontario da
    │                                    Impostazioni) + CambiaPasswordForm (contenuto riusato
    │                                    anche inline, forzato, da AccessoRichiesto)
    ├── anagrafiche/
    │   ├── anagrafiche_screen.dart CRUD associazioni/persone/ospedali/tipologie turno (spostato
    │   │                            da Impostazioni), raggiungibile dall'icona nell'AppBar di
    │   │                            Turni/Assistenze; export/import ospedali e geocoding compresi
    │   └── turni_filtrati_screen.dart TurniPersonaScreen/TurniOspedaleScreen: turni (e
    │                                   assistenze) in cui compare una persona/ospedale
    ├── turni/
    │   ├── turni_list.dart         lista + FAB + filtro assoc. + vista calendario (niente swipe/long-press,
    │   │                            v. Decisioni tecniche)
    │   ├── turno_form.dart         form crea/modifica turno (assoc., data, ore, tipol., eq.)
    │   ├── turno_detail.dart       dettaglio + lista servizi con riordino frecce
    │   └── servizio_form.dart      form crea/modifica servizio (codici, ospedale, desc.)
    ├── assistenze/
    │   ├── assistenze_list.dart
    │   ├── assistenza_form.dart
    │   └── assistenza_detail.dart
    ├── statistiche/
    │   └── statistiche_screen.dart  card statistiche + filtro associazione (chip)
    ├── tools/
    │   ├── tools_screen.dart          elenco strumenti extra (Materiali usati, Piano turni,
    │   │                               Lista ospedali, Repository formazione), filtrato dai tool
    │   │                               attivi (ToolsProvider); nasconde Piano turni se spostato
    │   │                               in navbar (NavigazioneProvider)
    │   ├── piano_turni_screen.dart    calendario equipaggi/buchi dal foglio Google dei turni;
    │   │                               sincronizza in sottofondo i fogli salvati sul backend
    │   │                               condiviso (kPrefSyncFogliAttivo, default attivo); pulsante
    │   │                               per aprire il link del foglio nel browser
    │   ├── lista_ospedali_screen.dart cerca ospedali per nome/via/città/regione, raggruppati
    │   │                               per regione, pulsante Naviga (Google Maps o Waze) e
    │   │                               vista mappa con tutti gli ospedali geocodificati
    │   │                               (flutter_map + OSM); scarica ospedali per città o
    │   │                               regione dal backend condiviso (backend_api.dart) — la
    │   │                               configurazione del server è in Impostazioni
    │   ├── materiali_usati_screen.dart lista utilizzi attivi, stepper +/- quantità,
    │   │                               swipe elimina, ripristina (singolo/tutto); pulsante per
    │   │                               scaricare il catalogo dal backend condiviso (come in
    │   │                               materiali_screen.dart, raggiungibile anche da qui)
    │   ├── materiale_usato_form.dart  form crea/modifica (materiale, quantità+unità, posizione, note)
    │   ├── materiali_screen.dart      gestione catalogo materiali: FAB aggiungi/rinomina/elimina
    │   │                               (doppioni case-insensitive bloccati: niente UNIQUE sul nome);
    │   │                               pulsante per scaricare il catalogo dal backend condiviso
    │   └── repository_formazione_screen.dart apre nel browser l'unico link condiviso ai
    │                                   materiali di formazione (impostato solo dalla pagina admin
    │                                   del backend condiviso, non configurabile qui). CONTENUTO
    │                                   RISERVATO: avvolto in AccessoRichiesto, richiede login.
    └── impostazioni/
        └── impostazioni_screen.dart Backup/ripristino + versione app + configurazione del
                                      backend condiviso (indirizzo del server, sincronizzazione
                                      fogli turni) + Navigazione (pagina principale, disattiva
                                      Attività+Statistiche, Piano turni in navbar) + Account
                                      (login/cambio password/logout utente-app). Le anagrafiche (associazioni/
                                      persone/ospedali/tipologie) sono in screens/anagrafiche/

backend/                            API Go+PostgreSQL dell'elenco condiviso ospedali (nome, via,
                                     città, regione, coordinate), dei link ai fogli turni mensili,
                                     del catalogo materiali, del link al repository di formazione
                                     e degli account "utente-app" che sbloccano i contenuti
                                     riservati dell'app (Repository formazione, Archivio
                                     comunicati) + pagina admin statica; NON è un backend di
                                     sincronizzazione, vedi Decisioni tecniche.
                                     ospedali.go/fogli.go/materiali.go/formazione.go/utenti_app.go/
                                     comunicati.go: CRUD (o lettura/scrittura per formazione.go,
                                     un solo valore; create/list/delete/login/cambio-password per
                                     utenti_app.go; upload multipart per comunicati.go, PDF in una
                                     colonna bytea) di ciascuna risorsa. auth.go: JWT con ruolo
                                     (`admin`/`utente`) e i tre middleware di autenticazione
                                     (authMiddleware, utenteAuthMiddleware, contentAuthMiddleware),
                                     vedi Decisioni tecniche. Repository formazione e Comunicati
                                     sono "contenuti riservati": lettura protetta da
                                     contentAuthMiddleware, richiede login nell'app.
                                     backend/Dockerfile + docker-compose.yml sono solo per
                                     sviluppo locale (`docker compose up --build`) — in
                                     produzione il binario è incorporato nell'immagine web
.github/workflows/build-web.yml      CI Docker versione web (build Flutter + backend Go + nginx,
                                     un'unica immagine — build-backend.yml è stato rimosso)
Dockerfile                          build multi-stage: web Flutter + binario backend Go +
                                     nginx (root: serve tutto il progetto, backend/ incluso)
docker-entrypoint.sh                avvia backend Go in sottofondo + nginx in primo piano
nginx.conf                          SPA fallback + cache statica + reverse proxy /api/ e
                                     /admin/ verso il backend Go
windows/                            progetto CMake generato da flutter create --platforms windows
assets/icon/                        sorgenti icona app (SVG + PNG 1024×1024), vedi sotto
```

---

## Schema DB

Nato identico all'app React Native (stesse tabelle, stessi CHECK, stessi indici)
per la compatibilità dell'import/export JSON. **L'app RN è stata dismessa
(2026-07)**: dalla versione DB 8 lo schema è libero di evolvere — la
compatibilità con i vecchi backup (RN e Flutter pre-v8) è mantenuta in
`importBackup`, che normalizza le righe dei formati precedenti.

Tabelle principali: `associazioni`, `persone`, `ospedali`, `tipologie_turno`,
`tipologie_assistenza`, `turni`, `servizi`, `assistenze`. `sync_meta` e
`deletions` (scaffolding per una sincronizzazione mai completata) sono state
rimosse in v10, vedi Decisioni tecniche.

`materiali` e `materiali_usati` (introdotte in versione DB 4, branch `feature/tools`)
non esistevano nell'app React Native. Sono incluse nel backup JSON
(`_backupTables` in `backup.dart`): un vecchio backup RN importato qui le
lascia semplicemente assenti.

Il DB è un singleton (`getDb()` in `database.dart`) aperto all'avvio in `main()`.
Le migrazioni vivono SOLO nel sistema versionato `_onCreate`/`_onUpgrade`
(versione corrente: 12); `_onOpen` esegue soltanto i PRAGMA di connessione
(WAL + foreign_keys).

`ospedali` ha anche `via` (indirizzo testuale), `lat`/`lng` (coordinate da
geocoding automatico, v9) e `regione` (v11, stessa fonte): vedi il tool
"Lista ospedali" in Decisioni tecniche.

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
flutter run -d chrome    # per test rapido su web
flutter build apk        # APK debug/release
flutter build web        # build web (dist in build/web)
```

Dopo un `flutter create`/clone pulito, prima del primo `flutter run -d chrome`/
`build web` va rigenerato il worker SQLite (non versionato, vedi
`.gitignore` e Piattaforma web in Decisioni tecniche):

```bash
dart run sqflite_common_ffi_web:setup
```

## Gradle / Java

La build Android richiede **Gradle 8.14.3** (`gradle-wrapper.properties`), **AGP 8.11.1**
e **Kotlin 1.9.0 → 2.2.20** (`android/settings.gradle`): versioni minime imposte da
Flutter stable per Java 23 (Gradle ≥ 8.14, AGP ≥ 8.11.1, KGP ≥ 2.2.20 — sotto soglia
la build fallisce con "AGP/Gradle/KGP version too low"). Il workflow GitHub
Actions (`build-android.yml`) usa `flutter build apk`.

## Decisioni tecniche rilevanti

- **Corretti due refusi negli identificatori Dart**: `eq1AutostaId`/`eq2AutostaId`
  → `eq1AutistaId`/`eq2AutistaId` (in `models.dart` e i file che li usano) e
  `AssistezeProvider`/`AssistezeList` → `AssistenzeProvider`/`AssistenzeList`.
  Solo nomi Dart: le colonne DB erano già corrette (`eq1_autista_id` ecc.),
  quindi nessuna migrazione né impatto sul formato dei backup JSON.
- **`android:allowBackup="false"`**: il default includerebbe il DB (dati
  personali di terzi) nel backup automatico Android/Drive. Trasferimento solo
  via export/import JSON esplicito.
- **`sqflite_common_ffi`** per Windows: no-op su Android, codice identico ovunque.
- **`ConflictAlgorithm.replace`** negli insert: upsert idiomatico (`INSERT OR REPLACE`).
- **`tipologie` colonna unica multi-valore (v8)**: sostituisce `tipologia_id`
  (FK "primaria") + `tipologie_extra` (JSON), che esistevano solo per
  compatibilità con lo schema RN dismesso — per l'utente è sempre stato un
  campo unico multi-valore. Migrazione v8: ricostruisce `turni` (ALTER non
  rimuove colonne con REFERENCES) fondendo i due campi, FK disattivate
  durante `_onUpgrade`. Nomi risolti via `AnagraficheProvider.byIdTipologia`
  (anche in `TurnoCard`, concatenati con `·`); `importBackup` fonde i campi
  vecchi per i backup pre-v8, che restano importabili.
- **Tool "Piano turni"** (`piano_turni_screen.dart` + `utils/piano_mensile.dart`):
  porta nell'app il tool HTML/SheetJS che l'utente usava per analizzare il
  foglio Google mensile dei turni dell'associazione. Il foglio si scarica
  dall'endpoint `export?format=xlsx` (nessuna API key, basta la condivisione
  con link) e si legge col package `excel` — unico package aggiunto, il
  parsing a mano dello zip+XML non era realistico. Il parser è Dart puro
  (niente import Flutter) così è unit-testato (`test/utils/`, workbook
  costruiti in memoria col package stesso, nessuna fixture binaria) e gira
  in un isolate via `compute()` (il decode di ~30 schede bloccherebbe la UI).
  Struttura riconosciuta: schede "LUN 1"/"GIO DIURNO 5", blocchi H12/H24/
  ASSISTENZA/GETTONE (4 ruoli)/CENTRALINO (1-2 slot)/USCITA MEZZI (saltato);
  colonna C = titolare di turno, colonna D = possibili sostituti (mostrate
  affiancate nel dettaglio), entrambe vuote = buco. UI: calendario col
  pallino per fascia sui giorni con buchi, dettaglio equipaggi per blocco al
  tap (card in sequenza operativa fissa richiesta dall'utente: H24 m/p,
  centralino giorno, H12 m/p, H24 s/n, centralino sera, assistenze, gettoni),
  filtri ruolo persistiti (il Quarto è spesso scoperto per scelta: senza
  filtro i pallini sarebbero ovunque), ultimo URL in shared_preferences e
  ricaricato all'apertura, più archivio multi-mese ("aaaa-mm" → URL, come lo
  storico del tool HTML: ogni mese ha un suo foglio) con lista nel form
  (ogni voce ha copia-link negli appunti e rimozione; "Cambia foglio" svuota
  il campo URL, perché lì si arriva per incollare un mese nuovo) e
  bottom sheet dall'AppBar, e ricerca volontario per nome
  (`PianoMensile.cercaNome`, tap sul risultato → il calendario salta al giorno).
- **Piano turni → "Aggiungi al calendario"** (v1.4.0): pulsante sulle
  card dei blocchi che apre l'editor eventi del calendario di sistema
  precompilato via `add_2_calendar` — intent `ACTION_INSERT`, nessun permesso
  runtime, ma serve la `<queries>` nel manifest (package visibility Android
  11+; senza, fallisce solo su device reale, stessa famiglia di bug di
  INTERNET/WAL). Titolo "CVS (mattina/pomeriggio/sera/notte/centralino/
  gettone/assistenza/altro)" e nessuna descrizione, formato chiesto
  dall'utente (una prima versione metteva l'equipaggio nella descrizione:
  rimosso). Il colore verde chiesto per l'evento NON è impostabile: l'intent
  di inserimento non prevede un extra colore, l'evento prende il colore del
  calendario di destinazione (mitigazione: calendario dedicato verde lato
  Google Calendar). L'orario viene dalla colonna info del blocco nel foglio:
  terza riga per i blocchi a 4 ruoli ("18:30 - 23:30"), seconda riga per il
  centralino, dove la scheda diurna ha i due intervalli mattina/pomeriggio
  separati da "/" — divisi tra i due slot, che in UI hanno ciascuno il
  proprio pulsante sulla propria riga (l'intestazione della card mostra
  orario+pulsante solo se tutti gli slot condividono lo stesso orario).
  Nuovo campo `SlotPiano.orario` + `orarioParsed` e
  `PianoMensile.intervalloEvento`, che gestisce i turni a cavallo di
  mezzanotte (fine <= inizio → giorno dopo, via costruttore `DateTime` e non
  `add(Duration)` per non sbagliare di un'ora nelle notti di cambio ora
  legale). Blocchi senza orario riconoscibile: niente pulsante, non si
  inventano orari. Su desktop il plugin non esiste: snackbar "solo su Android".
- **Piano turni → segnalino "nome cercato" sul calendario** (v1.4.0):
  i giorni in cui il nome dell'ultima ricerca volontario è **in servizio**
  hanno un'icona persona ciano nell'angolo della cella (ciano perché non
  collide né coi pallini fascia né col kPrimary di selezione/oggi;
  nell'angolo perché i pallini in basso significano "ruoli scoperti").
  "In servizio" = `PianoMensile.giorniInServizio`: sostituto (colonna D), o
  titolare (C) senza sostituto segnato — un titolare con la D compilata è
  stato sostituito e quel giorno non lavora, quindi niente segnalino
  (richiesta esplicita dell'utente). La ricerca volontario invece continua
  a usare `cercaNome`, che elenca ogni comparsa. La stessa icona compare
  anche accanto al nome nelle card del dettaglio giorno (`_nomeConSegnalino`
  in `_rigaSlot`), con la stessa regola: sostituto sì, titolare sostituito no.
- **Backup v2: sezione `preferenze`** (v1.4.0): il backup completo
  include anche le preferenze del Piano turni (URL corrente, archivio
  "aaaa-mm" → URL dei fogli — come mappa decodificata, leggibile — e ultima
  ricerca volontario), che vivono in SharedPreferences e prima andavano
  perse nel restore su un device nuovo. Chiavi centralizzate in
  `utils/prefs_keys.dart` (condivise tra schermata e backup). L'import le
  ripristina solo se presenti e valide (backup v1/RN: le preferenze del
  device restano com'erano); la versione del formato è salita a 2 ma
  l'import continua ad accettare `>= 1`. I materiali NON c'entrano: erano
  già in `_backupTables` fin dalla loro introduzione.
- **Cache locale del Piano turni** (v1.4.0, `utils/piano_cache.dart`):
  l'endpoint export di Google genera l'XLSX al momento e `excel` decodifica
  l'intero workbook — secondi di attesa a ogni apertura per dati quasi
  immutati. Ogni piano decodificato viene salvato come JSON per mese
  (`SlotPiano.toMap`/`PianoMensile.fromMap`, roundtrip unit-testato) nella
  support dir; all'apertura (e sul tap di un foglio salvato) la cache
  compare subito e `_carica(silenzioso: true)` aggiorna in sottofondo senza
  spinner, preservando il giorno selezionato se il mese è lo stesso; un
  errore di rete accende l'icona di avviso già esistente accanto al mese.
  Cache illeggibile/valori sconosciuti = cache assente (si riscarica);
  rimuovere un foglio dai salvati elimina anche il suo file. Il pulsante
  ricarica resta non-silenzioso: feedback esplicito con lo spinner.
- **Tool "Magazzino Verde" rimosso** (2026-07): collegava un gestionale di
  magazzino esterno dell'utente (giacenze/movimenti via API JSON, scanner
  barcode/QR con `mobile_scanner`, contatore rapido "Conta" scollegato
  dall'API) — tolto su richiesta esplicita, l'associazione non lo usa più.
  Rimossi `magazzino_screen.dart`, `conta_screen.dart`,
  `scanner_barcode_screen.dart`, `utils/magazzino_api.dart`,
  `utils/scanner_errors.dart`, la dipendenza `mobile_scanner`, le chiavi
  `kPrefMagazzino*` (anche dalla sezione `preferenze` del backup) e la voce
  dal catalogo tool (`tools_config.dart`/`kToolMagazzino`). Il backend Go
  condiviso non è toccato: non ha mai avuto endpoint per il magazzino (solo
  ospedali/fogli/materiali).
- **Impostazioni → Tools attivi** (`_SezioneToolsAttivi`, `ToolsProvider`,
  `utils/tools_config.dart`): switch per attivare/disattivare i tool
  mostrati nella tab Tools, tutti attivi di default. `attivoDiDefault` in
  `ToolInfo` resta comunque generico (non hardcoded a `true`): un tool
  futuro collegato a un servizio esterno da configurare potrà ripartire
  disattivato, come faceva il Magazzino Verde prima della rimozione.
  Catalogo (id, titolo, sottotitolo, icona,
  attivoDiDefault) unico in `tools_config.dart`, usato sia da
  `ToolsScreen` (filtra `kToolsDisponibili` sugli id attivi, mappa
  id→schermata di destinazione tenuta separata perché Impostazioni non ne
  ha bisogno) sia da `_SezioneToolsAttivi` (uno `SwitchListTile` per voce).
  `ToolsProvider` (stesso motivo di `StatisticheProvider`: l'IndexedStack
  di `AppNavigator` tiene Tools e Impostazioni entrambe montate, senza un
  provider condiviso uno switch cambiato non farebbe aggiornare la lista
  già mostrata) salva l'insieme degli id attivi come `List<String>` in
  SharedPreferences (`kPrefToolsAttivi`); se la chiave non è mai stata
  salvata si applicano i default del catalogo, altrimenti si usa esattamente
  quanto salvato (anche lista vuota, se l'utente disattiva tutto — Tools
  mostra un messaggio invece della lista). Inclusa nel backup come le altre
  preferenze, ma con una differenza: in `importBackup` una lista vuota è un
  valore valido da ripristinare (a differenza delle stringhe vuote delle
  altre preferenze, scartate) — solo il campo assente (backup precedenti a
  questa funzionalità) lascia i default del device.
- **Tab unificata "Attività"** (Turni + Assistenze): scelta dell'utente tra
  le due alternative proposte (selettore vs lista unica mescolata) — vince
  il selettore `SegmentedButton` sotto l'AppBar perché lascia intatte le due
  liste (ricerca, filtri, calendario, FAB propri) toccando solo la
  navigazione. `_AttivitaTab` in `app_navigator.dart` tiene le liste in un
  IndexedStack (stato preservato nel passaggio) e inietta il selettore
  nelle loro AppBar col nuovo parametro opzionale `selettore` — unico punto
  di contatto; le liste restano usabili anche da sole. NavigationBar da 5 a
  4 tab. Il nome attivo è
  mostrato in legenda e persiste tra i riavvii (`piano_turni_ultima_ricerca`,
  la stessa pref della ricerca): tipicamente si cerca il proprio nome una
  volta e da lì i propri turni si vedono a colpo d'occhio. Per questo il
  salvataggio della ricerca è passato da `dispose` a `onChanged`: il
  chiamante rilegge la pref subito dopo il pop, ma il dispose della route
  arriva solo a fine transizione — in dispose i segnalini sarebbero rimasti
  al nome precedente. Svuotare il campo di ricerca cancella anche i segnalini.
- **Anagrafiche spostate fuori da Impostazioni, raggiungibili da Attività**
  (`screens/anagrafiche/anagrafiche_screen.dart`): Associazioni, Persone,
  Ospedali e Tipologie turno (con tutto il loro CRUD, `_SezioneAnag<T>`
  condivisa, `_dialogNomeEColore`, export/import ospedali) non vivono più
  in Impostazioni — sono di uso frequente proprio mentre si compila un
  turno/un'assistenza (creazione al volo di una persona/ospedale nuovo),
  non un'impostazione. Raggiungibili con un'icona (`Icons.groups_outlined`,
  tooltip "Anagrafiche") nell'AppBar di Turni e Assistenze, iniettata da
  `_AttivitaTab` in `app_navigator.dart` tramite il nuovo parametro
  `azioniExtra` (`List<Widget>`, default vuota) che entrambe le liste
  aggiungono in coda alle proprie azioni — stesso meccanismo già in uso per
  `selettore` (un solo punto di contatto, le liste restano usabili anche da
  sole). `turni_filtrati_screen.dart` (`TurniPersonaScreen`/
  `TurniOspedaleScreen`) si è spostato con loro in `screens/anagrafiche/`.
  Impostazioni resta con Backup, Navigazione, Tools attivi, Backend
  condiviso e versione app.
- **Impostazioni → Navigazione: pagina principale + disattivazione
  Attività/Statistiche** (`NavigazioneProvider`, `kPrefPaginaPrincipale`/
  `kPrefAttivitaStatisticheAttive` in `prefs_keys.dart`): due impostazioni
  distinte ma correlate — quale pagina si apre all'avvio (Attività o Tools)
  e un solo interruttore per nascondere insieme le tab Attività (turni +
  assistenze) e Statistiche, per chi usa l'app solo per gli altri tool (es.
  solo Lista ospedali). Un solo switch per entrambe le tab,
  non due separati: le Statistiche aggregano proprio i dati di
  turni/assistenze, senza Attività non avrebbero nulla da mostrare — a
  differenza delle anagrafiche (bullet sopra), qui la richiesta esplicita
  era disattivarle insieme. Stesso motivo di `ToolsProvider` per il
  provider condiviso: `AppNavigator` e `ImpostazioniScreen` restano
  entrambe montate nell'`IndexedStack`, senza un provider uno switch
  cambiato in Impostazioni non aggiornerebbe da sola la `NavigationBar` già
  a schermo. **Selezione per identità di tab, non per indice numerico**
  (enum privato `_TabId` in `app_navigator.dart`): disattivare
  Attività/Statistiche toglie due voci dalla `NavigationBar`/`IndexedStack`,
  quindi le posizioni delle tab successive si spostano — tenere la tab
  selezionata per identità (`_TabId.impostazioni` ecc.) invece che per
  indice fa sì che la tab attualmente aperta resti selezionata alla sua
  nuova posizione senza alcun caso speciale; l'unico caso speciale reale è
  quando la tab sparita *era* quella selezionata, gestito ripiegando su
  Tools **senza sovrascrivere il campo di stato** — se le tab vengono
  riattivate più tardi la selezione originale torna a valere da sola.
  **Attività/Statistiche disattivate non possono mai essere la pagina
  principale**: invariante garantita dal provider stesso (in `carica()` e
  in `setAttivitaStatisticheAttive(false)`), non lasciata alla UI — se lo
  fosse, uno stato salvato incoerente (es. da un backup di un device con
  Attività ancora attiva) farebbe puntare l'avvio a una tab inesistente.
  `_tabSelezionata` (il campo, non la preferenza) viene allineato alla
  pagina principale in un `postFrameCallback` dopo `NavigazioneProvider.
  carica()`, stesso pattern asincrono già in uso per
  `AnagraficheProvider`/`ToolsProvider` in quel metodo: il default del
  campo (`_TabId.pianoTurni`) coincide con quello del provider prima del
  caricamento (vedi bullet sotto sui default), quindi non c'è alcun flash
  visibile in assenza di una preferenza salvata. Disattivare non tocca mai
  il database: turni, assistenze e statistiche restano intatti, solo le
  tab spariscono dalla navigazione (riattivandole, tutto torna visibile
  esattamente com'era).
- **Default di navigazione: Attività/Statistiche disattivate, Piano turni
  in navbar e come pagina principale** (richiesta esplicita dell'utente,
  applicata anche a device con turni/assistenze già registrati): il
  fallback di `NavigazioneProvider.carica()` per le tre preferenze assenti
  è stato scelto così deliberatamente, l'opposto del comportamento
  "storico" (Attività attiva/pagina principale, Piano turni nella tab
  Tools). Nessuna versione rilasciata ha mai scritto
  `kPrefAttivitaStatisticheAttive`/`kPrefPianoTurniInNavbar`/
  `kPrefPaginaPrincipale` (introdotte in questa stessa release): non esiste
  quindi un comportamento pregresso da preservare per chi aggiorna, il
  nuovo default si applica a tutti allo stesso modo, dati compresi (che
  restano intatti, vedi bullet sopra). Un utente che vuole tornare al
  comportamento con Attività in primo piano lo fa da Impostazioni →
  Navigazione, la stessa schermata di sempre.
- **Piano turni spostabile nella barra di navigazione**
  (`kPrefPianoTurniInNavbar`, `NavigazioneProvider.pianoTurniInNavbar`,
  terzo valore `pianoTurni` di `PaginaPrincipale`): interruttore
  indipendente da quello di Attività/Statistiche, per chi consulta il
  piano turni più spesso degli altri tool e non vuole passare da Tools
  ogni volta. Attivarlo **imposta subito Piano turni come pagina
  principale** (richiesta esplicita, non solo "aggiungilo alla navbar"):
  `setPianoTurniInNavbar(true)` scrive sia la preferenza sia la pagina
  principale in un colpo solo. Disattivarlo mentre è la pagina principale
  ripiega su Attività (se attiva) o Tools, stessa logica di
  `setAttivitaStatisticheAttive`. `ToolsScreen` nasconde la card Piano
  turni dalla lista quando è in navbar (sarebbe un accesso duplicato alla
  stessa schermata) — controllo indipendente da Tools attivi
  (`ToolsProvider`): un utente può tenere il tool "attivo" ma visibile solo
  in navbar, i due switch non si escludono a vicenda di proposito. Le
  funzioni di (de)serializzazione della pagina principale sono centralizzate
  in `_paginaAStringa`/`_paginaDaStringa` (`app_provider.dart`) invece di
  ripetere lo switch in ogni metodo: con tre valori possibili invece di due
  la codifica manuale sparsa sarebbe stata più facile da disallineare.
- **Tutorial di navigazione a schermo intero** (`widgets/tutorial_overlay.dart`,
  `TutorialProvider` in `app_provider.dart`): con la navigazione ormai
  configurabile in più modi (tab disattivabili, Piano turni spostabile in
  navbar), un nuovo utente rischia di non capire subito cosa c'è dietro
  ogni voce della `NavigationBar` — un overlay "a spotlight" evidenzia in
  sequenza ogni tab attualmente visibile con una card di spiegazione,
  mostrato in automatico una sola volta al primo avvio e rivedibile in
  qualsiasi momento dal pulsante "Rivedi il tutorial di navigazione" in
  Impostazioni → Navigazione.
  - **Nessun package** (`avviaTutorial` in `tutorial_overlay.dart`), stessa
    scelta "niente dipendenza per poco codice" del calendario mensile: un
    solo `OverlayEntry` con `CustomPainter` (`Path.combine` con
    `PathOperation.difference` per ritagliare il "buco" nello scrim scuro)
    e un `Completer` per restituire il controllo a chi ha avviato il
    tutorial una volta finito o saltato.
  - **Aree evidenziate calcolate dividendo la larghezza della
    `NavigationBar` per il numero di tab**, non con una `GlobalKey` per
    singola icona: `NavigationDestination` anima internamente una coppia
    `icon`/`selectedIcon` sovrapposta per la transizione Material 3, quindi
    due chiavi sullo stesso slot avrebbero rischiato un conflitto — una
    sola `GlobalKey` sul widget `NavigationBar` stesso, con un conto
    aritmetico sulla sua `RenderBox`, è più robusto e molto meno codice.
  - **Piano turni ha 3 passi invece di 1** (`_descrizioneTutorial` in
    `app_navigator.dart` restituisce una `List<String>`, non una singola
    stringa): è il tool più complesso dell'app, un solo passo avrebbe dovuto
    scegliere tra un testo generico ("c'è un calendario con dei buchi") o un
    unico paragrafo troppo lungo per una card. I passi extra condividono
    area e titolo del passo singolo degli altri tab (cambia solo la
    descrizione) e coprono: da dove arriva il foglio (sync automatica dal
    backend), il significato dei pallini per fascia e il tap per il
    dettaglio equipaggi, e la ricerca per nome col segnalino sul calendario.
  - **`TutorialProvider` condiviso** (stesso motivo di `ToolsProvider`/
    `NavigazioneProvider`): il pulsante di replay vive in
    `ImpostazioniScreen`, ma solo `AppNavigator` ha la `NavigationBar` reale
    da cui calcolare le aree — le due schermate restano entrambe montate
    nell'`IndexedStack`, quindi serve stato condiviso perché un tap
    nell'una faccia scattare l'overlay nell'altra. `richiesta` è un
    contatore incrementale (non un bool): sia il primo avvio mai completato
    (`carica()`) sia un replay esplicito (`richiediReplay()`) lo
    incrementano, e `AppNavigator` reagisce al *cambiamento* di valore, non
    al suo stato assoluto — altrimenti un tutorial già "vero" non
    ripartirebbe più al tap su "Rivedi". `kPrefTutorialCompletato` non è
    nel backup (come `kPrefPianoTurniUltimoMese`): è stato locale al
    device, e su un device nuovo ripristinato da un backup ha senso
    rivedere comunque il tutorial.
- **Permesso INTERNET nel manifest Android (v1.3.1)**: le build debug lo
  includono automaticamente, le release no — il Piano turni (prima feature di
  rete su main) falliva con "Failed host lookup" solo sull'APK release.
  Stessa lezione del PRAGMA WAL: i bug di piattaforma vanno verificati con
  una build release su Android reale, non solo in debug/desktop.
- **Vista calendario custom, nessun package** (`widgets/calendario_mensile.dart`):
  serve solo una griglia mese con marker colorati (pallini per associazione) e
  l'elenco del giorno selezionato — table_calendar & co. non giustificano la
  dipendenza (stessa politica di byId* vs package collection). Nomi di mesi e
  giorni hardcoded in italiano: tutte le stringhe di questo widget sono già
  fisse in italiano indipendentemente da `flutter_localizations` (aggiunta
  poi solo per i widget Material nativi, vedi bullet dedicato più sotto). Il
  giorno selezionato è stato della
  lista (non del calendario) perché il FAB lo usa per precompilare
  `dataIniziale` del form; la vista scelta (lista/calendario) persiste in
  shared_preferences, con chiave separata per turni e assistenze. La ricerca
  testuale resta solo in vista lista: un risultato sparso su più mesi non ha
  una rappresentazione utile a calendario. Nato come `CalendarioTurni`, reso
  generico (`CalendarioMensile<T>` con callback dataIso/colore/itemBuilder)
  quando calendario e ricerca sono stati estesi alle assistenze: `Turno` e
  `Assistenza` sono classi diverse e duplicare la griglia era peggio di tre
  callback. Per i pallini `getAssistenze` ora denormalizza anche
  `associazione_colore` (nuovo campo `Assistenza.associazioneColore`, escluso
  da toMap come `associazioneNome`) e supporta `ricerca` su descrizione/note.
- **Icona filtro col colore dell'associazione filtrata** (liste turni e
  assistenze, quindi anche vista calendario che ne condivide l'AppBar):
  mostra *quale* filtro è attivo riusando il colore già assegnato
  all'associazione, con kPrimary come fallback se non ne ha uno.
- **Eliminazione solo dal cestino nel dettaglio**: rimossi swipe e long-press
  dalle liste turni/assistenze — ridondanti col cestino già nell'AppBar del
  dettaglio, e più a rischio di cancellazione accidentale.
- **Equipaggio 1ª/2ª parte affiancate nel dettaglio** (`_EquipaggioCard`,
  duplicata in `turno_detail.dart`/`assistenza_detail.dart` perché `Turno`
  e `Assistenza` sono classi diverse): riga per ruolo con i due nomi
  affiancati quando c'è un 2° equipaggio, invece di due blocchi impilati.
  Con un solo equipaggio resta l'elenco singolo. Solo la visualizzazione:
  il form resta con le due sezioni sequenziali.
- **Export JSON leggibile esteso alle assistenze**: `exportSemplificato()`
  produce anche `{'assistenze': [...]}` (stessa risoluzione nomi dei turni,
  senza tipologie/servizi che la tabella non ha).
- **Nomi file con timestamp leggibile** (`_timestampFile()`): `AAAAMMGG_HH_MM`
  al posto dei millisecondi epoch, illeggibili per l'utente.
- **`StatisticheProvider`**: le statistiche non si aggiornavano dopo un import
  perché `StatisticheScreen` caricava i dati una volta in stato locale, mai
  invalidato — e `IndexedStack` in `AppNavigator` tiene tutte le tab montate,
  quindi cambiare tab non la ricostruiva. Estratto un provider con lo stesso
  pattern `carica`/`ricarica` degli altri; `ImpostazioniScreen._import()` lo
  ricarica. Stesso motivo, stesso bug si ripresentava per ogni turno/servizio/
  assistenza creato, modificato o eliminato dalla tab Attività: `ricarica()`
  di `StatisticheProvider` mancava nei punti dove `TurniList`/`AssistenzeList`
  già ricaricano il proprio provider dopo essere tornate da `TurnoForm`/
  `TurnoDetail`/`AssistenzaForm`/`AssistenzaDetail` (`_apriDettaglio`,
  `_nuovoTurno`/`_nuovaAssistenza`) — aggiunto lì, stesso punto, stesso pattern.
- **Note in markdown, editor a schermo intero**: renderizzate con
  `flutter_markdown_plus` (l'ufficiale `flutter_markdown` è `discontinued` su
  pub.dev). `NotaMarkdown` (in `widgets/`) definisce uno style sheet esplicito
  perché i colori di default sono pensati per sfondo chiaro. Il vecchio
  dialog piccolo è sostituito da `NoteEditorScreen` (`screens/shared/`,
  condivisa turno/assistenza): scomodo scrivere/scorrere markdown multi-riga
  in poche righe. Nessuna barra di formattazione né anteprima (minimale). Il
  salvataggio passa da `toMap`/`fromMap`, non `copyWith`, che non può
  riportare `note` a `null` quando il campo si svuota.
- **Descrizione dei servizi in markdown**: stessa estensione a `Servizio.descrizione`
  (`NotaMarkdown` con `fontSize`/`color` opzionali per lo stile compatto già
  in `_ServizioCard`). Il campo nel form riempie lo spazio libero sotto gli
  altri campi con `CustomScrollView` + `SliverFillRemaining` (non `Column` +
  `Expanded`, che andava in overflow quando la tastiera riduce lo spazio e i
  campi sopra non ci stanno più — con lo sliver l'intera schermata scrolla invece).
- **`byId*` con try/catch**: evita `firstWhereOrNull` (richiederebbe il package `collection`).
- **Combobox `RawAutocomplete`** (`PersonaPicker`/`OspedalePicker`): controller/focus
  esterni, voce "Aggiungi..." per creazione inline; l'update dopo creazione
  passa da `didUpdateWidget`+`addPostFrameCallback` per non toccare il
  controller durante il build.
- **`PRAGMA foreign_keys = OFF` fuori dalla transazione nell'import**: dentro
  una transazione è un no-op silenzioso in SQLite. Le righe che falliscono
  l'insert non sono più scartate in silenzio: contate e segnalate nel messaggio finale.
- **`num_servizi` escluso dall'UPDATE in `saveTurno`**: è gestito solo da
  `_aggiornaNumServizi()`; includerlo lo azzererebbe a ogni modifica del turno.
- **`saveTurno`/`saveAssistenza` rinumerano anche l'associazione di provenienza**:
  se si sposta un turno su un'altra associazione, quella vecchia va rinumerata
  anche lei (altrimenti resta un buco); batch atomico invece di N update.
- **`TurnoCard` estratta in `widgets/`**: da classe privata di `turni_list.dart`
  a pubblica, condivisa anche da `turni_filtrati_screen.dart`.
- **Turni/assistenze per persona via OR sui 10 campi equipaggio**: niente
  tabella ponte persona↔turno (eredità dello schema RN).
- **Turni per ospedale via INNER JOIN + DISTINCT** su `servizi.ospedale_id`
  (DISTINCT evita duplicati con più servizi nello stesso ospedale).
- **Ricerca testuale in `getTurni`**: JOIN+DISTINCT su `servizi` solo se
  `ricerca` è valorizzata (altrimenti overhead/duplicati inutili). Debounce 300ms.
- **`PRAGMA journal_mode = WAL` in `_onOpen`, con `rawQuery`**: in `_schema`
  causava schermata nera su Android reale — SQLite rifiuta il passaggio a WAL
  dentro la transazione implicita di `_onCreate`/`_onUpgrade`, e su Android
  `execute()` mappa a `execSQL()` che rifiuta query coi risultati. Invisibile
  su desktop (sqflite_common_ffi), solo su Android reale.
- **Icona app con `flutter_launcher_icons`**: sorgenti in `assets/icon/`
  (verde pieno per Windows/legacy Android, trasparente per l'adaptive
  foreground). Rigenerare con `dart run flutter_launcher_icons` dopo aver
  cambiato le sorgenti.
- **CI Android in `ghcr.io/cirruslabs/flutter:3.44.0`**: elimina i ~10 min di
  setup Flutter/SDK a ogni run su runner effimero (dettagli e motivazioni nei
  commenti in testa a `build-android.yml`, per non duplicarli qui).
- **Pubblicazione web: un'unica immagine Docker (nginx + backend Go)**
  (`Dockerfile` alla radice + `.github/workflows/build-web.yml`): build
  multi-stage, stage 1 `ghcr.io/cirruslabs/flutter:3.44.0` (stessa immagine
  pinnata della CI Android, include già il setup di
  `sqflite_common_ffi_web:setup` non versionato) compila `flutter build web
  --release`; stage 2 `golang:1.25-alpine` compila il backend di `backend/`
  in un binario statico (`CGO_ENABLED=0`); stage 3 `nginx:alpine` copia
  l'output statico Flutter, il binario e la cartella `public/` del backend,
  `nginx.conf` e `docker-entrypoint.sh` — nell'immagine finale non c'è
  toolchain Flutter né Go. `docker-entrypoint.sh` avvia il backend in
  sottofondo e nginx in primo piano (`exec nginx -g 'daemon off;'`, PID 1,
  riceve i segnali di `docker stop`): se il backend fallisce l'avvio (es.
  `DATABASE_URL` non configurato) nginx continua comunque a servire i file
  statici, solo `/api/*` risponde con errore — verificato lanciando
  l'immagine senza Postgres raggiungibile. `nginx.conf` fa anche da reverse
  proxy: `/api/` → backend su `/api/` (**pass-through, nessun prefisso
  tolto** — le rotte Go vivono sotto `/api/` anche quando il backend gira
  da solo senza nginx davanti, vedi bullet sotto sul perché), `/admin/` →
  backend su `/admin/` (pagina di gestione ospedali, percorso diretto per
  un URL più corto). Pubblicata sul GitHub Container Registry
  (`ghcr.io/<owner>/ambuturni-web`), push col `GITHUB_TOKEN` automatico del
  workflow, nessun secret PAT da gestire (migrato da Gitea il 2026-08-12,
  vedi bullet dedicato più sotto). Trigger sui tag
  `vX.Y.Z` (come `build-android.yml`, non a ogni push su `main`: la web app
  segue lo stesso versionamento dell'APK — questo ora vale anche per il
  backend, che non ha più un versionamento/trigger proprio), immagine
  taggata sia `latest`/SHA sia col nome del tag. Deploy sul server manuale
  — il workflow si ferma al push dell'immagine; la configurazione del
  backend (`DATABASE_URL`, `JWT_SECRET`, `ADMIN_USERNAME`/`PASSWORD`, vedi
  `backend/.env.example`) va passata come variabili d'ambiente al container
  in produzione. `nginx.conf`: fallback SPA (`try_files` su `index.html`) e
  `Cache-Control: no-cache` su tutti i file statici (il browser tiene la
  copia ma la rivalida a ogni uso via ETag/304) — vedi il bullet dedicato
  sotto sul perché nessuna cache lunga è sicura per una build Flutter web.
- **Web che non si aggiornava dopo i deploy: colpa della cache `immutable`
  in nginx**: la prima versione di `nginx.conf` metteva `expires 30d` +
  `Cache-Control: public, immutable` su tutti i `.js`/`.wasm`/immagini,
  nell'assunzione (sbagliata) che Flutter generasse nomi file con hash.
  Flutter web invece NON versiona i nomi: `main.dart.js`,
  `flutter_bootstrap.js`, `flutter.js`, `sqflite_sw.js`, `sqlite3.wasm`,
  `assets/*` si chiamano uguali a ogni build. Con `immutable` il browser non
  rivalidava per 30 giorni il vecchio `flutter_bootstrap.js`, che contiene la
  versione del service worker (registrato come
  `flutter_service_worker.js?v=...`): il vecchio bootstrap ri-registrava il
  vecchio service worker, che serviva l'intera vecchia app dalla sua cache —
  e anche senza service worker il vecchio `main.dart.js` sarebbe rimasto
  comunque in cache un mese. Per questo dopo un deploy l'app spesso restava
  alla versione precedente finché non si faceva un hard-refresh. Fix:
  `no-cache` su tutto lo statico (dentro `location /`, niente più blocco
  regex): a ogni accesso il browser rivalida con richieste condizionali
  (304 se invariato, costo minimo) e scarica solo i file cambiati; col
  bootstrap fresco, `flutter.js` vede la nuova versione del service worker,
  la installa e carica l'app aggiornata. I nomi non-hashati sono un limite
  di Flutter web, non di questa config: se in futuro la build generasse
  asset fingerprinted, solo allora avrebbe senso reintrodurre una cache lunga.
- **Backend riscritto da zero in Go: da "sync generico" a "elenco condiviso
  ospedali"** (`backend/`, v10 lato client): il vecchio backend Node+Express
  (`ambulanza-sync`, tabelle generiche `users`/`records`, endpoint
  `/sync/push`+`/sync/pull` last-write-wins) sincronizzava l'intero DB
  dell'app, ma quella sincronizzazione non è mai stata completata lato
  client — nessuna chiamata la usava davvero, era solo schema scaffolding
  (`sync_meta`/`deletions`, rimosse in v10 — le colonne `is_synced` sulle
  altre tabelle restano invece: erano scritte/lette solo da quel
  meccanismo mai nato, ma toglierle ricostruirebbe ogni tabella per un
  beneficio nullo) e un TODO mai chiuso. Il backup
  JSON locale (Impostazioni → Backup/Ripristino, `db/backup.dart`) resta
  l'unico modo per spostare i dati tra device: **non è stato toccato**,
  scelta deliberata (rimuovere anche quello avrebbe lasciato l'utente senza
  alcuna rete di sicurezza per i dati). Il nuovo backend fa una cosa sola:
  espone un elenco ospedali condiviso (nome/via/città/coordinate) scaricabile
  per città, con una pagina admin per aggiungerli — non conosce affatto lo
  schema turni/persone/associazioni dell'app.
  - **Perché Go**: richiesta esplicita, oltre a essere già lo stack del
    gestionale Magazzino Verde (progetto separato dello stesso utente,
    stessa istanza Gitea) — coerenza tra i propri servizi. Libreria standard
    `net/http` con `ServeMux` (pattern `"GET /api/ospedali"`, `r.PathValue`,
    disponibili da Go 1.22): nessun framework HTTP, un'API di 6 endpoint non
    lo giustifica. `github.com/jackc/pgx/v5` per Postgres,
    `github.com/golang-jwt/jwt/v5` + `golang.org/x/crypto/bcrypt` per
    l'auth della pagina admin (stesso meccanismo username/password + JWT del
    vecchio backend, incluso il bootstrap dell'utente admin da
    `ADMIN_USERNAME`/`ADMIN_PASSWORD` al primo avvio), `google/uuid` per gli
    id — nessuna dipendenza evitabile con poche righe (CORS incluso, header
    manuali in `httputil.go`). `go.mod` dichiara `go 1.25` (imposto da
    `go mod tidy` in base alle dipendenze, non da preferenza): l'immagine
    builder è pinnata di conseguenza (`golang:1.25-alpine`).
  - **Tutte le rotte API vivono sotto `/api/`, PERMANENTEMENTE** (non solo
    dietro nginx in produzione): bug reale scoperto testando il backend
    standalone in locale, come da `backend/README.md`. Prima le rotte Go
    erano a livello radice (`/health`, `/ospedali`...) e `nginx.conf`
    toglieva il prefisso `/api/` inoltrando al backend — corretto in
    produzione, ma il client (`utils/backend_api.dart`) chiama sempre
    `$baseUrl/api/...` **anche** quando `baseUrl` punta al backend standalone
    (`go run .`/`docker compose` in `backend/`, senza nginx davanti): lì
    nessuna rotta rispondeva su `/api/health`, quindi `verificaConnessione`
    e ogni chiamata fallivano sempre, indipendentemente dall'indirizzo
    scritto dall'utente nel dialog di configurazione. Fix: le rotte Go sono
    ora registrate direttamente come `/api/health`, `/api/ospedali`, ecc.
    (solo `/admin/` resta a parte), e `nginx.conf` fa un puro pass-through
    (`proxy_pass http://127.0.0.1:3000;` senza path finale = nginx inoltra
    l'URI originale invariato, invece del precedente `.../;` che tagliava il
    prefisso) — stesso path funzionante sia in locale sia in produzione.
  - **Endpoint**: `GET /api/ospedali?citta=` pubblico (nessuna chiave: è
    quello che chiama l'app, filtro case-insensitive per match esatto,
    citta assente → tutto l'elenco) — `POST /api/ospedali`/`PUT
    /api/ospedali/:id`/`DELETE /api/ospedali/:id` protetti da JWT (solo la
    pagina admin). Risposta nello stesso formato nome/via/citta/lat/lng di
    `exportOspedali`/`importOspedali` lato client: un client può fare
    l'upsert per nome sulla risposta senza trasformazioni.
    `GET /api/citta` (pubblica anche lei): le città che hanno almeno un
    ospedale, `DISTINCT ON (lower(citta))` invece di un DISTINCT semplice —
    altrimenti "Milano"/"milano" inserite con maiuscole diverse dalla pagina
    admin comparirebbero come due voci, mentre `listOspedali` le tratta già
    come la stessa città (match case-insensitive). Usata dal client per far
    scegliere la città da un elenco invece di farla digitare alla cieca.
  - **Pagina admin** (`backend/public/admin/index.html`): HTML+JS vanilla
    servito come file statico da Go (`http.FileServer`), nessun framework
    frontend per una form di login + tabella + aggiungi/modifica/elimina.
    Token JWT in `sessionStorage` (sopravvive a un refresh della scheda,
    sparisce chiudendola). lat/lng inviate come numero JSON (`Number(...)`),
    non stringa: la decodifica JSON di Go in `*float64` è rigorosa sul tipo,
    a differenza del parsing permissivo che aveva il vecchio backend Node.
  - **Modifica e filtro nella pagina admin**: il pulsante "Modifica" di una
    riga precompila lo stesso form dell'aggiunta (`modificaForm`) invece di
    aprirne uno separato — una variabile `editingId` (null = modalità
    aggiungi) decide se `salva()` fa POST o `PUT /api/ospedali/:id`, col
    titolo/testo del pulsante aggiornati di conseguenza e un "Annulla
    modifica" per tornare alla modalità aggiungi senza salvare. `nome` non
    ha UNIQUE (vedi sopra), quindi la modifica è per `id`, non per nome: a
    differenza dell'import massivo, qui non serve upsert perché si parte
    sempre da una riga già esistente in tabella. Il campo di ricerca sopra
    l'elenco filtra lato client (`filtraTabella`, su nome/via/città) l'intero
    elenco già scaricato — niente nuove chiamate API a ogni carattere
    digitato, la lista degli ospedali condivisi è piccola.
  - **Import massivo da file** (`POST /api/ospedali/import`, pulsante
    "Importa da file" nella pagina admin): oltre al form di aggiunta singola,
    carica un intero file JSON e fa l'upsert per nome di tutte le righe in
    un'unica transazione (`upsertOspedali` lato Go in `ospedali.go`, stessa
    logica — e stesso scopo, bulk import — della funzione omonima lato
    client in `db/helpers.dart`). Accetta sia un array puro sia
    `{"ospedali": [...]}`: è lo stesso formato che l'app esporta da
    Impostazioni → Ospedali → Esporta, quindi un'associazione può esportare
    la propria anagrafica ospedali e un admin importarla nel backend
    condiviso senza alcuna trasformazione. `nome` non ha un vincolo UNIQUE
    nello schema (scelta di semplicità: l'unico scrittore era finora
    `createOspedale` una riga alla volta) — l'upsert quindi fa una `SELECT`
    di tutti gli id per nome prima del giro di `INSERT`/`UPDATE`, non un
    `INSERT ... ON CONFLICT`. Il file si inoltra al backend come testo grezzo
    (`file.text()` poi `body: testo`), senza riparsarlo/ristringificarlo in
    JS: è già JSON valido, non c'è motivo di decodificarlo e ricodificarlo
    nel browser. Testato via curl con array puro, formato wrapper,
    aggiornamento di un nome già presente, righe senza nome (scartate senza
    interrompere le altre) e corpo malformato (400).
  - **Docker locale vs produzione**: `backend/Dockerfile` +
    `docker-compose.yml` (backend Go + Postgres, `build: .` invece di tirare
    un'immagine da un registry) servono solo per sviluppare/testare il
    backend da solo, verificato end-to-end con `docker compose up --build`
    + curl (health, login, CRUD ospedali, filtro città, protezione JWT). In
    produzione questo codice **non gira da un'immagine propria**: è
    compilato dentro l'immagine web (vedi bullet sopra) — `build-backend.yml`
    è stato rimosso, `docker-compose.yml` non usa più `SYNC_IMAGE`.
  - **Client: indirizzo del backend configurabile, con un default
    condiviso** (`kPrefBackendUrl`/`kBackendUrlDefault` in
    `utils/prefs_keys.dart`, `https://ambuturni.maratuck.com/`): un'unica
    istanza gestita centralmente, quindi il tool funziona da subito senza
    configurazione. Il dialog di
    configurazione (`_ConfigServerDialog`, in `impostazioni_screen.dart` —
    vedi bullet sotto sullo spostamento) **verifica prima di salvare**: il
    pulsante principale chiama `BackendApi.verificaConnessione` (GET
    `/api/health`, non lancia mai eccezioni, timeout più corto — 8s — delle
    altre chiamate perché qui l'utente aspetta in un dialog) e solo se
    risponde salva; se fallisce mostra l'errore e il pulsante diventa "Salva
    comunque" (un secondo tap forza il salvataggio: il server potrebbe
    essere solo temporaneamente giù, non deve bloccare per forza — ma
    modificare di nuovo il testo dell'indirizzo fa ripartire da capo la
    verifica, non si "eredita" un bypass per un URL diverso).
    Il pulsante "Scarica ospedali" in Lista ospedali fa scegliere città o
    regione da un elenco (`_SceltaLuogoDialog`, `SegmentedButton` in cima per
    passare da `BackendApi.getCitta` a `getRegioni` — vedi bullet "Regione"
    sotto) invece di far digitare alla cieca — se il download dell'elenco
    fallisce resta comunque un campo libero come ripiego, il download vero
    (`GET /api/ospedali?citta=|regione=`) potrebbe funzionare anche senza
    quell'elenco. Scelto il luogo, scarica e fa l'upsert con la stessa
    funzione condivisa dell'import di backup (`upsertOspedali` in
    `db/helpers.dart`, estratta da lì per questo riuso — stessa logica, due
    sorgenti diverse: file JSON o rete). `BackendApi` (`utils/backend_api.dart`)
    è Dart puro e testato con `MockClient`.
  - **Configurazione del backend spostata in Impostazioni**: l'indirizzo
    del server viveva dietro l'icona ingranaggio di
    Lista ospedali, ma non è specifico di quel tool (lo riusano anche Piano
    turni e Materiali usati per fogli/materiali condivisi, vedi bullet
    sotto) — spostato in una nuova sezione collassabile "Backend condiviso"
    (`_SezioneBackendCondiviso` in `impostazioni_screen.dart`, stesso
    pattern collassato-di-default di Tools attivi), insieme a
    `_ConfigServerDialog` (portata lì di peso). Il download "per città/
    regione" resta invece in Lista ospedali: è contestuale a quella
    schermata, non una configurazione. `_SezioneOspedali`/altre schermate
    leggono comunque `kPrefBackendUrl` direttamente da SharedPreferences,
    non serve un provider condiviso (letto raramente, non a ogni frame).
  - **Regione: raggruppamento Lista ospedali + download per regione**:
    `Ospedale.regione` (v11, colonna nullable come lat/lng) si
    popola allo stesso modo delle coordinate — geocoding automatico
    (`GeocodingApi.geocodifica` ora chiama Nominatim con `addressdetails=1`
    e legge `address.state`, che per un indirizzo italiano è la regione) o
    inserimento manuale nel form Ospedale, con la stessa regola di priorità
    già in uso per lat/lng: se l'utente compila anche solo uno tra
    lat/lng/regione a mano, il geocoding automatico viene saltato del tutto
    (esteso da "solo lat/lng" a includere la regione, comportamento più
    prevedibile che aggiornare i singoli campi con priorità diverse). La
    funzione che scrive questi campi è stata rinominata da
    `aggiornaCoordinateOspedale` a **`aggiornaGeocodingOspedale`**, con lat/
    lng/regione tutti opzionali (si scrive solo ciò che viene passato — un
    aggiornamento parziale, es. solo regione da un `upsertOspedali`, non
    azzera le coordinate già presenti). Lista ospedali raggruppa la vista
    elenco per regione (intestazioni di sezione inline in una `ListView`,
    stessa filosofia "niente package" del calendario mensile — ordine
    alfabetico con un bucket "Senza regione" sempre in fondo) e il pulsante
    "Scarica ospedali" offre "Per città"/"Per regione" nello stesso dialog
    (vedi bullet sopra). Lato backend: colonna `ospedali.regione`
    (`ALTER TABLE ... ADD COLUMN IF NOT EXISTS`, niente sistema di
    migrazioni lì — un solo campo non lo giustifica), `GET /api/regioni`
    gemella di `/api/citta` (stesso `DISTINCT ON (lower(...))`), filtro
    `?regione=` su `GET /api/ospedali` con priorità a `?citta=` se entrambi
    passati (nessun caso d'uso per l'AND). Pagina admin: campo Regione nel
    form e colonna in tabella, incluso nella ricerca lato client.
  - **Fogli turni sul backend, sincronizzati automaticamente**: nuova
    tabella `fogli_turni` (`chiave` "aaaa-mm" PRIMARY KEY, `url`) con
    lo stesso schema di fiducia di `/api/ospedali` — lettura pubblica
    (`GET /api/fogli`), scrittura solo da admin (`POST`/`DELETE`, pagina
    admin: card dedicata con form chiave+link e tabella). Nessuna scrittura
    dal client: l'app non ha alcun login (solo la pagina admin ce l'ha),
    quindi il client può solo scaricare, mai proporre un link al backend.
    Lato client, `PianoTurniScreen._sincronizzaFogliDalBackend` (chiamata
    da `_ripristinaPreferenze`, quindi a ogni apertura del tool) scarica
    `BackendApi.getFogli()` e fa un **merge additivo** nell'archivio locale
    (`kPrefPianoTurniFogli`): aggiunge solo le chiavi assenti, senza mai
    sovrascrivere un link che l'utente ha già incollato/verificato per quel
    mese — un aggiornamento silenzioso di un URL già in uso sarebbe più
    sorprendente che utile. Attivo di default (`kPrefSyncFogliAttivo`,
    assente = true) con uno `SwitchListTile` in Impostazioni → Backend
    condiviso; come il geocoding, è best-effort e silenzioso (nessun errore
    in UI, un backend vecchio senza l'endpoint o irraggiungibile non deve
    disturbare l'apertura dello strumento).
  - **Catalogo materiali sul backend**: stesso schema pubblico-
    lettura/admin-scrittura di ospedali/fogli, tabella `materiali(id, nome)`
    lato server (solo il nome: quantità/posizione sono per-device, il
    backend condivide solo l'anagrafica per popolare un catalogo su un
    device nuovo). `POST /api/materiali/import` mirror di
    `/api/ospedali/import` (upsert per nome, array puro o
    `{"materiali":[...]}`). Lato client, `upsertMateriali` in
    `db/helpers.dart` (match case-insensitive come il `MaterialePicker`,
    nessun aggiornamento sui match — un materiale ha solo il nome) e un
    pulsante "Scarica dal backend condiviso" nell'AppBar di
    `materiali_screen.dart`, duplicato identico (stessa funzione, stesso
    upsert) anche in `materiali_usati_screen.dart`: è la schermata usata
    più spesso durante il turno, prima per aggiornare il catalogo (es. un
    materiale nuovo aggiunto da un altro volontario) bisognava passare da
    "Gestisci materiali" solo per farlo comparire nel `MaterialePicker` del
    form di utilizzo. Lì non ricarica la lista utilizzi dopo il download
    (a differenza di `materiali_screen.dart`): il sync tocca solo il
    catalogo dei nomi, non gli utilizzi già registrati mostrati in quella
    schermata.
  - **Pagina admin ridisegnata (2026-07-20)**: era un'unica pagina con tutte
    le sezioni impilate (login, form ospedale, import, tabella ospedali,
    fogli, materiali) — sempre più lunga da scorrere man mano che si
    aggiungevano sezioni, e la sezione "Utenti" non è mai esistita in UI
    nonostante `GET`/`POST`/`DELETE /api/auth/users` esistano lato backend
    (creabili solo via `curl`). Restano HTML+JS vanilla, nessun framework
    (stessa scelta di sempre per una form di poche schermate) ma:
    **navigazione a tab** (Ospedali/Fogli turni/Materiali/Utenti, sola CSS
    `display` toggle — i dati di tutte le sezioni si caricano insieme in
    `carica()` come prima, cambiare tab non fa nuove richieste); **nuova
    sezione Utenti** (crea/elenca/elimina, usa gli endpoint già esistenti;
    l'errore "non è possibile eliminare l'unico utente admin rimasto" del
    backend arriva già leggibile); **stati vuoto/caricamento** nelle tabelle
    (`renderTabellaGenerica`, condivisa dalle quattro sezioni) invece di una
    tabella bianca senza spiegazione; **toast di conferma** per le azioni
    riuscite (`toast()`, si autodistruggono dopo ~3s) — prima solo gli
    errori avevano un feedback, un salvataggio ok si vedeva solo dal form
    che si svuotava; **login con Enter** (form vero invece di un
    `onclick` sul pulsante). Verificato end-to-end con
    `docker compose up --build` + `curl` replicando le stesse chiamate che
    fa la pagina (login, CRUD ospedali, CRUD utenti incluso il rifiuto di
    eliminare l'ultimo, validazione mese/URL dei fogli) e controllo statico
    di sintassi JS/bilanciamento tag/funzioni `onclick` referenziate — non
    un click-through reale nel browser (nessun modo di interagire con una
    GUI da qui).
  - **Export/import per ospedali, fogli turni e materiali (2026-07-20)**:
    ospedali aveva già l'import (upsert per nome, `POST /api/ospedali/import`)
    ma non l'export; fogli turni e materiali non avevano né l'uno né l'altro
    dalla pagina admin — solo un form "una riga alla volta". L'**export è
    puramente client-side**: nessun nuovo endpoint serve, i dati sono già in
    `ospedaliCache`/`fogliCache`/`materialiCache` (le stesse variabili che
    riempiono le tabelle) — `scaricaJson()` li scarica come file `.json` via
    Blob + `<a download>`, senza passare dal server. Ogni categoria esporta
    lo stesso formato che il suo endpoint di import si aspetta (array o
    `{"chiave": [...]}`), quindi un file esportato da qui si reimporta qui,
    su un'altra istanza, o — per ospedali — dall'app stessa (stesso formato
    di `exportOspedali`/`importOspedali` lato client). Per **materiali**
    l'import lato backend esisteva già (`POST /api/materiali/import`, mai
    esposto in UI); per **fogli turni** mancava anche lato backend: aggiunta
    `upsertFogli` in `fogli.go` (stessa struttura di
    `upsertOspedali`/`upsertMateriali`, upsert per chiave dentro una
    transazione) e `POST /api/fogli/import`, con le stesse validazioni già
    in vigore per il form singolo (mese 01-12, url http/https — righe non
    valide scartate e contate, non bloccano l'intero import). I tre flussi
    di import condividono `importaFileGenerico()` lato pagina admin
    (endpoint/elemento errore/funzione di ricarica come parametri) invece di
    triplicare la stessa logica fetch-e-mostra-esito. Verificato con
    `docker compose` + `curl`: import con wrapper e con array puro, righe
    scartate per formato invalido, upsert (stessa chiave reimportata con url
    diverso → aggiornata non duplicata).
  - **Repository formazione**: un solo link condiviso (non una collezione)
    ai materiali di formazione dell'associazione — a differenza di
    ospedali/fogli/materiali non serve un elenco, solo "qual è il link
    attuale". Tabella `repository_formazione` con una riga singola forzata
    da `CHECK (id = 1)` (stesso idioma Postgres usato altrove per un
    singleton, invece di una tabella chiave-valore generica: nessun altro
    caso d'uso oggi la giustificherebbe). `GET /api/repository-formazione`
    pubblica (restituisce `url` vuoto se non ancora configurato, non un
    errore: è uno stato legittimo prima del primo salvataggio admin),
    `POST` protetta con la stessa validazione schema http(s) già in uso per
    i fogli turni. Pagina admin: nuova scheda "Formazione", un form a un
    solo campo che si precompila col link già salvato (upsert, non
    creazione). Lato client, tool "Repository formazione"
    (`repository_formazione_screen.dart`): **non un redirect invisibile**
    — apre il browser in automatico al primo caricamento riuscito (una sola
    volta, `_apertoAutomaticamente`, altrimenti un "Riprova" dopo un errore
    di rete riaprirebbe il browser una seconda volta senza che l'utente
    l'abbia chiesto) ma resta una schermata con stato vero: messaggio
    dedicato se il link non è ancora configurato, messaggio con "Riprova"
    se il server non risponde, pulsante "Apri di nuovo" altrimenti — così
    chi nega il popup del browser o lo chiude per sbaglio non resta bloccato
    su una schermata bianca senza spiegazione.
  - **Piano turni → pulsante "Apri il foglio nel browser"**: apre col
    browser esterno (`url_launcher`, già una dipendenza per Lista ospedali)
    il link del foglio Google così come incollato dall'utente (`_urlCtrl`),
    non l'endpoint `export?format=xlsx` usato internamente per scaricare i
    dati — quel link porta a un file, non alla pagina del foglio.
  - **Nessuno scoping multi-associazione sul backend**: ospedali, fogli
    turni, materiali e il link di formazione condividono lo stesso schema
    "un'unica istanza, tabella piatta" già scelto per gli ospedali — chi
    vuole dati isolati
    per la propria associazione fa girare la propria istanza del backend
    (indirizzo configurabile, vedi sopra) invece di condividere quella
    centralizzata di default. Se in futuro più associazioni dovessero
    condividere davvero la stessa istanza pubblica per fogli/materiali,
    servirebbe una chiave di scoping (non implementata: nessun caso d'uso
    reale oggi, aggiunta prematura).
- **`pubspec.lock` versionato**: raccomandazione Flutter per le app (non le
  librerie) — build riproducibili in CI. Gli step actions/cache (Gradle/pub)
  erano stati rimossi dal workflow perché, sulla vecchia istanza Gitea, senza
  un cache backend configurato facevano solo cache-miss silenziosi — non
  reintrodotti nella migrazione a GitHub Actions (2026-08-12, che invece un
  cache backend funzionante ce l'ha) perché il grosso del guadagno è già
  nell'immagine `cirruslabs/flutter` precompilata: possibile ottimizzazione
  futura, non fatta qui per non allargare la portata della migrazione.
- **Rinominata l'app "AmbuTurni"**: nome visibile e identificatori interni
  (package Dart `ambu_turni`, `applicationId` Android, CMake/Windows).
  **Eccezione deliberata**: il file SQLite resta `ambulanza_turni.db` — rinominarlo
  avrebbe fatto perdere l'accesso al DB già esistente sui device in uso.
  L'`applicationId` Android è cambiato: l'app installata con l'ID vecchio
  resta orfana (accettato esplicitamente).
- **`materiali_usati`: `quantita` INTEGER + `unita` TEXT** (non testo libero
  unico): permette i pulsanti +/- di modifica rapida.
- **Lezione v4→v5** (richiamata da regola 7): un edit in-place dello schema
  v4 senza bump di versione ha causato un crash su device che avevano già
  aperto l'app durante il test del branch (`onUpgrade` non scatta se
  `oldVersion == newVersion`). Ogni modifica a uno schema già rilasciato,
  anche solo aperto localmente, richiede bump + vera migrazione in `_onUpgrade`.
- **`posizione` con CHECK fisso** (`AMBULANZA`/`BOMBOLINO`/`ZAINO`): valori
  fissi, non un catalogo editabile (stesso pattern dei codici chiamata/uscita).
- **Nessuno storico materiali ripristinati (v5→v6)**: eliminato il soft-delete
  con flag `ripristinato`; ripristinare/eliminare ora è una DELETE vera.
- **Migrazioni consolidate nel solo `_onUpgrade` (v7)**: rimosso il vecchio
  `_runMigrations` idempotente (schema+ALTER a ogni apertura) — due sistemi
  paralleli erano l'origine della lezione v4→v5.
- **`CHECK (quantita >= 1)` (v7)**: prima solo un clamp in UI, non nel DB.
- **`materiale_id` con `ON DELETE CASCADE` (v6)**: eliminare un materiale
  elimina anche i suoi utilizzi, coerente con "nessuno storico".
- **Delete anagrafiche con conferma + messaggio su vincolo FK**: eliminare
  una voce ancora referenziata è bloccato dalle FK (voluto, a differenza dei
  materiali) ma prima falliva in silenzio; ora `_confermaEdElimina` intercetta
  l'errore FK e mostra un messaggio specifico.
- **Versione app in Impostazioni** (`_VersioneApp` in fondo alla schermata):
  letta a runtime con `package_info_plus` (`PackageInfo.fromPlatform()`)
  invece di duplicare la stringa a mano — riflette sempre `X.Y.Z+N` di
  quello che è stato davvero compilato, senza rischio di disallinearsi da
  `pubspec.yaml` a ogni release.
- **`MaterialeUsatoForm`: `createdAt` passato esplicitamente in modifica**:
  altrimenti l'UPDATE lo sovrascriverebbe a NULL.
- **`MaterialePicker` come catalogo con creazione inline**, non testo libero:
  evita doppioni incoerenti ("Garze" vs "garze").
- **`savePersona`/`saveOspedale`/`saveMateriale` restituiscono l'id**: i
  picker lo usano per l'auto-selezione, evitando ambiguità con gli omonimi.
- **Tools come 5° tab**, non sezione in Impostazioni: scala meglio per
  ospitare più strumenti in futuro.
- **Keystore di release**: PKCS12 in `%USERPROFILE%\keystores\`, letto da
  `android/key.properties` (gitignorato) se presente, altrimenti fallback
  debug. In CI arriva dai secret del repository GitHub
  `KEYSTORE_B64`/`KEYSTORE_PASSWORD`. Le release passate (v1.0.0, v1.1.0)
  sono state ri-firmate per uniformità: gli update via Obtainium richiedono
  la stessa firma tra versioni. **Rigenerato da zero il 2026-08-12** dopo la
  violazione del vecchio server Gitea (dove viveva come secret CI, quindi
  potenzialmente esposto): rottura deliberata della continuità di firma, chi
  ha già installato l'app deve disinstallare/reinstallare — vedi bullet
  sulla migrazione a GitHub Actions.
- **Piattaforma web** (`flutter create . --platforms web`): il blocco vero
  non era il target in sé ma tre dipendenze Android/desktop-only, trovate
  leggendo il codice prima di iniziare:
  - **DB**: `sqflite`/`sqflite_common_ffi` non esistono nel browser. Aggiunto
    `sqflite_common_ffi_web` (SQLite compilato in WASM, persistito in
    IndexedDB tramite un worker — binari generati con
    `dart run sqflite_common_ffi_web:setup` in `web/sqlite3.wasm` +
    `web/sqflite_sw.js`, non versionati, da rigenerare dopo un
    `flutter create`/clone pulito). `getDb()` sceglie `databaseFactoryFfiWeb`
    su `kIsWeb`. Due bug reali trovati solo lanciando l'app in Chrome (non da
    `flutter analyze`/`test`/`build web`, che passavano lo stesso):
    `getDatabasesPath()` lancia su questa implementazione ("getDatabasesPath
    is null") — su web si passa un nome fisso (`'ambulanza_turni.db'`) invece
    del path da `getDatabasesPath()`, che resta usato su Android/desktop;
    e la versione 0.4.x del pacchetto è troppo vecchia per la
    `sqflite_common` risolta da pub (compila ma va in eccezione a runtime,
    `Unsupported operation: unsupported result null`) — servita la 1.1.2,
    che a sua volta richiede `sqlite3 >=3.1.2`, incompatibile con
    `sqflite_common_ffi` 2.3.5 (import di `package:sqlite3/open.dart`,
    rimosso in sqlite3 3.x — errore di compilazione anche nativo, non solo
    web). Risolto con `sqflite_common_ffi: ^2.4.2` (aggiornato anche lui) +
    `sqlite3: ^3.1.2` pinnato esplicitamente. Lezione: per questa famiglia di
    pacchetti i vincoli in pubspec non bastano a garantire compatibilità
    runtime, serve lanciare l'app per davvero (coerente con la regola 8, qui
    estesa al web: browser reale, non solo `flutter analyze`).
  - **`dart:io` non condizionale = errore di compilazione sul target web**
    (non un'eccezione a runtime rimandabile): isolato dietro export
    condizionali (`if (dart.library.io)`) in tre punti — `database.dart`
    (branch `isDesktop`/`isMobile` per la scelta del `databaseFactory`, via
    `utils/platform_check.dart`), `db/backup.dart` (filesystem/file_picker/
    share_plus spostati in `db/backup_file_io.dart` vs `db/backup_file_web.dart`,
    riusata anche per l'export .ics del Piano turni, vedi sotto) e
    `utils/piano_cache.dart` (`piano_cache_io.dart`: file JSON per mese in
    directory di supporto; `piano_cache_web.dart`: stessa cache ma su
    `shared_preferences`/localStorage, path_provider non ha lì una directory
    persistente utilizzabile allo stesso modo).
  - **Backup su web**: `file_picker` non implementa `saveFile` nel browser
    (solo `pickFiles`, con `bytes` invece di un path reale). Export via
    `XFile.fromData` (bytes in memoria, nessun file scritto) passato a
    `share_plus`, che sul web tenta la Web Share API nativa e ricade da solo
    su un download via Blob URL se non disponibile (`downloadFallbackEnabled`,
    default `true`) — bump `share_plus` da `^9.0.0` a `^12.0.2` richiesto da
    `sqflite_common_ffi_web` (dipende da `package:web >=1.0.0`, incompatibile
    con `web ^0.5.0` di share_plus 9.x); import con `withData: true` per
    leggere i `bytes` invece del path (null sul web).
  - **`add_2_calendar`**: dichiara solo Android/iOS nel suo `pubspec.yaml`,
    nessuna implementazione web. Su desktop/web `_aggiungiAlCalendario` in
    `piano_turni_screen.dart` genera invece un file .ics (RFC 5545, orari
    "floating" senza Z/TZID — stesso orario locale passato finora all'intent
    Android, nessuna conversione fuso orario altrove nel codice) e lo salva
    con `salvaFilePiattaforma` di `backup_file.dart` (già generica: dialog
    "Salva come" su desktop, download/share sul web), invece di limitarsi a
    un messaggio "non disponibile".
  - **Icona web**: aggiunta sezione `web:` a `flutter_launcher_icons` in
    `pubspec.yaml` (stesso `app_icon.png`, sfondo/tema `#00A651`); nome e
    descrizione in `web/manifest.json`/`web/index.html` aggiornati a mano
    (il tool non li tocca).
- **Tool "Lista ospedali"** (`lista_ospedali_screen.dart`,
  `utils/geocoding_api.dart`, v9): sola consultazione degli ospedali già in
  anagrafica (creare/rinominare resta in Impostazioni → Ospedali, ora con
  campi `via` e lat/lng in più) — ricerca per nome/via/città, pulsante
  "Naviga" per ospedale (scelta tra Google Maps e Waze) e vista mappa con
  tutti gli ospedali geocodificati, toggle lista/mappa persistito come in
  turni/assistenze (chiave locale nella schermata, non nel backup, stesso
  pattern di `_kVistaCalendarioKey`). Attivo di default (`attivoDiDefault:
  true`): non richiede alcuna configurazione. Tre decisioni "nessuna API
  key", coerenti con Piano turni:
  - **Naviga → link universali, non intent/scheme nativi**: Google Maps
    (`https://www.google.com/maps/search/?api=1&query=...`) e Waze
    (`https://waze.com/ul?...&navigate=yes`, coordinate se disponibili
    altrimenti `q=` testuale) via `url_launcher` — entrambi risolvono
    l'indirizzo da soli, il pulsante funziona anche per un ospedale senza
    coordinate salvate e non serve alcuna voce `<queries>` nel manifest (a
    differenza di uno scheme diretto tipo `geo:`/`waze://`, un link
    http(s) è implicitamente visibile su Android 11+ e i due servizi lo
    intercettano da soli se l'app è installata). Scelta app: `PopupMenuButton`
    nella riga della lista (compatta), due pulsanti affiancati nello sheet
    del marker sulla mappa (più spazio, nessun tap in più).
  - **Mappa in-app con `flutter_map`** (tile OpenStreetMap, `RichAttributionWidget`
    con l'attribuzione richiesta dalla policy OSM): mostra solo gli ospedali
    con `lat`/`lng` valorizzate; funziona anche su Windows/web perché non è
    un plugin nativo (a differenza di add_2_calendar), solo rendering +
    richieste HTTP delle tile.
  - **Geocoding automatico via Nominatim** (`GeocodingApi.geocodifica`, Dart
    puro e testato con `MockClient`): risolve
    `via, città` in coordinate con uno User-Agent identificativo (richiesto
    dalla policy del servizio) e non lancia mai eccezioni — è un
    arricchimento best-effort per la mappa, non deve mai bloccare il
    salvataggio di un ospedale (app offline-first). Scatta in sottofondo da
    `_dialogOspedale` in Impostazioni dopo il salvataggio (non lo blocca) e
    solo quando l'indirizzo è nuovo o cambiato, non a ogni modifica banale
    (es. solo il nome) — per questo `saveOspedale` non tocca più `lat`/`lng`,
    scritte solo da `aggiornaCoordinateOspedale`, separata apposta perché un
    save successivo con indirizzo invariato non deve azzerarle. Chi fallisce
    (offline, indirizzo non risolvibile) resta comunque salvato senza
    coordinate: si ritenta semplicemente risalvando l'ospedale in
    Impostazioni (nessun pulsante di retry dedicato in Lista ospedali: c'era,
    rimosso su richiesta perché la sua icona — un mirino di localizzazione —
    veniva scambiata per "imposta la posizione dell'ospedale alla posizione
    GPS attuale del telefono", cosa che non ha mai fatto). Il form Ospedale
    ha anche due campi
    "Latitudine"/"Longitudine" opzionali (accettano sia punto che virgola
    come separatore decimale) per inserirle a mano — utile per una posizione
    più precisa di quella trovata da Nominatim (es. l'ingresso ambulanze
    invece del centroide dell'edificio) o quando l'indirizzo non è
    geocodificabile: se compilati hanno priorità e saltano del tutto il
    geocoding automatico. In modifica i due campi partono **sempre vuoti**
    anche se l'ospedale ha già coordinate (mostrate come hintText, di sola
    lettura) — bug corretto dopo la prima versione: precompilarli col valore
    esistente li rendeva "campi manuali" già valorizzati, quindi correggere
    solo via/città lasciandoli intatti veniva letto come "coordinate inserite
    a mano" invece che "campi vuoti", e il geocoding automatico non ripartiva
    mai più dopo la prima geocodifica riuscita.
- **Export/import della sola anagrafica ospedali** (`exportOspedali`/
  `importOspedali` in `db/backup.dart`, pulsanti nell'header della sezione
  Ospedali in Impostazioni, `_SezioneAnag.onExport`/`onImport`): a differenza
  del backup completo (distruttivo, sovrascrive tutto) serve a
  scambiare/condividere solo la lista ospedali, es. con un'altra
  associazione. Il file JSON esportato ha solo nome/via/città/coordinate,
  niente id/timestamp interni — l'import fa un **upsert per nome** (un
  ospedale già in anagrafica con lo stesso nome viene aggiornato, uno nuovo
  viene creato) invece di sovrascrivere tutto: il resto dei dati e gli
  ospedali non presenti nel file restano invariati. Accetta anche un backup
  completo come sorgente (ha comunque una chiave `"ospedali"`), per comodità.
  Le coordinate si scrivono così come sono nel file, **nessun geocoding
  automatico in import**: un upsert con molte righe farebbe una raffica di
  richieste a Nominatim che ne violerebbe la policy (max 1/s) — un ospedale
  arrivato senza coordinate le calcola risalvandolo in Impostazioni. Non
  testato (come `exportBackup`/`importBackup`, che dipendono dal file picker
  reale): stesso limite già accettato per quelle funzioni.
- **Tool nuovo con `attivoDiDefault: true` ma "invisibile" dopo un
  aggiornamento**: bug scoperto aggiungendo Lista ospedali. `ToolsProvider.carica()`
  applicava i default del catalogo SOLO se `kPrefToolsAttivi` non era mai
  stato salvato — chi aveva già toccato un solo switch in Tools attivi in
  passato (es. per accendere il Magazzino Verde) aveva quella chiave salvata,
  e un tool aggiunto dopo restava escluso per sempre dalla lista finché non
  lo si accendeva a mano, anche con default true. Corretto tracciando anche
  `kPrefToolsConosciuti` (id dei tool già "visti" su questo device): un id
  del catalogo assente da lì è nuovo, e prende il proprio default anche se
  `kPrefToolsAttivi` esiste già; un id già noto e disattivato esplicitamente
  resta rispettato. Aggiunto al backup accanto a `kPrefToolsAttivi` (stessa
  ragione: senza, un restore tratterebbe come "nuovi" tutti i tool già noti
  all'origine, riaccendendo quelli disattivati prima del backup). Coperto da
  test dedicati (`test/providers/tools_provider_test.dart`, primo test su un
  provider in questo progetto: gli altri erano tutti Dart puro/DB).
- **Giro di bug fix da code review multi-agente** (2026-07-20, tracciato in
  `TODO.md` durante il lavoro, poi svuotato): analisi sistematica di tutto il
  progetto (DB layer, state management, schermate, tool, backend Go) seguita
  da una sessione di fix quasi completa. Raggruppato per area invece di un
  bullet per voce, per non triplicare la lunghezza di questo file:
  - **DB/backup — perdita dati e atomicità**: `saveOspedale`/`upsertOspedali`
    non scrivono più `via`/`citta` a `null` quando la riga in arrivo non li
    valorizza (stesso pattern "solo se non vuoto" già in uso per
    lat/lng/regione) — prima, scaricare ospedali per città/regione o
    importare un JSON senza quei campi cancellava silenziosamente indirizzi
    inseriti a mano. `upsertOspedali`/`upsertMateriali` girano ora in
    un'unica `db.transaction()` invece di N scritture separate.
    `importBackup` protegge i cast "duri" su `version`/`tables`/righe di
    tabella (un file manomesso restituisce il messaggio "file non valido"
    invece di un `TypeError` non gestito) e ricalcola `num_servizi` da un
    `COUNT(*)` reale a fine import (`ricalcolaTuttiINumServizi`), non più
    verbatim dal backup — disallineato se righe di `servizi` vengono
    scartate. `_ricalcolaNumerazioneTurni`/`_ricalcolaNumerazioneAssistenze`
    unificate in `_ricalcolaNumerazione(db, tabella, assocId)`. Ricerca
    testuale (`getTurni`/`getAssistenze`) con `ESCAPE '\'` e `_escapeLike`:
    prima `%`/`_` digitati dall'utente erano wildcard SQL, non caratteri
    letterali. **Indice `idx_servizi_ospedale` su `servizi(ospedale_id)`**
    (migrazione v11→v12): "Vedi turni" di un ospedale faceva uno scan
    completo della tabella `servizi` senza — **testato solo su
    desktop/analyze, non ancora verificato su Android reale** (regola 8: va
    fatto prima della prossima release APK).
  - **Gestione errori mancante in salvataggi/eliminazioni**: `servizio_form.dart`,
    l'import backup in Impostazioni e i salvataggi in `anagrafiche_screen.dart`
    (violazione `UNIQUE` su un nome duplicato) non avevano try/catch —
    un'eccezione lasciava lo spinner acceso per sempre o falliva in silenzio.
    Stesso trattamento per `_carica`/`_eliminaTurno`/`_sposta`/`_modificaNote`
    in `turno_detail.dart`/`assistenza_detail.dart` e per il caricamento
    iniziale di `turno_form.dart`/`assistenza_form.dart`. **Eliminazione di un
    servizio ora chiede conferma** (dialog identico a turno/assistenza: prima
    il tap sul menu a tre puntini cancellava subito). Le frecce di riordino
    servizi si disabilitano durante l'operazione (`_riordinando`): tap multipli
    rapidi prima che `_carica()` tornasse potevano invertire l'ordine atteso.
    Il campo "Ore" di turno/assistenza rifiuta valori negativi nel validator
    (`formatOre` li scomponeva ore/minuti in modo scorretto, e inquinavano le
    somme in Statistiche).
  - **Piano turni**: il download dell'XLSX ora ha un `.timeout(20s)` (era
    l'unica chiamata di rete dell'app senza — una rete instabile bloccava lo
    spinner a schermo intero indefinitamente). Il completamento di `_carica`
    verifica che `_urlCtrl.text.trim()` coincida ancora con l'input di
    partenza prima di applicare lo stato: premere "Cambia foglio" durante un
    refresh silenzioso in corso non fa più ricomparire il piano appena
    cancellato. Il merge additivo della sincronizzazione dal backend condiviso
    ora esclude le chiavi in `kPrefPianoTurniFogliRimossi` (nuova preferenza,
    locale al device come `kPrefPianoTurniUltimoMese`): un foglio rimosso
    esplicitamente dai salvati non viene più "resuscitato" se il backend lo
    ha ancora.
  - **Widget/provider**: `colorFromHex` valida che l'input sia 6/8 cifre
    esadecimali (con o senza `#`) invece di lasciare che un valore senza `#`
    (es. da un backup modificato a mano) venga interpretato come decimale,
    producendo un colore quasi trasparente invece del fallback `null` atteso.
    `CodiceChip` tratta anche la stringa vuota come "nessun codice".
    `CalendarioMensile<T>` memoizza il raggruppamento per giorno in
    `didUpdateWidget` (ricalcolato solo se cambia `widget.elementi`, non a
    ogni build) e risincronizza il mese mostrato se `giornoSelezionato`
    cambia di mese da fuori senza far rimontare il widget. `avviaTutorial`
    ha una guardia globale anti-concorrenza (un secondo avvio mentre uno è
    già a schermo — doppio tap su "Rivedi tutorial" — veniva ignorato invece
    di inserire una seconda `OverlayEntry` irraggiungibile) e la card del
    passo è ora in un `ConstrainedBox` + `SingleChildScrollView` invece di
    poter eccedere lo schermo in landscape sui passi più lunghi. `tools_screen.dart`
    non fa più un null-check secco su `_destinazioni[t.id]` (un tool nel
    catalogo senza voce lì diventa un tap senza effetto, non un crash).
    `ToolsProvider.carica()` scrive le due `List<String>` in
    SharedPreferences solo se il valore risolto differisce da quello già
    salvato, non a ogni avvio incondizionatamente. `backend_api.dart`
    incapsula ogni `jsonDecode` in un'eccezione tipizzata (`_decodeJson`): un
    body 200 non-JSON (proxy/manutenzione) mostrava prima un errore grezzo.
  - **Piano turni, parser**: `parsePianoMensile` valida `giorno` contro i
    giorni reali del mese individuato da B2 (28-31), non solo `1..31` — un
    refuso nel nome scheda (es. "MAR 31" in un mese di 30 giorni) restava
    prima raggiungibile da `cercaNome`/`giorniInServizio` con una data che
    `DateTime` normalizzava silenziosamente su un altro giorno/mese.
  - **Materiali usati**: `_variaQuantita` fa rollback dello stato locale se
    la scrittura su DB fallisce (l'aggiornamento ottimistico prima restava
    "sporco" senza alcun feedback in caso di errore).
  - **Backend Go — sicurezza**: `checkJwtSecret()` (chiamata a inizio
    `main()`, prima di aprire qualunque connessione) termina il processo se
    `JWT_SECRET` è assente o coincide con uno dei placeholder noti del
    progetto (fallback Go, default `docker-compose.yml`, esempio in
    `.env.example`) — prima il server partiva comunque con un segreto
    pubblico, permettendo di firmarsi un JWT admin valido. `readJSON`/gli
    endpoint di import usano `http.MaxBytesReader` (1 MiB per il JSON
    generico, incluso il login non autenticato; 10 MiB per gli import
    massivi) contro un DoS a basso costo. Tutti gli handler usano
    `r.Context()` invece del `context.Background()` catturato a startup
    (rinominato `startupCtx`, usato solo per `connectDB`/`initSchema`/`seedAdmin`):
    una richiesta lenta o un client disconnesso ora annulla davvero la query
    invece di rischiare di esaurire il pool sotto carico. Login: rate limit
    in-memory per IP chiamante (`loginRateLimitato`/`loginRegistraFallito`,
    5 tentativi falliti / 5 minuti, chiave da `X-Real-IP` se dietro nginx
    altrimenti `r.RemoteAddr`) e confronto bcrypt a tempo costante anche per
    username inesistenti (`dummyHash`), che prima rivelava via timing quali
    username esistessero. Nuovi `GET`/`DELETE /api/auth/users`
    (`listUsers`/`deleteUser` in `auth.go`, protetti come gli altri endpoint
    admin): prima un account si poteva solo creare, mai vedere o revocare —
    `deleteUser` rifiuta di eliminare l'ultimo utente rimasto. `POST
    /api/fogli` valida che `chiave` abbia un mese reale (01-12, non solo il
    formato `\d{4}-\d{2}`) e che `url` inizi per `http://`/`https://`; la
    pagina admin (`public/admin/index.html`) renderizza comunque un link
    ai fogli solo se lo schema è http(s), come difesa in profondità per righe
    scritte prima di questo controllo. `docker-entrypoint.sh`: il backend
    gira in un loop di riavvio (backoff fisso 2s) invece che restare morto in
    permanenza dopo un crash successivo a un avvio riuscito — nessun
    `HEALTHCHECK` Docker sul container intero, di proposito: farebbe
    riavviare anche nginx per un backend mal configurato, contraddicendo la
    scelta (sopra) di lasciare nginx a servire i file statici anche a
    backend giù.
- **Aggiornamento dipendenze Flutter (2026-07-20), incluse le major**: fatto
  in una sessione dedicata separata dal giro di bug fix sopra (rimandato lì
  di proposito). `sqlite3` (^3.1.2→^3.5.0), `intl` (^0.19.0→^0.20.3), `uuid`
  (^4.4.0→^4.6.0), `flutter_markdown_plus` (^1.0.7→^1.0.12) e `flutter_lints`
  (^4.0.0→^6.0.0, nessun nuovo lint scattato: il set raccomandato v6 sembra
  anzi più permissivo su alcuni `prefer_const_constructors`) sono bump senza
  sorprese. `file_picker` ^8.0.7→^11.0.2 (non la 12.0.0-beta, evitata di
  proposito per una dipendenza dell'unico percorso di restore dei dati) ha
  **cambiato l'intera API pubblica**: `FilePicker` non è più un singleton
  (`FilePicker.platform.pickFiles(...)`) ma una classe con soli metodi
  static (`FilePicker.pickFiles(...)`/`FilePicker.saveFile(...)`) — aggiornati
  i tre punti d'uso in `backup_file_io.dart`/`backup_file_web.dart`.
  - **`package_info_plus` e `share_plus` restano fermi** (^9.0.1/^12.0.2,
    non le rispettive major ^10.x/^13.x) per un vincolo scoperto durante
    l'update, non ovvio dai soli numeri di versione: **`package_info_plus`
    ≥10.1.0 e `share_plus` ≥13.1.0 richiedono entrambi `win32` ^6.x, ma
    nessuna versione stabile di `file_picker` fino all'11.x incluso lo
    supporta** (tutte fisse su `win32` ^5.9.0 — solo la 12.0.0-beta è
    passata a ^6.x). Le tre dipendenze non sono risolvibili insieme oltre
    questo punto senza accettare la beta. Scelta: priorità a `file_picker`
    (bump reale 8→11, tocca l'import backup) sugli altri due, il cui bump
    sarebbe stato di impatto pratico minimo (solo lettura versione app e
    normale manutenzione) — `pub get` fallisce con un errore esplicito se in
    futuro si prova a spingerli oltre senza prima risolvere `file_picker`.
  - **Verificato**: `flutter analyze` (0 errori), `flutter test` (136/136),
    `flutter build windows --debug` (compila, l'app si avvia). Non testato a
    mano il click-through di export/import backup su un file reale — da
    fare prima della prossima release, area toccata dal cambio di API di
    `file_picker`.
- **`flutter_localizations` aggiunta (2026-07-20), solo per i widget Material
  nativi**: `showDatePicker` (selezione data in `turno_form.dart`/
  `assistenza_form.dart`) è l'unico punto dell'app che usa un widget
  Material standard invece di testo/UI custom, e senza
  `localizationsDelegates` mostrava mesi/giorni e i pulsanti OK/Cancel in
  inglese — stonato in un'app altrimenti interamente in italiano (vedi
  bullet sopra sul calendario custom, dove l'italiano era già hardcoded a
  prescindere). `MaterialApp` ora dichiara i tre delegate globali
  (`GlobalMaterialLocalizations`/`GlobalWidgetsLocalizations`/
  `GlobalCupertinoLocalizations`) e **`locale` fissato a `Locale('it')`**
  (non la lingua di sistema): coerente col resto dell'app, che non ha mai
  seguito la lingua del device. `flutter_localizations` è nell'SDK Flutter
  stesso (`sdk: flutter`, nessuna versione da scegliere), ma pinna `intl` a
  una versione esatta della release Flutter in uso (qui `0.20.2`, non
  `^0.20.3` come dopo l'ultimo bump dipendenze) — il vincolo in
  `pubspec.yaml` è stato ristretto di conseguenza, altrimenti `pub get`
  fallisce. Nessun impatto sul resto dell'app (nessun'altra schermata usa
  widget Material localizzabili) e nessuna nuova stringa da tradurre: il
  pacchetto localizza solo i widget standard di Flutter, non introduce un
  sistema di localizzazione da estendere alle stringhe dell'app.
- **Badge "quante volte compare" in Anagrafiche (2026-07-25)**: ogni voce di
  associazioni/persone/ospedali/tipologie turno in `AnagraficheScreen` ha ora
  un badge col numero di turni/assistenze/servizi in cui compare (richiesta
  esplicita: aiuta a individuare voci mai usate o da consolidare). Quattro
  nuove funzioni in `helpers.dart` (`contaOccorrenzeAssociazioni/Persone/
  Ospedali/Tipologie`), una query aggregata per tipo invece di una query per
  voce — l'anagrafica può contenere decine di persone/ospedali e N query
  scalerebbero male:
  - **Persone**: unpivot via `UNION ALL` dei 10 campi equipaggio +
    `COUNT(DISTINCT id)`, sommato tra `turni` e `assistenze`
    (`_contaPerEquipaggio`, funzione privata parametrizzata sul nome tabella —
    sempre un letterale interno, mai testo utente). `DISTINCT id` replica la
    stessa semantica OR di `getTurniPerPersona`/`getAssistenzePerPersona`: una
    persona in più ruoli sulla stessa riga conta una volta sola, non due.
  - **Ospedali**: `COUNT(DISTINCT turno_id)` su `servizi` **con `WHERE
    ospedale_id IS NOT NULL`** — un servizio senza ospedale assegnato
    (campo opzionale nel form) produrrebbe altrimenti un gruppo `NULL` nel
    `GROUP BY` che fa fallire il cast Dart a `String` in fase di lettura;
    bug reale, preso dal test dedicato prima di finire in produzione.
  - **Associazioni**: somma dei conteggi di `turni`+`assistenze` per
    `associazione_id`.
  - **Tipologie turno**: `tipologie` è la colonna multi-valore JSON (v8) —
    lette tutte le righe non vuote e decodificate in Dart (stesso
    `jsonDecode` di `Turno.fromMap`) invece di un unpivot SQL su un array di
    lunghezza variabile, più semplice per una tabella di questa dimensione.
  - **Ricalcolo**: `AnagraficheProvider.carica()` calcola le quattro mappe
    insieme alle liste; un nuovo `ricaricaConteggi()` le ricalcola da sole
    (senza rileggere le liste anagrafiche, che non cambiano quando si salva
    un turno) ed è chiamato da `TurniList`/`AssistenzeList` negli stessi
    punti in cui già ricaricano `StatisticheProvider` dopo un form/dettaglio
    — stesso bug-pattern già documentato per `StatisticheProvider`:
    `AnagraficheScreen` resta montata nell'`IndexedStack` di `AppNavigator`,
    senza questo refresh i badge sarebbero rimasti quelli di prima di
    ogni modifica a un turno/un'assistenza.
  - Coperto da un nuovo gruppo di test in `test/db/helpers_test.dart`
    (`Conteggi anagrafiche`), incluso il caso NULL di cui sopra.
  - **Ordinamento "Nome"/"Numero" per sezione**: due chip sopra la lista di
    ogni sezione (richiesta esplicita di seguito al badge). Ciclo a tre stati
    per campo (`_SezioneAnagState._toggleOrdinamento`): primo tap ordina
    crescente, secondo tap inverte, terzo tap torna all'ordine naturale
    (quello di `widget.items`, già "per nome" per tre sezioni su quattro —
    solo le tipologie hanno un ordine custom, il campo `ordine`). Stato di
    sola visualizzazione della sessione (`_ordinamento`/
    `_ordinamentoDiscendente`), non persistito e non incluso nel backup: non
    è una preferenza dell'anagrafica. Le frecce di riordino manuale delle
    tipologie (`onMoveUp`/`onMoveDown`) restano visibili solo con
    l'ordinamento naturale attivo: con "Nome"/"Numero" attivo la posizione in
    lista non rispecchia più il campo `ordine`, quindi spostare una voce
    sarebbe fuorviante.
- **Piano turni: apertura automatica al primo avvio + navigazione rapida tra
  mesi (2026-07-25)**: due richieste esplicite legate allo stesso archivio
  `_fogliSalvati` (chiave "aaaa-mm" → URL del foglio Google di quel mese, già
  esistente).
  - **Primo utilizzo**: prima `_ripristinaPreferenze()` decideva solo tra
    "c'è un URL salvato → carica quello" e "nessun URL → form vuoto",
    lasciando un utente nuovo davanti a un campo da compilare a mano anche
    se l'associazione ha già pubblicato il foglio del mese sul backend
    condiviso. Quando l'URL salvato è assente, la sincronizzazione dal
    backend (`_sincronizzaFogliDalBackend`, già esistente per il merge
    additivo in sottofondo) viene ora **attesa** invece che lanciata e
    dimenticata, e se l'archivio risultante contiene la chiave del mese
    corrente il piano si apre da solo (`_apriFoglioSalvato`, stessa funzione
    già usata dal tap su un foglio salvato). Per chi ha già un URL salvato
    il comportamento non cambia: la sincronizzazione resta in sottofondo,
    non deve ritardare l'apertura del piano che l'utente aveva già.
  - **Frecce ← → mese precedente/successivo**: nell'intestazione del
    calendario, accanto al nome del mese. Abilitate solo se il mese
    adiacente è tra i fogli salvati (`_fogliSalvati`, locale + sincronizzato
    dal backend) — a differenza di una paginazione qualunque, ogni mese ha
    un proprio link Google Sheets distinto (vedi bullet originale del tool):
    senza un URL noto per quel mese non c'è nulla da scaricare, quindi il
    pulsante resta disabilitato (icona attenuata, tooltip esplicito) invece
    di tentare un caricamento destinato a fallire. Stessa `_apriFoglioSalvato`
    di sopra, nessuna logica di caricamento duplicata.
  - **Nessuno scenario di rete lascia l'utente senza feedback**: verificato
    a mente ripercorrendo il codice (non solo assunto). Il download del
    foglio ha già un timeout di 20s e cattura `TimeoutException`/errori di
    rete in `_carica()` (preesistente); `getFogli()` del backend condiviso
    ha lo stesso timeout di 20s in `backend_api.dart`. Se il tentativo
    automatico al primo avvio non trova un link per il mese corrente (rete
    assente, timeout, o l'associazione non ha ancora pubblicato quel mese —
    i tre casi non sono distinguibili da qui, la sync è silenziosa di
    proposito) compare un banner informativo nel form (`_messaggioPrimoAvvio`,
    icona neutra `info_outline`, non lo stile rosso di `_errore`: non è detto
    che qualcosa sia "andato storto"). Si azzera al primo vero tentativo di
    caricamento (manuale o su un foglio salvato) in `_carica()`, altrimenti
    resterebbe visibile insieme a un piano già caricato con successo.
- **Bug del parser Piano turni: descrizione fascia e orario leggevano anche
  la colonna B (2026-07-25)**: trovato dall'utente confrontando col foglio
  reale (mai un'ipotesi mia, verificato cella per cella). Struttura vera di
  ogni riga del blocco a 4 ruoli: colonna A = contenuto informativo di quella
  riga (titolo blocco sulla riga del titolo, descrizione fascia sulla riga
  del Cs, orario sulla riga del Terzo, monte ore sulla riga del Quarto,
  ignorato), colonna B = **solo l'etichetta del ruolo** (AUT/CAP/SOC/ALL —
  Autista/Cs/Terzo/Quarto), colonna C = titolare, D = sostituti. Il codice
  concatenava A+B sia per la descrizione sia per l'orario
  (`'${testo(r + 1, 0)} ${testo(r + 1, 1)}'`), quindi appendeva il nome del
  ruolo in coda al valore mostrato (es. `"18:30 - 23:30 Terzo"` invece di
  `"18:30 - 23:30"`); stesso bug per l'orario del centralino (riga sotto il
  titolo). Ora entrambi leggono solo `testo(r + 1, 0)`/`testo(r + 2, 0)` —
  colonna B non viene mai letta dal parser, in nessun punto. Nuovo gruppo di
  test "Foglio reale" in `piano_mensile_test.dart`: riproduce cella per
  cella un vero foglio "SERA/NOTTE" fornito dall'utente (colonna B compresa,
  con le etichette di ruolo), non solo frammenti sintetici minimi come gli
  altri test — regressione concreta invece che solo teorica. Lo stesso bug
  e la stessa correzione sono stati applicati in parallelo al porting Go del
  parser in un progetto separato (`Progetti/MOS`, temporaneo).
- **Migrazione CI/registry da Gitea a GitHub Actions (2026-08-12)**: il
  server che ospitava l'istanza Gitea del progetto è stato violato — repo
  spostato su GitHub (`enne139/ambuturni`, pubblico), dismessa ogni
  infrastruttura self-hosted per la CI. `.gitea/workflows/` rimosso,
  sostituito da `.github/workflows/build-android.yml`/`build-web.yml`:
  stessi trigger (tag `vX.Y.Z` + `workflow_dispatch`) e stessa logica di
  build, ma:
  - **Runner self-hosted (label `android`, >= 8 GB RAM) → runner
    GitHub-hosted `ubuntu-latest`** per entrambi i workflow: i runner
    standard GitHub-hosted (4 vCPU/16 GB RAM) coprono ampiamente il
    requisito, supportano nativamente i job `container:` (usati per
    l'immagine `ghcr.io/cirruslabs/flutter`) e hanno Docker/buildx già
    pronti — nessuna infrastruttura propria da tenere online, il motivo
    stesso della migrazione. Rimosso anche lo step di installazione manuale
    di Node.js nel container Flutter (necessario per l'act_runner di
    Gitea): i runner GitHub-hosted montano da soli il proprio Node dentro
    qualunque container di job per eseguire le action JS, senza bisogno che
    l'immagine lo includa.
  - **Container Registry Gitea → GitHub Container Registry (`ghcr.io`)**:
    `build-web.yml` pubblica su `ghcr.io/enne139/ambuturni-web` (stesso
    nome immagine, stesso schema di tag `latest`/SHA/`vX.Y.Z`).
  - **Niente più secret `REGISTRY_TOKEN` (PAT)**: sia il push su `ghcr.io`
    sia la pubblicazione della Release usano il `GITHUB_TOKEN` generato
    automaticamente a ogni run (permessi `packages: write`/`contents:
    write` dichiarati nel workflow) — un secret in meno da custodire e
    ruotare. `akkuman/gitea-release-action` (specifica di Gitea) è
    sostituita da `gh release create` (CLI preinstallata sui runner
    GitHub-hosted), in un job **separato** (`release`) che gira fuori dal
    container Flutter — non è detto che `gh` sia presente in
    un'immagine di terze parti pensata solo per build Flutter — e scarica
    l'APK come artifact dal job `build`.
  - **Restano solo due secret**: `KEYSTORE_B64`/`KEYSTORE_PASSWORD`. Il
    keystore è stato **rigenerato da zero**, non semplicemente ricopiato:
    viveva come secret sull'istanza Gitea violata, quindi potenzialmente
    esposto (vedi bullet "Keystore di release" più sopra per le
    conseguenze accettate esplicitamente dall'utente).
  - **`actions/upload-artifact` da v3 (SHA pinnato) a v4.6.2**: v3 è stato
    dismesso da GitHub nel frattempo (le run che lo usano falliscono), non
    una scelta di aggiornamento facoltativa — stesso motivo per
    `actions/download-artifact` (v4.3.0, nuovo nel job `release`).
    `actions/checkout` resta pinnato alla stessa versione/SHA di prima
    (v4.3.1): è la stessa action upstream, nessun motivo di cambiarla.
  - **Pacchetto `ghcr.io` privato di default anche con repo pubblico**: va
    reso pubblico a mano una tantum dalle impostazioni del pacchetto su
    GitHub, altrimenti il pull in produzione richiede un login.
  - **Nessuna azione lato codice applicativo**: la migrazione tocca solo
    workflow CI, `Dockerfile`/`.dockerignore` (path nei commenti, `.gitea`
    → `.github` nell'exclude list), `android/app/build.gradle` (commento) e
    `README.md`/`backend/README.md` (riferimenti a Gitea) — nessuna
    modifica a `lib/`, `backend/*.go` o allo schema DB, quindi nessun bump
    di versione DB né test manuale richiesti (regola 4, eccezione
    documentazione/CI).
  - **Bug trovato al primo run reale su `ghcr.io`**: `build-web.yml` faceva
    `buildx build --load` seguito da tre `docker push` sequenziali (SHA/
    latest/`vX.Y.Z`) — su un pacchetto appena creato ha fatto scattare il
    secondary rate limit del registry ("You have exceeded a secondary rate
    limit"), run fallita. Corretto in un unico `buildx build --push` con i
    tre `-t`: un solo giro di richieste al registry, layer condivisi tra i
    tag, pattern comunque più idiomatico per buildx multi-tag.
- **Account "utente-app" + ruoli nei JWT del backend condiviso (2026-09-02,
  primo passo di "Contenuti riservati" — vedi bullet successivo per
  Comunicati)**: fin qui il backend aveva un solo tipo di credenziali, gli
  account admin (tabella `users`) per la pagina `/admin/`. Richiesta
  esplicita dell'utente: un secondo tipo di account, creato **solo**
  dall'admin dalla pagina del sito (mai dall'app), che serve a sbloccare
  contenuti nell'app — non a gestire il backend. Primo tool a diventarne
  dipendente: Repository formazione (bullet a parte per quando la
  protezione è stata attivata).
  - **Tabella `utenti_app` separata da `users`**, non un campo `role` sulla
    tabella admin: un account-contenuto non deve mai poter transitare per i
    controlli riservati agli admin nemmeno per errore. `deve_cambiare_password`
    parte sempre `true` alla creazione (la password data dall'admin è sempre
    provvisoria) e si azzera solo dal cambio password riuscito.
  - **Ruolo (`role: "admin"|"utente"`) aggiunto alle claims JWT** (`auth.go`,
    struct `claims` con `jwt.RegisteredClaims` embedded): senza, un token
    utente-app varrebbe anche per le rotte admin, firmate con lo stesso
    `JWT_SECRET`. Tre middleware condividono `roleMiddleware(next,
    ruoliAmmessi...)`: `authMiddleware` (solo `admin`, tutte le rotte di
    scrittura esistenti + gestione utenti-app/comunicati), `utenteAuthMiddleware`
    (solo `utente`, l'unica rotta di scrittura lato utente: il cambio
    password), `contentAuthMiddleware` (`admin` o `utente`, sola lettura dei
    contenuti riservati). Tutti e tre scrivono lo username (`claims.Subject`)
    nel `context.Context` della richiesta (`usernameFromContext`): il cambio
    password identifica sempre il chiamante dal token, mai da uno username
    nel body, altrimenti chiunque potrebbe cambiare la password di un altro
    account indovinandone lo username.
  - **Effetto collaterale accettato**: i token admin già emessi prima di
    questo deploy non hanno `role` e non passano più `authMiddleware` — un
    admin già loggato deve rifare il login dopo l'aggiornamento del server.
    Stesso genere di rottura deliberata già accettato per JWT_SECRET/keystore.
  - **Cambio password obbligatorio al primo login, poi libero** (richiesta
    esplicita): `PUT /api/utenti/password` (`{passwordAttuale,passwordNuova}`,
    minimo 8 caratteri) verifica sempre `passwordAttuale` via bcrypt anche
    per il primo cambio — stesso schema di sicurezza del login, nessuna
    scorciatoia solo perché è appena arrivato un token fresco. Login
    (`POST /api/utenti/login`) restituisce anche `deveCambiarePassword`,
    letto dalla riga: dice all'app se mostrare subito la schermata di
    cambio password prima di lasciar entrare nei contenuti riservati (lato
    client, vedi bullet dedicato quando arriva).
  - **`utenti_app.go` mirror della parte admin di `auth.go`**: stesso
    `dummyHash` per timing costante, stesso rate-limiter di login condiviso
    per IP chiamante (budget in comune con l'admin, comunque sufficiente a
    fermare un bruteforce). A differenza di `deleteUser` (admin), `deleteUtenteApp`
    non ha il vincolo "non l'ultimo": zero utenti-app è uno stato legittimo,
    nessuna funzionalità del sistema ne dipende per esistere.
  - **Confine esplicito voluto dall'utente: la gestione degli account è SOLO
    della pagina admin del sito, mai dell'app Flutter** — l'app Flutter
    chiamerà solo login, cambio password e lettura dei contenuti riservati;
    creare/elencare/eliminare un utente-app resta un'azione della tab
    "Utenti app" in `backend/public/admin/index.html` (mirror della tab
    "Utenti" esistente, stesso pattern `renderTabellaGenerica`/`toast()`),
    mai un endpoint richiamato da `utils/backend_api.dart`.
  - **Verificato end-to-end** (nessun framework di test Go nel repo, come
    per le altre risorse): Postgres usa e getta via Podman + `go run .`,
    `curl` per l'intero flusso — login admin, login utente-app inesistente
    (401), un token utente-app rifiutato su una rotta admin e un token admin
    rifiutato su `PUT /api/utenti/password` (401 su entrambi, confermano il
    confine di ruolo), creazione utente-app con password provvisoria, cambio
    password con la password attuale sbagliata (rifiutato) e poi corretta
    (accettato, `deveCambiarePassword` torna `false` al login successivo),
    eliminazione — più uno smoke test di non regressione su `POST
    /api/ospedali` (continua a funzionare identico con un token admin).
- **Archivio comunicati (PDF) sul backend condiviso, protetto da login
  (2026-09-02)**: secondo tool a diventare "contenuto riservato" insieme a
  Repository formazione (bullet precedente), che con questo commit smette
  davvero di essere pubblica — `GET /api/repository-formazione` passa da
  handler nudo a `contentAuthMiddleware`.
  - **I PDF vivono dentro Postgres** (`comunicati.file_data bytea`), non su
    filesystem: decisione discussa esplicitamente con l'utente. Zero
    modifiche al deploy — stesso volume `pgdata` già persistito, nessun
    volume Docker dedicato da aggiungere né in `backend/docker-compose.yml`
    né in produzione — coerente con lo stile "niente infrastruttura nuova"
    già seguito per ospedali/fogli/materiali. Limite pratico accettato:
    adatta a documenti associativi (poche pagine), non a un archivio enorme.
  - **`comunicati.go`**: `listComunicati` restituisce solo i metadati (id,
    titolo, descrizione, nome file, dimensione, data) — MAI `file_data`, che
    appesantirebbe inutilmente l'elenco; il download è l'endpoint a parte
    `GET /api/comunicati/{id}/file`.
  - **Upload multipart, non JSON**: `POST /api/comunicati` usa
    `r.ParseMultipartForm` dopo `http.MaxBytesReader(w, r.Body,
    maxComunicatoBytes)` (20 MiB, `httputil.go`) — `readJSON` non si applica
    a un body multipart. Validazione doppia: titolo non vuoto e primi 4 byte
    del file uguali a `%PDF` (un file rinominato a caso non basta a farlo
    passare per un comunicato).
  - **`Content-Disposition` costruito con `mime.FormatMediaType`** (stdlib)
    invece di concatenare la stringa a mano: escaping corretto del nome
    file, evita un header injection da un nome file malevolo caricato
    dall'admin (difesa in profondità, l'upload è comunque protetto da
    `authMiddleware`).
  - **Lettura protetta da `contentAuthMiddleware`** (`admin` o `utente`,
    vedi bullet precedente sui ruoli JWT), scrittura (`POST`/`DELETE`) da
    `authMiddleware` (solo admin) — stesso confine "gestione solo dalla
    pagina admin" del bullet precedente: nessuno di questi due endpoint di
    scrittura verrà mai chiamato da `utils/backend_api.dart`.
  - **Pagina admin**: nuova tab "Comunicati" (form titolo+descrizione+file,
    upload via `fetch` con `FormData` — niente `Content-Type` manuale, lo
    imposta il browser col boundary corretto — tabella con Scarica/Elimina).
    `caricaFormazione()` doveva anche lei aggiungere l'header
    `Authorization`: prima era una `GET` pubblica, senza l'header avrebbe
    iniziato a ricevere 401 col cambio sopra — trovato e corretto prima del
    test end-to-end, non dopo.
  - **Verificato end-to-end** come il bullet precedente (Podman + `go run
    .` + `curl`, incluso un vero PDF minimo generato al volo): `GET
    /api/repository-formazione` senza token ora dà 401; upload di un PDF
    vero, elenco, download con confronto **byte-per-byte** col file
    originale (identico), upload di un file non-PDF rifiutato (400),
    eliminazione; un token utente-app legge sia repository-formazione sia
    comunicati (200) ma non può caricarne uno (401, confine di ruolo).
- **Login utente-app lato client, sblocca Repository formazione
  (2026-09-02)**: terzo commit della funzionalità, primo a toccare l'app
  Flutter — i due bullet precedenti erano solo backend.
  - **`AccountProvider`** (`providers/app_provider.dart`): stesso motivo di
    `ToolsProvider`/`NavigazioneProvider` (Impostazioni e il tool aperto
    restano entrambe montate nell'`IndexedStack`, un login/logout/cambio
    password fatto in un punto deve riflettersi subito nell'altro).
    `carica()` ripristina la sessione da SharedPreferences all'avvio,
    chiamata da `AppNavigator.initState` insieme ad `AnagraficheProvider`/
    `ToolsProvider`. Token/username/`deveCambiarePassword` **non vanno nel
    backup** (`kPrefAccountToken`/`kPrefAccountUsername`/
    `kPrefAccountDeveCambiarePassword` in `prefs_keys.dart`, `db/backup.dart`
    non li tocca): stato di sessione locale al device, come
    `kPrefTutorialCompletato` — un JWT dentro un backup esportabile sarebbe
    anche un problema di sicurezza, non solo una preferenza da ripristinare
    altrove.
  - **`AccessoRichiesto`** (`widgets/accesso_richiesto.dart`): avvolge il
    contenuto di un tool riservato, nessuno Scaffold/AppBar propri (li mette
    già la schermata chiamante) — mostra `LoginForm` se non autenticati,
    `CambiaPasswordForm(forzato: true)` se `deveCambiarePassword`, altrimenti
    il `builder(context, token)` del tool. `LoginForm` è pubblico e condiviso
    con la sezione Account di Impostazioni (stesso campo, stesso
    comportamento, non duplicato).
  - **`CambiaPasswordForm`/`CambiaPasswordScreen`**
    (`screens/shared/cambia_password_screen.dart`): stesso pattern
    contenuto-condiviso-in-due-contesti di `note_editor_screen.dart` — il
    form (`CambiaPasswordForm`) è riusato inline da `AccessoRichiesto` (caso
    forzato, niente Scaffold) e dentro `CambiaPasswordScreen` (caso
    volontario da Impostazioni, Scaffold+AppBar+back, pop con snackbar a
    fine cambio). Verifica sempre la password attuale lato server
    (`PUT /api/utenti/password`), anche nel caso forzato: nessuna
    scorciatoia solo perché il token è appena stato emesso. Caso forzato:
    niente pulsante indietro, solo "Esci" come via di fuga (mai un vicolo
    cieco per chi non vuole cambiarla subito) — nessuna navigazione
    esplicita al successo, `AccountProvider.cambiaPassword()` azzera
    `deveCambiarePassword` e notifica, `AccessoRichiesto` passa da solo al
    contenuto vero.
  - **401 → logout automatico**: `BackendApiUnauthorized extends
    BackendApiException` (nuova, `backend_api.dart`, lanciata da
    `_lanciaErrore` sullo status 401) invece del generico
    `BackendApiException` — i chiamanti delle rotte autenticate
    (`_RepositoryFormazioneContenuto`, e Archivio comunicati quando arriva)
    la intercettano per chiamare `AccountProvider.logout()` invece di
    mostrare un errore con un "Riprova" destinato a fallire per sempre finché
    non si rifà login.
  - **`getRepositoryFormazione` ora richiede `token`** (era pubblica):
    `RepositoryFormazioneScreen` avvolta in `AccessoRichiesto`, estratto il
    contenuto vero in `_RepositoryFormazioneContenuto` (stessa logica di
    prima, solo parametrizzata sul token).
  - **Sezione "Account" in Impostazioni** (`_SezioneAccount`, stesso pattern
    collassato-di-default di `_SezioneBackendCondiviso`): da sloggato
    riusa `LoginForm`, da loggato mostra "Accesso effettuato come
    {username}" + "Cambia password" (`Navigator.push` su
    `CambiaPasswordScreen`) + "Esci".
  - **Test**: `test/utils/backend_api_test.dart` esteso con `loginUtente`,
    `cambiaPassword`, `getComunicati`, `getComunicatoFile` (header
    `Authorization` verificato su ognuna) e un caso 401 →
    `BackendApiUnauthorized` per `getRepositoryFormazione`/`loginUtente`.
    `flutter analyze` pulito, `flutter test` verde (155/155).
  - **Due bug trovati dal test manuale dell'utente** (non da `analyze`/
    `test`, entrambi richiedevano l'app vera):
    1. **`_SezioneAccount` non controllava `deveCambiarePassword`**: un
       login fatto da Impostazioni → Account (invece che aprendo
       direttamente un tool riservato, l'unico percorso testato a mente
       durante lo sviluppo) mostrava subito "Accesso effettuato come..."
       saltando il cambio password obbligatorio — `AccessoRichiesto` aveva
       il controllo, questa sezione no. Corretto allineando la stessa
       cascata di condizioni (`!caricato` → `!loggedIn` → `deveCambiarePassword`
       → stato loggato) in entrambi i punti.
    2. **CORS del backend senza `PUT` in `Access-Control-Allow-Methods`**
       (`httputil.go`, bug preesistente): il cambio password (`PUT
       /api/utenti/password`) falliva silenziosamente su Flutter web con un
       errore di rete generico — il browser blocca la richiesta reale già
       in fase di preflight se il metodo non è nell'elenco dichiarato.
       Colpiva già `PUT /api/ospedali/:id`/`PUT /api/materiali/:id`, mai
       notato prima perché mai esercitati da un client web reale. `curl`
       non lo intercetta (CORS è imposto dal browser, non dal server): per
       questo era passato inosservato in tutta la verifica end-to-end fatta
       finora via `curl`, lezione aggiunta alla lista di cose che una
       verifica solo-backend non copre.

---

## Funzionalità implementate

Dettagli/motivazioni dei punti più delicati sono in "Decisioni tecniche
rilevanti"; qui solo l'inventario di cosa esiste.

- ✅ **Turni**: lista con filtro/ricerca, form completo, dettaglio con servizi
  (CRUD + riordino, descrizione markdown), tipologie multi-select, numerazione automatica.
- ✅ **Vista calendario turni e assistenze**: griglia mensile con pallini
  colorati per associazione, elementi del giorno selezionato, FAB con data
  precompilata; toggle lista/calendario in AppBar, persistito tra i riavvii
  (preferenza separata per turni e assistenze).
- ✅ **Equipaggio**: form 1ª/2ª parte con "Copia 1ª → 2ª"; affiancate per ruolo nel dettaglio.
- ✅ **Note** (turno/assistenza): card dedicata in markdown, editor a schermo intero.
- ✅ **Assistenze**: come i turni ma senza tipologia né servizi; ricerca
  testuale (descrizione/note) e vista calendario come i turni.
- ✅ **Statistiche**: 6 card aggregate, filtro associazione, si aggiornano anche dopo import.
- ✅ **Anagrafiche** (raggiungibile dall'AppBar di Attività): CRUD
  associazioni/persone/ospedali/tipologie turno, "Vedi turni" per
  persona/ospedale, export/import ospedali, badge con quante volte ogni
  voce compare in turni/assistenze/servizi.
- ✅ **Impostazioni**: backup, Tools attivi (attiva/disattiva i tool
  mostrati in Tools), backend condiviso, navigazione, account (login/cambio
  password/logout utente-app).
- ✅ **Backup**: export/import JSON completo e leggibile, nomi file con timestamp.
- ✅ **Combobox con creazione inline** per persone/ospedali/materiali.
- ✅ **Tools → Materiali usati**: catalogo + utilizzi (quantità/unità/posizione),
  nessuno storico. Pulsante per scaricare il catalogo condiviso dal backend
  (upsert per nome, case-insensitive).
- ✅ **Tools → Piano turni**: calendario equipaggi/buchi dal foglio Google
  mensile dell'associazione (pallini per fascia, dettaglio per blocco, filtri
  ruolo, aggiunta del turno al calendario di sistema). Sincronizza in
  sottofondo i fogli salvati sul backend condiviso (merge additivo,
  disattivabile in Impostazioni → Backend condiviso). Al primo utilizzo
  (nessun link mai incollato) apre da solo il foglio del mese corrente se
  già pubblicato dall'associazione; frecce ← → per saltare al mese
  precedente/successivo tra i fogli salvati.
- ✅ **Tools → Lista ospedali**: ricerca ospedali per nome/via/città/regione,
  vista elenco raggruppata per regione, pulsante Naviga (Google Maps o
  Waze) e vista mappa con tutti gli ospedali geocodificati automaticamente
  (nessuna API key) o con coordinate/regione inserite a mano nel form
  Ospedale. Anagrafica ospedali esportabile/importabile a parte
  (Impostazioni → Ospedali), upsert per nome, senza toccare il resto dei
  dati. Ospedali scaricabili per città o per regione anche dal backend
  condiviso (`backend/`).
- ✅ **Tools → Repository formazione**: apre nel browser l'unico link
  condiviso ai materiali di formazione, impostato dalla pagina admin del
  backend condiviso. CONTENUTO RISERVATO: richiede login (account
  utente-app, creato solo dalla pagina admin).
- ✅ **Impostazioni → Account**: login/logout con le credenziali
  utente-app (create solo dalla pagina admin del backend condiviso, mai da
  questa app) che sbloccano i contenuti riservati (Repository formazione,
  Archivio comunicati); cambio password, obbligatorio al primo accesso con
  la password provvisoria data dall'admin, poi libero in ogni momento.
- ✅ **Impostazioni → Backend condiviso**: indirizzo del server (spostato da
  Lista ospedali) e interruttore per la sincronizzazione automatica dei
  fogli turni (default attivo).
- ✅ **Impostazioni → Navigazione**: scelta della pagina principale
  all'avvio (Attività, Tools o Piano turni), interruttore per disattivare/
  nascondere insieme le tab Attività (turni + assistenze) e Statistiche, e
  interruttore per spostare il tool Piano turni dalla tab Tools a una voce
  propria nella barra di navigazione.
- ✅ **Backend condiviso** (`backend/`, Go+PostgreSQL): API pubblica di sola
  lettura per ospedali (per città/regione), fogli turni e catalogo
  materiali + pagina admin (login) per gestirli uno alla volta o in blocco
  da file JSON, incorporato nell'immagine Docker della versione web. Gestisce
  anche gli account utente-app (contenuti riservati dell'app) e i comunicati
  PDF, entrambi creabili/caricabili SOLO dalla pagina admin.
- ✅ **Tutorial di navigazione**: overlay spotlight a schermo intero mostrato
  al primo avvio, un passo per ogni tab visibile in basso, rivedibile da
  Impostazioni → Navigazione.
- ✅ Windows desktop, web (Chrome/Edge), icona app personalizzata, 140 test unitari.
- ✅ **CI/Release**: build APK su GitHub Actions (runner GitHub-hosted),
  Release automatica sui tag `vX.Y.Z`.

## TODO

Le voci completate sono già documentate in Funzionalità implementate/Decisioni
tecniche e vengono rimosse da qui una volta chiuse, per non tenere in questo
elenco un changelog duplicato.

(La sincronizzazione completa dei dati dell'app con un backend non è più in
programma: il backend condiviso serve solo elenco ospedali, fogli turni e
catalogo materiali — vedi Decisioni tecniche — il backup JSON locale resta
l'unico modo per spostare i dati "vivi" — turni, persone, assistenze... —
tra device.)

Nessuna voce aperta al momento.