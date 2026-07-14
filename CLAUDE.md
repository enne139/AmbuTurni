# CLAUDE.md — Guida per le chiamate IA

> Questo è il rewrite completo in Flutter dell'app originale React Native / Expo.
> Il rewrite è stato integrato su `main` (2026-07-01). Il backend Node+Express
> in `backend/` è condiviso e non cambia.

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
   del tag fa pubblicare al workflow Gitea l'APK come artifact e come Release,
   e pubblica anche l'immagine Docker della versione web (build-web.yml) con
   un tag pari alla versione — il deploy sul server resta comunque manuale.

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
| Scansione barcode/QR (Magazzino) | `mobile_scanner` (Android/iOS/web; il FAB Scansiona non esiste su desktop nativo) |
| Mappa (Lista ospedali) | `flutter_map` + `latlong2`, tile OpenStreetMap, nessuna API key (funziona anche su Windows/web) |
| Geocoding indirizzi (Lista ospedali) | Nominatim (OpenStreetMap), nessuna API key, chiamato solo alla creazione/modifica di un ospedale |
| Apertura navigatore esterno (Lista ospedali) | `url_launcher`, link universale Google Maps |
| Icona app | `flutter_launcher_icons` (dev dependency), genera Android+Windows+web da `assets/icon/` |
| Versione app a runtime | `package_info_plus` (legge X.Y.Z+N dalla piattaforma, mostrata in Impostazioni) |
| Build | `flutter build apk` oppure workflow Gitea |

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
│   ├── magazzino_api.dart         client dell'API JSON del gestionale Magazzino Verde
│   │                               (Dart puro, testato con MockClient)
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
│   ├── prefs_keys.dart            chiavi SharedPreferences condivise col backup
│   │                               (Piano turni + Magazzino Verde + Tools attivi)
│   ├── scanner_errors.dart        messaggio d'errore fotocamera per mobile_scanner,
│   │                               condiviso tra scanner_barcode_screen e conta_screen
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
│                                   StatisticheProvider, ToolsProvider
├── navigation/
│   └── app_navigator.dart         Scaffold con NavigationBar a 4 tab (IndexedStack);
│                                   la tab Attività unisce Turni e Assistenze con un
│                                   SegmentedButton sotto l'AppBar
├── widgets/
│   ├── codice_chip.dart           chip colorato per codici chiamata/uscita
│   ├── anag_pickers.dart          PersonaPicker, OspedalePicker, MaterialePicker (RawAutocomplete + Aggiungi...)
│   ├── calendario_mensile.dart    CalendarioMensile<T>: vista calendario generica (turni e assistenze)
│   ├── turno_card.dart            TurnoCard: card condivisa tra turni_list e le viste filtrate
│   └── nota_markdown.dart         NotaMarkdown: rendering markdown delle note, stile coerente col tema scuro
└── screens/
    ├── shared/
    │   └── note_editor_screen.dart NoteEditorScreen: editor note a schermo intero, condiviso turno/assistenza
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
    │   │                               Magazzino Verde), filtrato dai tool attivi (ToolsProvider)
    │   ├── piano_turni_screen.dart    calendario equipaggi/buchi dal foglio Google dei turni
    │   ├── magazzino_screen.dart      giacenze e movimenti carico/scarico dal gestionale
    │   │                               esterno Magazzino Verde (API JSON con chiave)
    │   ├── lista_ospedali_screen.dart cerca ospedali per nome/via/città, pulsante Naviga
    │   │                               (apre Google Maps esterno) e vista mappa con tutti
    │   │                               gli ospedali geocodificati (flutter_map + OSM)
    │   ├── scanner_barcode_screen.dart scanner barcode/QR a schermo intero (mobile_scanner),
    │   │                               pop col codice letto; aperto solo dietro !isDesktop
    │   ├── conta_screen.dart          contatore rapido indipendente dall'API: manuale
    │   │                               (pulsanti grandi +1/-1) o a scansione continua
    │   ├── materiali_usati_screen.dart lista utilizzi attivi, stepper +/- quantità,
    │   │                               swipe elimina, ripristina (singolo/tutto)
    │   ├── materiale_usato_form.dart  form crea/modifica (materiale, quantità+unità, posizione, note)
    │   └── materiali_screen.dart      gestione catalogo materiali: FAB aggiungi/rinomina/elimina
    │                                   (doppioni case-insensitive bloccati: niente UNIQUE sul nome)
    └── impostazioni/
        ├── impostazioni_screen.dart CRUD assoc./persone/ospedali/tipologie + backup + versione app
        └── turni_filtrati_screen.dart TurniPersonaScreen/TurniOspedaleScreen: turni (e
                                        assistenze) in cui compare una persona/ospedale

