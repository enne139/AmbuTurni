// Chiavi SharedPreferences del tool Piano turni, centralizzate qui perché
// condivise tra la schermata (lettura/scrittura) e il backup (export/import:
// queste preferenze non stanno nel DB, ma senza di loro un restore su un
// device nuovo perderebbe l'archivio dei fogli mensili e il nome cercato).
const kPrefPianoTurniUrl = 'piano_turni_url';
const kPrefPianoTurniFogli = 'piano_turni_fogli'; // JSON: {"aaaa-mm": url}
const kPrefPianoTurniRuoliEsclusi = 'piano_turni_ruoli_esclusi';
const kPrefPianoTurniUltimaRicerca = 'piano_turni_ultima_ricerca';
