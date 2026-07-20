# TODO — problemi da sistemare

> Generato da una code review completa del progetto (analisi multi-agente, 2026-07-20).
> Il tool Magazzino Verde (incluso il bug fotocamera in Conta) è stato rimosso il
> 2026-07-20 — le voci che lo riguardavano sono state tolte da questo elenco.

## 🔴 Alta priorità

- [ ] **Perdita dati — upsert ospedali cancella via/città esistenti**
  `lib/db/helpers.dart` (`saveOspedale`/`upsertOspedali`): a differenza di
  lat/lng/regione (scritti "solo se valorizzati"), `via`/`citta` vengono sempre
  sovrascritti anche con `null`. Scaricare ospedali per città/regione dal backend,
  o importare un JSON di un'altra installazione senza `via` compilata, cancella
  silenziosamente indirizzi inseriti a mano. Fix: stesso pattern "scrivi solo se
  non vuoto" già usato per il geocoding.

- [ ] **`importBackup`: cast non protetti possono far crashare l'import**
  `lib/db/backup.dart:267-333` — `payload['version'] as int?`,
  `payload['tables'] as Map`, `rows as List` sono cast "duri" in mezzo a una
  funzione altrimenti molto difensiva. Un file manomesso con tipi diversi lancia
  un `TypeError` non gestito invece del messaggio "file non valido".

- [ ] **Import backup in Impostazioni: nessun try/catch → schermata bloccata per sempre**
  `lib/screens/impostazioni/impostazioni_screen.dart` (`_import`) — a differenza
  di `_export`, non cattura eccezioni: se `importBackup` lancia, `_busy` resta
  `true` per sempre e la UI resta bloccata sulla progress bar, recuperabile solo
  riavviando l'app.

- [ ] **Salvataggio servizio senza try/catch → form bloccato**
  `lib/screens/turni/servizio_form.dart:56-69` — un'eccezione in `saveServizio`
  lascia `_saving = true` per sempre, form inutilizzabile, dati persi.

- [ ] **Eliminazione servizio senza dialog di conferma**
  `lib/screens/turni/turno_detail.dart:58-61` — turno e assistenza hanno conferma
  esplicita, il servizio no: un tap impreciso sul menu a tre puntini lo cancella
  senza possibilità di annullare.

- [ ] **Backend: `JWT_SECRET` di default debole, nessun controllo all'avvio**
  `backend/auth.go:19` (stesso default in `docker-compose.yml`) — se ci si
  scorda di impostare `JWT_SECRET` in produzione, il server parte comunque senza
  avviso, e chiunque conosca il placeholder può firmarsi un JWT admin valido.
  Fix: `log.Fatal` se assente o coincide col default.

- [ ] **Backend: nessun limite alla dimensione del body JSON, incluso il login non autenticato**
  `backend/httputil.go:30-37` — `POST /api/auth/login` decodifica il body senza
  `http.MaxBytesReader`: DoS a basso costo, senza credenziali.

- [ ] **Piano turni: download XLSX da Google Sheets senza timeout**
  `lib/screens/tools/piano_turni_screen.dart:217-218` — unica chiamata di rete
  dell'app priva di `.timeout(...)`. Rete instabile → spinner a schermo intero
  bloccato indefinitamente, nessun errore, nessun modo di annullare.

- [ ] **Tutorial: nessuna protezione da chiamate concorrenti**
  `lib/widgets/tutorial_overlay.dart` + `lib/providers/app_provider.dart:343-346`
  — doppio tap rapido su "Rivedi tutorial" inserisce due `OverlayEntry`
  sovrapposte; quella sotto non riceve mai il tap di chiusura e resta uno scrim
  residuo che blocca l'interazione finché non si "bucano" entrambi gli overlay
  in sequenza.

## 🟠 Media priorità