backend/                            API sync Node+Express+PostgreSQL (invariata)
.gitea/workflows/build-backend.yml  CI Docker backend (solo su modifiche a backend/)
.gitea/workflows/build-web.yml      CI Docker versione web (build Flutter + nginx)
Dockerfile                          build multi-stage versione web (root: serve tutto il progetto)
nginx.conf                          config nginx della versione web (SPA fallback + cache statica)
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
`tipologie_assistenza`, `turni`, `servizi`, `assistenze`, `sync_meta`, `deletions`.

`materiali` e `materiali_usati` (introdotte in versione DB 4, branch `feature/tools`)
non esistevano nell'app React Native. Sono incluse nel backup JSON
(`_backupTables` in `backup.dart`): un vecchio backup RN importato qui le
lascia semplicemente assenti.

Il DB è un singleton (`getDb()` in `database.dart`) aperto all'avvio in `main()`.
Le migrazioni vivono SOLO nel sistema versionato `_onCreate`/`_onUpgrade`
(versione corrente: 9); `_onOpen` esegue soltanto i PRAGMA di connessione
(WAL + foreign_keys).

`ospedali` ha anche `via` (indirizzo testuale) e `lat`/`lng` (coordinate da
geocoding automatico, v9): vedi il tool "Lista ospedali" in Decisioni tecniche.

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
la build fallisce con "AGP/Gradle/KGP version too low"). Il workflow Gitea
(`build-android.yml`) usa `flutter build apk`.

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
- **Tool "Magazzino Verde"** (`magazzino_screen.dart` +
  `utils/magazzino_api.dart`): si collega al gestionale di magazzino esterno
  dell'utente (progetto Go separato, stessa istanza Gitea del backend) via la
  sua API JSON (`/api/v1`, header `X-API-Key`). Client Dart puro come
  `piano_mensile.dart`, unit-testato con `MockClient` di
  `package:http/testing` (nessun server vero nei test); usa la lista
  materiali, la POST movimenti per ID e la GET per codice a barre (solo come
  fallback della scansione, vedi bullet successivo — nella ricerca testuale
  i codici si confrontano sulla lista già scaricata, si possono digitare le
  cifre del barcode). UI: lista giacenze con evidenza rossa
  "sotto scorta" (giacenza <= soglia di allerta, stesso criterio della home
  web del gestionale) e chip-filtro col conteggio; tap su un materiale →
  bottom sheet carico/scarico con stepper/campo quantità. La POST parte
  dallo sheet, che si chiude solo a successo (un errore resta visibile
  accanto ai pulsanti) restituendo il materiale aggiornato dalla risposta
  201: si aggiorna la sola riga toccata, senza ricaricare la lista, e il
  verso mostrato nello snackbar è dedotto dalla giacenza prima/dopo (dato
  confermato dal server). Configurazione URL+chiave API in SharedPreferences
  (`kPrefMagazzino*` in `prefs_keys.dart`), inclusa nella sezione
  `preferenze` del backup — chiave API compresa, scelta deliberata: il
  backup completo serve al trasferimento su device nuovo e senza chiave il
  tool resterebbe scollegato — senza bump del formato (ogni chiave della
  sezione è opzionale, i backup vecchi restano validi). Limite noto su web:
  la chiamata dal browser richiede che il server esponga gli header CORS —
  vincolo lato server, non aggirabile dal client Flutter.
- **Magazzino → scansione barcode/QR su mobile e web**
  (`scanner_barcode_screen.dart`, package `mobile_scanner`): FAB "Scansiona"
  nella schermata Magazzino su Android/iOS **e** web, dietro `!isDesktop`
  (il plugin non ha canale per desktop nativo — a differenza di
  add_2_calendar nel Piano turni, che sul web non ha alternativa e resta
  mobile-only). Lo scanner è una schermata generica che fa pop col primo
  codice letto (guard anti-pop-multipli: `onDetect` arriva a raffica finché
  il codice resta inquadrato), con torcia in AppBar (nascosta su web con
  `kIsWeb`: `toggleTorch()` lancia `UnsupportedError` lì, i video track del
  browser non espongono il controllo torcia) e `errorBuilder` per il
  permesso fotocamera negato, con testo diverso tra le due piattaforme
  (impostazioni di sistema dell'app su mobile, impostazioni del sito nel
  browser su web) più un messaggio dedicato per browser non supportato.
  Il permesso CAMERA NON va aggiunto al manifest Android dell'app: sta nel
  manifest del plugin e il manifest merger lo porta nell'APK anche in
  release (verificato nel sorgente del package — non è il caso di INTERNET,
  che era iniettato dal tooling solo in debug); la richiesta runtime la
  gestisce il plugin. Sul web la richiesta è quella nativa del browser
  (`getUserMedia`), che **richiede un contesto sicuro (HTTPS o localhost)**
  — stesso vincolo già noto del login in produzione (`ENV=production`),
  nessun requisito nuovo per il deploy; la libreria di decodifica (ZXing)
  viene caricata da uno script esterno al primo uso (dalla v5 del plugin
  nessuna configurazione in `index.html` necessaria), quindi la prima
  scansione su web richiede una connessione di rete funzionante anche col
  server Magazzino Verde già raggiungibile. Flusso dopo la lettura: match
  locale sui `codes` della lista già scaricata (immediato), poi
  `GET /materials/code/{code}` come fallback per materiali/codici associati
  dopo l'ultimo refresh — il 404 qui non è un guasto ma "codice non
  associato" (messaggio dedicato, distinto tramite il campo `statusCode` di
  `MagazzinoApiException`); trovato il materiale si apre direttamente lo
  sheet carico/scarico (flusso scanner del Raspberry: scansiona →
  registra). Un materiale arrivato dal fallback e assente dalla lista viene
  inserito in ordine alfabetico dopo il movimento. mobile_scanner richiede
  Android SDK Platform 35 installata (la build la scarica da sola).
