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

// Chiavi del tool Magazzino Verde (URL del server e chiave API del device).
// Anche loro condivise col backup, per la stessa ragione: senza, un restore
// su un device nuovo costringerebbe a recuperare URL e chiave a mano.
const kPrefMagazzinoUrl = 'magazzino_url';
const kPrefMagazzinoApiKey = 'magazzino_api_key';

// Indirizzo del backend condiviso ospedali (tool Lista ospedali): assente =
// si usa kBackendUrlDefault, un dominio unico gestito centralmente (non
// serve configurazione come per Magazzino Verde, che non ha un default
// universale). Sovrascrivibile per puntare a un backend locale/di test.
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
// i default del catalogo (attivoDiDefault), non tutti abilitati (es. il
// Magazzino Verde parte disattivato). Una volta salvato riflette esattamente
// le scelte dell'utente, incluso nel backup come le altre preferenze.
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

// Tutorial di navigazione a schermo intero (widgets/tutorial_overlay.dart,
// TutorialProvider): mostrato una sola volta al primo avvio, poi rivedibile
// dal pulsante in Impostazioni → Navigazione. Stato puramente locale al
// device, non va nel backup (come kPrefPianoTurniUltimoMese): su un device
// nuovo ripristinato da un backup ha senso rivedere comunque il tutorial.
const kPrefTutorialCompletato = 'tutorial_completato';