- [ ] **Anagrafiche**: nessun try/catch su `saveAssociazione`/`saveOspedale`/
  `saveTipologiaTurno`/`savePersona` — con nomi `UNIQUE`, rinominare con un nome
  già esistente fallisce in silenzio (l'utente crede di aver salvato).
  `lib/screens/anagrafiche/anagrafiche_screen.dart`

- [ ] **Campo "Ore" accetta valori negativi**, che poi rompono `formatOre`
  (floor su negativi) e inquinano le statistiche aggregate.
  `lib/screens/turni/turno_form.dart:201-206` (stesso validator in
  `assistenza_form.dart:199-204`)

- [ ] **Piano turni**: race condition — "Cambia foglio" durante un refresh
  silenzioso può far ricomparire il piano appena cancellato mentre l'utente sta
  compilando il form nuovo. `lib/screens/tools/piano_turni_screen.dart:203-256`

- [ ] **Piano turni**: il merge additivo dei fogli dal backend può "resuscitare"
  un foglio che l'utente aveva rimosso esplicitamente dai salvati.
  `lib/screens/tools/piano_turni_screen.dart:148-165`

- [ ] **`backend_api.dart`**: `jsonDecode` non protetto su risposte 200 con
  body non-JSON (proxy/manutenzione) → eccezione grezza mostrata all'utente
  invece del messaggio pulito. `lib/utils/backend_api.dart:80,93,105,118,133`

- [ ] **`num_servizi` non ricalcolato dopo l'import backup** se righe `servizi`
  vengono scartate — badge "N serv." disallineato finché non si tocca il turno.
  `lib/db/backup.dart:326-354`

- [ ] **`upsertOspedali`/`upsertMateriali`**: nessuna transazione — centinaia di
  round-trip singoli per un download regione, non atomico.
  `lib/db/helpers.dart:159-210,694-717`

- [ ] **Indice mancante su `servizi.ospedale_id`** — "Vedi turni" di un ospedale
  fa scan completo della tabella servizi. `lib/db/database.dart` (richiede bump
  versione DB + migrazione in `_onUpgrade`)

- [ ] **`colorFromHex`**: un hex senza `#` viene interpretato come decimale
  invece di fallire → colore trasparente invisibile invece del fallback
  atteso. `lib/utils/theme.dart:14-21`

- [ ] **`CalendarioMensile<T>`** non risincronizza il mese mostrato se
  `giornoSelezionato` cambia da fuori senza rimontare il widget (bug latente,
  oggi mascherato). `lib/widgets/calendario_mensile.dart:56-60`

- [ ] **Card del tutorial** può clippare in landscape su schermi bassi durante
  i passi più lunghi (Piano turni). `lib/widgets/tutorial_overlay.dart:91-96`

- [ ] **Backend**: nessun rate limit sul login (bruteforce illimitato); tutte
  le query usano `context.Background()` invece di `r.Context()` (nessun timeout
  per-richiesta, rischio esaurimento pool); nessuna gestione/revoca utenti
  admin; timing side-channel per enumerare username validi.
  `backend/main.go`, `backend/auth.go`

- [ ] **Turni/assistenze**: `_carica` in vari form/detail senza try/catch →
  spinner infinito su errore imprevisto; frecce di riordino servizi non
  disabilitate durante l'operazione (tap multipli rapidi possono invertire
  l'ordine). `lib/screens/turni/turno_detail.dart`

## 🟡 Bassa priorità / ottimizzazioni

- [ ] `giorno` nel parser piano turni validato solo 1-31, non contro i giorni
  reali del mese. `lib/utils/piano_mensile.dart:284`
- [ ] Aggiornamento ottimistico senza rollback in `_variaQuantita`.
  `lib/screens/tools/materiali_usati_screen.dart:71-78`
- [ ] `tools_screen.dart`: mappa `_destinazioni` non sincronizzata staticamente
  col catalogo — footgun silenzioso per tool futuri.
- [ ] Duplicazione quasi identica tra `_ricalcolaNumerazioneTurni`/
  `_ricalcolaNumerazioneAssistenze` — occasione di unificazione.
  `lib/db/helpers.dart:422-437,615-631`
- [ ] Ricerca `LIKE` senza escape di `%`/`_` (solo UX, non injection).
  `lib/db/helpers.dart:296-297,531-532`
- [ ] `ToolsProvider.carica()` riscrive SharedPreferences a ogni avvio anche
  senza cambiamenti. `lib/providers/app_provider.dart:188-190`
- [ ] `CalendarioMensile` raggruppa l'intera lista ad ogni build invece di
  memoizzare. `lib/widgets/calendario_mensile.dart:79-84`
- [ ] `CodiceChip` non gestisce stringa vuota (solo `null`).
  `lib/widgets/codice_chip.dart:14`
- [ ] `withOpacity` deprecato ancora usato in `theme.dart`/`codice_chip.dart`
  (resto del progetto già su `withValues`).
- [ ] Backend: link ai fogli turni nella pagina admin non valida lo schema URL
  (self-XSS, richiede già JWT admin); chiave "aaaa-mm" non valida il range del
  mese (accetta "13"); nessun health check/restart automatico del processo
  backend nell'immagine Docker.
- [ ] Dipendenze con versioni più recenti disponibili (non urgente):
  `file_picker`, `share_plus`, `mobile_scanner`, `package_info_plus`, `intl`,
  `uuid`, `flutter_lints`.

## Nessun problema trovato in

Migrazioni DB (v1→v11 coerenti), leak di controller/FocusNode, gestione
`context.mounted` dopo `await` (quasi ovunque corretta), transazioni di
`importBackup`, rate limit Nominatim, dispose dello scanner in
`scanner_barcode_screen.dart`.