- **Magazzino → "Conta"** (`conta_screen.dart`, pulsante `Icons.numbers` in
  AppBar): contatore rapido scollegato dall'API — nessun materiale
  selezionato, nessuna giacenza toccata, solo un numero che sale/scende.
  Sempre raggiungibile anche a server non configurato (`_api == null`),
  a differenza del resto della schermata. Due modalità, cambiate da un
  pulsante in AppBar: manuale (due pulsanti grandi +1/-1, pensati per essere
  premuti anche con i guanti o tenendo in mano delle scatole — il -1 è
  disabilitato sotto zero, un conteggio fisico non è mai negativo) e
  scansione (ogni codice a barre/QR inquadrato incrementa di 1, per contare
  oggetti che passano davanti alla fotocamera). In scansione un cooldown di
  1200ms tra un conteggio e il successivo evita di contare più volte lo
  stesso codice se resta a lungo davanti alla fotocamera (`onDetect` arriva
  a raffica finché è a fuoco) — a differenza dello scanner di lookup del
  Magazzino, qui la fotocamera resta aperta e si continua a contare finché
  l'utente non torna alla modalità manuale, quindi non basta il guard "solo
  la prima lettura". Il pulsante per cambiare modalità è nascosto su
  desktop nativo (`isDesktop`, mobile_scanner non ha canale lì): la
  modalità manuale invece funziona ovunque, quindi il contatore resta
  sempre raggiungibile. Il messaggio d'errore fotocamera (permesso negato,
  browser non supportato) è condiviso con `scanner_barcode_screen.dart`
  tramite `utils/scanner_errors.dart` invece di duplicarlo.
