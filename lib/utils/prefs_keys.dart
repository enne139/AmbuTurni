// Chiavi SharedPreferences del tool Piano turni, centralizzate qui perché
// condivise tra la schermata (lettura/scrittura) e il backup (export/import:
// queste preferenze non stanno nel DB, ma senza di loro un restore su un
// device nuovo perderebbe l'archivio dei fogli mensili e il nome cercato).
const kPrefPianoTurniUrl = 'piano_turni_url';
const kPrefPianoTurniFogli = 'piano_turni_fogli'; // JSON: {"aaaa-mm": url}
const kPrefPianoTurniRuoliEsclusi = 'piano_turni_ruoli_esclusi';
const kPrefPianoTurniUltimaRicerca = 'piano_turni_ultima_ricerca';
// Mese dell'ultimo piano caricato ("aaaa-mm"): dice quale file di cache
// mostrare subito all'apertura, prima che il download aggiorni i dati.
// Non va nel backup: le cache sono locali al device e non vengono esportate.
const kPrefPianoTurniUltimoMese = 'piano_turni_ultimo_mese';
// Chiavi ("aaaa-mm") di fogli rimossi esplicitamente dai salvati: la
// sincronizzazione automatica dal backend condiviso (merge additivo) non
// deve "resuscitarli" alla riapertura successiva se il backend li ha
// ancora. Stato locale al device come kPrefPianoTurniUltimoMese, non va
// nel backup: su un device nuovo non c'è nulla da ricordare come rimosso.
const kPrefPianoTurniFogliRimossi = 'piano_turni_fogli_rimossi';

// Indirizzo del backend condiviso ospedali (tool Lista ospedali): assente =
// si usa kBackendUrlDefault, un dominio unico gestito centralmente.
// Sovrascrivibile per puntare a un backend locale/di test.
const kPrefBackendUrl = 'backend_url';
const kBackendUrlDefault = 'https://ambuturni.maratuck.com/';

// Sincronizzazione automatica dei fogli turni dal backend condiviso (tool
// Piano turni): assente = attiva (default true, vedi CLAUDE.md). Il backend
// li tiene solo in lettura per i client (scrittura riservata alla pagina
// admin), quindi qui basta un interruttore sì/no, non credenziali.
const kPrefSyncFogliAttivo = 'backend_sync_fogli_attivo';

// Navigazione principale (AppNavigator): quale tab è la "pagina principale"
// mostrata all'avvio ('attivita', 'tools' o 'piano_turni') e se le tab
// Attività (turni + assistenze) e Statistiche sono visibili del tutto.
// Default (entrambe le chiavi assenti, richiesta esplicita anche per device
// con dati già esistenti — nessuna versione precedente ha mai scritto
// queste chiavi, quindi non c'è un comportamento "storico" da preservare):
// Attività/Statistiche DISATTIVATE e Piano turni in navbar/pagina
// principale (vedi kPrefPianoTurniInNavbar sotto e NavigazioneProvider).
// Chi disattiva Attività/Statistiche mentre Attività è impostata come
// pagina principale la vede spostata automaticamente su Tools.
const kPrefPaginaPrincipale = 'pagina_principale';
const kPrefAttivitaStatisticheAttive = 'attivita_statistiche_attive';

// Sposta il tool Piano turni dalla tab Tools a una voce propria nella barra
// di navigazione (assente = true, default: vedi sopra): attivarla imposta
// anche Piano turni come pagina principale (richiesta esplicita),
// disattivarla ripiega la pagina principale su Attività/Tools se era
// impostata su Piano turni.
const kPrefPianoTurniInNavbar = 'piano_turni_in_navbar';

// Elenco (List<String>) degli ID dei tool attivi in Impostazioni → Tools
// attivi, vedi utils/tools_config.dart. Assente = mai salvato: si applicano
// i default del catalogo (attivoDiDefault). Una volta salvato riflette
// esattamente le scelte dell'utente, incluso nel backup come le altre preferenze.
const kPrefToolsAttivi = 'tools_attivi';
// Elenco (List<String>) degli ID di tool già "visti" da questo device (vedi
// ToolsProvider.carica): un id del catalogo assente da qui è un tool nuovo,
// mai proposto all'utente, a cui va applicato attivoDiDefault invece di
// considerarlo disattivato — altrimenti un tool aggiunto con default true
// resterebbe invisibile per chi ha già personalizzato Tools attivi in
// passato. Nel backup insieme a kPrefToolsAttivi: senza, un restore su un
// device nuovo tratterebbe come "nuovi" tutti i tool già noti sul device di
// origine, riattivando quelli disattivati esplicitamente prima del backup.
const kPrefToolsConosciuti = 'tools_conosciuti';

// Account "utente-app" (AccountProvider, widgets/accesso_richiesto.dart):
// sblocca i contenuti riservati dell'app (Repository formazione, Archivio
// comunicati). Credenziali create SOLO dalla pagina admin del backend
// condiviso, mai da questa app — qui si fa solo login/cambio password.
// Stato di sessione locale al device, come kPrefTutorialCompletato: NON va
// nel backup (db/backup.dart non le tocca), un JWT dentro un backup
// esportabile sarebbe anche un problema di sicurezza, non solo una
// preferenza da ripristinare altrove.
const kPrefAccountToken = 'account_token';
const kPrefAccountUsername = 'account_username';
// true finché la password provvisoria data dall'admin non è stata
// cambiata (vedi backend: utenti_app.deve_cambiare_password); persistito
// così un riavvio dell'app durante il cambio forzato lo ripropone invece
// di lasciar entrare nei contenuti riservati.
const kPrefAccountDeveCambiarePassword = 'account_deve_cambiare_password';

// Modalità di tema dell'app (Impostazioni → Aspetto, TemaProvider,
// ModalitaTema): bool nullable, non un bool semplice — assente = "sistema"
// (segue il tema del device), true/false = scelta esplicita chiara/scura.
// Preferenza di visualizzazione come quelle di Navigazione/Tools attivi
// (non locale al device come account/tutorial): inclusa nel backup, così il
// tema scelto segue il resto delle preferenze su un ripristino.
const kPrefModalitaChiara = 'modalita_chiara';

// Tutorial di navigazione a schermo intero (widgets/tutorial_overlay.dart,
// TutorialProvider): mostrato una sola volta al primo avvio, poi rivedibile
// dal pulsante in Impostazioni → Navigazione. Stato puramente locale al
// device, non va nel backup (come kPrefPianoTurniUltimoMese): su un device
// nuovo ripristinato da un backup ha senso rivedere comunque il tutorial.
const kPrefTutorialCompletato = 'tutorial_completato';
