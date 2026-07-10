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

// Elenco (List<String>) degli ID dei tool attivi in Impostazioni → Tools
// attivi, vedi utils/tools_config.dart. Assente = mai salvato: si applicano
// i default del catalogo (attivoDiDefault), non tutti abilitati (es. il
// Magazzino Verde parte disattivato). Una volta salvato riflette esattamente
// le scelte dell'utente, incluso nel backup come le altre preferenze.
const kPrefToolsAttivi = 'tools_attivi';