- **Impostazioni → Tools attivi** (`_SezioneToolsAttivi`, `ToolsProvider`,
  `utils/tools_config.dart`): switch per attivare/disattivare i tool
  mostrati nella tab Tools. Il Magazzino Verde parte **disattivato di
  default** (`attivoDiDefault: false` nel catalogo): si collega a un server
  esterno da configurare, non è utile finché non lo si imposta — meglio non
  ingombrare la lista finché non lo si attiva esplicitamente; gli altri
  tool sono attivi di default. Catalogo (id, titolo, sottotitolo, icona,
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
- **Permesso INTERNET nel manifest Android (v1.3.1)**: le build debug lo
  includono automaticamente, le release no — il Piano turni (prima feature di
  rete su main) falliva con "Failed host lookup" solo sull'APK release.
  Stessa lezione del PRAGMA WAL: i bug di piattaforma vanno verificati con
  una build release su Android reale, non solo in debug/desktop.
- **Vista calendario custom, nessun package** (`widgets/calendario_mensile.dart`):
  serve solo una griglia mese con marker colorati (pallini per associazione) e
  l'elenco del giorno selezionato — table_calendar & co. non giustificano la
  dipendenza (stessa politica di byId* vs package collection). Nomi di mesi e
  giorni hardcoded in italiano: l'app non usa flutter_localizations e tutte le
  stringhe sono già fisse in italiano. Il giorno selezionato è stato della
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
- **Pubblicazione web: immagine Docker (nginx), stesso pattern del backend**
  (`Dockerfile` alla radice + `.gitea/workflows/build-web.yml`): build
  multi-stage, stage 1 `ghcr.io/cirruslabs/flutter:3.44.0` (stessa immagine
  pinnata della CI Android, include già il setup di
  `sqflite_common_ffi_web:setup` non versionato) compila `flutter build web
  --release`, stage 2 `nginx:alpine` copia solo l'output statico —
  nell'immagine finale non c'è il toolchain Flutter. Pubblicata sul
  Container Registry della stessa istanza Gitea del backend
  (`ambuturni-web`, accanto a `ambulanza-sync`), riusando lo stesso secret
  `REGISTRY_TOKEN`. Trigger sui tag `vX.Y.Z` (come `build-android.yml`, non
  a ogni push su `main`: la web app segue lo stesso versionamento
  dell'APK), immagine taggata sia `latest`/SHA sia col nome del tag —
  permette di puntare sul server a una versione precisa. Deploy sul server
  manuale, come già per il backend — il workflow si ferma al push
  dell'immagine. `nginx.conf`: fallback SPA
  (`try_files` su `index.html`) e cache lunga solo sugli asset con hash nel
  nome (`main.dart.js`, `assets/*`), `index.html` sempre rivalidato perché è
  lui a referenziare l'hash aggiornato a ogni build.
- **`pubspec.lock` versionato**: raccomandazione Flutter per le app (non le
  librerie) — build riproducibili in CI. Gli step actions/cache (Gradle/pub)
  sono stati rimossi dal workflow: senza cache backend sull'istanza Gitea
  facevano solo cache-miss silenziosi.
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
  debug. In CI arriva dai secret Gitea `KEYSTORE_B64`/`KEYSTORE_PASSWORD`. Le
  release passate (v1.0.0, v1.1.0) sono state ri-firmate per uniformità: gli
  update via Obtainium richiedono la stessa firma tra versioni.
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
  true`): non richiede alcuna configurazione, a differenza del Magazzino Verde.
  Tre decisioni "nessuna API key", coerenti con Piano turni/Magazzino Verde:
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
    un plugin nativo (a differenza di mobile_scanner/add_2_calendar), solo
    rendering + richieste HTTP delle tile.
  - **Geocoding automatico via Nominatim** (`GeocodingApi.geocodifica`, Dart
    puro e testato con `MockClient` come `magazzino_api.dart`): risolve
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
    coordinate: in Lista ospedali un'icona sulla riga permette di ritentare
    sul posto senza riaprire il form. Il form Ospedale ha anche due campi
    "Latitudine"/"Longitudine" opzionali (accettano sia punto che virgola
    come separatore decimale) per inserirle a mano — utile per una posizione
    più precisa di quella trovata da Nominatim (es. l'ingresso ambulanze
    invece del centroide dell'edificio) o quando l'indirizzo non è
    geocodificabile: se compilati hanno priorità e saltano del tutto il
    geocoding automatico.
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
  richieste a Nominatim che ne violerebbe la policy (max 1/s) — chi vuole
  geocodificare un ospedale arrivato senza coordinate può comunque ritentare
  singolarmente dal pulsante già presente in Lista ospedali. Non testato
  (come `exportBackup`/`importBackup`, che dipendono dal file picker reale):
  stesso limite già accettato per quelle funzioni.
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
- ✅ **Impostazioni**: CRUD anagrafiche, "Vedi turni" per persona/ospedale,
  Tools attivi (attiva/disattiva i tool mostrati in Tools).
- ✅ **Backup**: export/import JSON completo e leggibile, nomi file con timestamp.
- ✅ **Combobox con creazione inline** per persone/ospedali/materiali.
- ✅ **Tools → Materiali usati**: catalogo + utilizzi (quantità/unità/posizione), nessuno storico.
- ✅ **Tools → Piano turni**: calendario equipaggi/buchi dal foglio Google
  mensile dell'associazione (pallini per fascia, dettaglio per blocco, filtri
  ruolo, aggiunta del turno al calendario di sistema).
- ✅ **Tools → Magazzino Verde**: giacenze e movimenti carico/scarico dal
  gestionale di magazzino esterno (API JSON con chiave, evidenza sotto
  scorta, scansione barcode/QR su mobile e web, contatore rapido manuale
  o a scansione scollegato dall'API).
- ✅ **Tools → Lista ospedali**: ricerca ospedali per nome/via/città,
  pulsante Naviga (Google Maps o Waze) e vista mappa con tutti gli ospedali
  geocodificati automaticamente (nessuna API key) o con coordinate inserite
  a mano nel form Ospedale. Anagrafica ospedali esportabile/importabile a
  parte (Impostazioni → Ospedali), upsert per nome, senza toccare il resto
  dei dati.
- ✅ Windows desktop, web (Chrome/Edge), icona app personalizzata, 101 test unitari.
- ✅ **CI/Release**: build APK su Gitea, Release automatica sui tag `vX.Y.Z`.

## TODO

Le voci completate sono già documentate in Funzionalità implementate/Decisioni
tecniche e vengono rimosse da qui una volta chiuse, per non tenere in questo
elenco un changelog duplicato.

- [ ] Sincronizzazione backend (syncManager) — tabelle `sync_meta` e `deletions` già esistono