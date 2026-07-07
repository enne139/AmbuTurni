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
   del tag fa pubblicare al workflow Gitea l'APK come artifact e come Release.

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
| Eventi calendario (Piano turni) | `add_2_calendar` (intent Android, nessun permesso) |
| Icona app | `flutter_launcher_icons` (dev dependency), genera Android+Windows da `assets/icon/` |
| Build | `flutter build apk` oppure workflow Gitea |

---

## Struttura cartelle

```
lib/
├── main.dart                      entry: init DB + MultiProvider + MaterialApp
├── utils/
│   ├── theme.dart                 buildDarkTheme(), getCodiceColor(), costanti colori
│   ├── format.dart                formatDate/Ore/parseOre/dateToIso + nomi mesi/giorni it
│   └── piano_mensile.dart         parser XLSX del piano turni mensile (Dart puro, testato)
├── db/
│   ├── database.dart              getDb() singleton sqflite, schema SQL, migrations
│   ├── models.dart                classi Dart (fromMap/toMap/copyWith) — 1:1 con le tabelle
│   ├── helpers.dart               TUTTE le funzioni CRUD + StatisticheData
│   └── backup.dart                exportBackup() + importBackup() via share_plus/file_picker
├── providers/
│   └── app_provider.dart          AnagraficheProvider, TurniProvider, AssistenzeProvider, StatisticheProvider
├── navigation/
│   └── app_navigator.dart         Scaffold con NavigationBar a 5 tab (IndexedStack)
├── widgets/
│   ├── codice_chip.dart           chip colorato per codici chiamata/uscita
│   ├── anag_pickers.dart          PersonaPicker, OspedalePicker, MaterialePicker (RawAutocomplete + Aggiungi...)
│   ├── turno_card.dart            TurnoCard: card condivisa tra turni_list e le viste filtrate
│   └── nota_markdown.dart         NotaMarkdown: rendering markdown delle note, stile coerente col tema scuro
└── screens/
    ├── shared/
    │   └── note_editor_screen.dart NoteEditorScreen: editor note a schermo intero, condiviso turno/assistenza
    ├── turni/
    │   ├── turni_list.dart         lista + FAB + filtro assoc. (niente swipe/long-press, v. Decisioni tecniche)
    │   ├── turni_calendario.dart   CalendarioTurni: vista calendario mensile (toggle in AppBar della lista)
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
    │   ├── tools_screen.dart          elenco strumenti extra (Materiali usati, Piano turni)
    │   ├── piano_turni_screen.dart    calendario equipaggi/buchi dal foglio Google dei turni
    │   ├── materiali_usati_screen.dart lista utilizzi attivi, stepper +/- quantità,
    │   │                               swipe elimina, ripristina (singolo/tutto)
    │   ├── materiale_usato_form.dart  form crea/modifica (materiale, quantità+unità, posizione, note)
    │   └── materiali_screen.dart      gestione catalogo materiali: FAB aggiungi/rinomina/elimina
    │                                   (doppioni case-insensitive bloccati: niente UNIQUE sul nome)
    └── impostazioni/
        ├── impostazioni_screen.dart CRUD assoc./persone/ospedali/tipologie + backup
        └── turni_filtrati_screen.dart TurniPersonaScreen/TurniOspedaleScreen: turni (e
                                        assistenze) in cui compare una persona/ospedale

backend/                            API sync Node+Express+PostgreSQL (invariata)
.gitea/workflows/build-backend.yml  CI Docker backend (solo su modifiche a backend/)
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
(versione corrente: 8); `_onOpen` esegue soltanto i PRAGMA di connessione
(WAL + foreign_keys).

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
  storico del tool HTML: ogni mese ha un suo foglio) con lista nel form e
  bottom sheet dall'AppBar, e ricerca volontario per nome
  (`PianoMensile.cercaNome`, tap sul risultato → il calendario salta al giorno).
- **Piano turni → "Aggiungi al calendario"** (branch `dev`): pulsante sulle
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
- **Piano turni → segnalino "nome cercato" sul calendario** (branch `dev`):
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
- **Backup v2: sezione `preferenze`** (branch `dev`): il backup completo
  include anche le preferenze del Piano turni (URL corrente, archivio
  "aaaa-mm" → URL dei fogli — come mappa decodificata, leggibile — e ultima
  ricerca volontario), che vivono in SharedPreferences e prima andavano
  perse nel restore su un device nuovo. Chiavi centralizzate in
  `utils/prefs_keys.dart` (condivise tra schermata e backup). L'import le
  ripristina solo se presenti e valide (backup v1/RN: le preferenze del
  device restano com'erano); la versione del formato è salita a 2 ma
  l'import continua ad accettare `>= 1`. I materiali NON c'entrano: erano
  già in `_backupTables` fin dalla loro introduzione. Il nome attivo è
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
- **Vista calendario custom, nessun package** (`turni_calendario.dart`): serve
  solo una griglia mese con marker colorati (pallini per associazione) e
  l'elenco del giorno selezionato — table_calendar & co. non giustificano la
  dipendenza (stessa politica di byId* vs package collection). Nomi di mesi e
  giorni hardcoded in italiano: l'app non usa flutter_localizations e tutte le
  stringhe sono già fisse in italiano. Il giorno selezionato è stato di
  `TurniList` (non del calendario) perché il FAB lo usa per precompilare
  `TurnoForm.dataIniziale`; la vista scelta (lista/calendario) persiste in
  shared_preferences. La ricerca testuale resta solo in vista lista: un
  risultato sparso su più mesi non ha una rappresentazione utile a calendario.
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
  pattern `carica`/`ricarica` degli altri; `ImpostazioniScreen._import()` lo ricarica.
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
- **`pubspec.lock` versionato**: raccomandazione Flutter per le app (non le
  librerie) — build riproducibili in CI; cache pub in CI su hash del lockfile.
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

---

## Funzionalità implementate

Dettagli/motivazioni dei punti più delicati sono in "Decisioni tecniche
rilevanti"; qui solo l'inventario di cosa esiste.

- ✅ **Turni**: lista con filtro/ricerca, form completo, dettaglio con servizi
  (CRUD + riordino, descrizione markdown), tipologie multi-select, numerazione automatica.
- ✅ **Vista calendario turni**: griglia mensile con pallini colorati per
  associazione, turni del giorno selezionato, FAB con data precompilata;
  toggle lista/calendario in AppBar, persistito tra i riavvii.
- ✅ **Equipaggio**: form 1ª/2ª parte con "Copia 1ª → 2ª"; affiancate per ruolo nel dettaglio.
- ✅ **Note** (turno/assistenza): card dedicata in markdown, editor a schermo intero.
- ✅ **Assistenze**: come i turni ma senza tipologia né servizi.
- ✅ **Statistiche**: 6 card aggregate, filtro associazione, si aggiornano anche dopo import.
- ✅ **Impostazioni**: CRUD anagrafiche, "Vedi turni" per persona/ospedale.
- ✅ **Backup**: export/import JSON completo e leggibile, nomi file con timestamp.
- ✅ **Combobox con creazione inline** per persone/ospedali/materiali.
- ✅ **Tools → Materiali usati**: catalogo + utilizzi (quantità/unità/posizione), nessuno storico.
- ✅ **Tools → Piano turni**: calendario equipaggi/buchi dal foglio Google
  mensile dell'associazione (pallini per fascia, dettaglio per blocco, filtri
  ruolo, aggiunta del turno al calendario di sistema).
- ✅ Windows desktop, icona app personalizzata, 29 test unitari.
- ✅ **CI/Release**: build APK su Gitea, Release automatica sui tag `vX.Y.Z`.

## TODO

Le voci completate sono già documentate in Funzionalità implementate/Decisioni
tecniche e vengono rimosse da qui una volta chiuse, per non tenere in questo
elenco un changelog duplicato.

- [ ] Sincronizzazione backend (syncManager) — tabelle `sync_meta` e `deletions` già esistono