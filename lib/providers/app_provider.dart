import 'package:flutter/foundation.dart' show debugPrint, listEquals;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/helpers.dart';
import '../db/models.dart';
import '../utils/backend_api.dart';
import '../utils/prefs_keys.dart';
import '../utils/tools_config.dart';

/// Provider per le anagrafiche (associazioni, persone, ospedali, tipologie).
/// Caricato all'avvio in AppNavigator e richiamato dopo ogni modifica nelle
/// Impostazioni; i widget che mostrano nomi al posto di ID lo leggono in sola lettura.
class AnagraficheProvider extends ChangeNotifier {
  List<Associazione> associazioni = [];
  List<Persona> persone = [];
  List<Ospedale> ospedali = [];
  List<TipologiaTurno> tipologieTurno = [];
  bool _caricato = false;

  // Quante volte ogni voce compare in turni/assistenze/servizi (id -> conteggio),
  // mostrato come badge accanto a ogni voce in AnagraficheScreen. Mappe separate
  // da carica() (sotto) perché vanno ricalcolate anche a ogni salvataggio di un
  // turno/un'assistenza, non solo quando cambiano le anagrafiche stesse — vedi
  // ricaricaConteggi().
  Map<String, int> conteggioAssociazioni = {};
  Map<String, int> conteggioPersone = {};
  Map<String, int> conteggioOspedali = {};
  Map<String, int> conteggioTipologie = {};

  // Ogni load è indipendente: se una query fallisce (es. migrazione DB non ancora
  // applicata) le altre continuano e notifyListeners() viene chiamato comunque.
  // Gli errori vengono comunque loggati: un catch completamente muto mascherava
  // eventuali problemi reali del DB (liste vuote senza alcuna traccia del perché).
  Future<void> carica() async {
    try { associazioni = await getAssociazioni(); } catch (e) { debugPrint('[anagrafiche] associazioni non caricate: $e'); }
    try { persone = await getPersone(); } catch (e) { debugPrint('[anagrafiche] persone non caricate: $e'); }
    try { ospedali = await getOspedali(); } catch (e) { debugPrint('[anagrafiche] ospedali non caricati: $e'); }
    try { tipologieTurno = await getTipologieTurno(); } catch (e) { debugPrint('[anagrafiche] tipologie non caricate: $e'); }
    await _caricaConteggi();
    _caricato = true;
    notifyListeners();
  }

  /// Ricalcola solo i conteggi d'uso, senza ricaricare le liste anagrafiche
  /// (che non cambiano quando si salva un turno/un'assistenza). Da chiamare
  /// negli stessi punti in cui TurniList/AssistenzeList già ricaricano
  /// StatisticheProvider dopo essere tornate da un form/dettaglio: senza,
  /// i contatori resterebbero quelli di prima finché non si tocca
  /// un'anagrafica, dato che AnagraficheScreen resta montata nell'IndexedStack.
  Future<void> ricaricaConteggi() async {
    await _caricaConteggi();
    notifyListeners();
  }

  Future<void> _caricaConteggi() async {
    try { conteggioAssociazioni = await contaOccorrenzeAssociazioni(); } catch (e) { debugPrint('[anagrafiche] conteggio associazioni non calcolato: $e'); }
    try { conteggioPersone = await contaOccorrenzePersone(); } catch (e) { debugPrint('[anagrafiche] conteggio persone non calcolato: $e'); }
    try { conteggioOspedali = await contaOccorrenzeOspedali(); } catch (e) { debugPrint('[anagrafiche] conteggio ospedali non calcolato: $e'); }
    try { conteggioTipologie = await contaOccorrenzeTipologie(); } catch (e) { debugPrint('[anagrafiche] conteggio tipologie non calcolato: $e'); }
  }

  bool get caricato => _caricato;

  // I metodi byId* usano try/catch invece di firstWhereOrNull perché quest'ultimo
  // richiede il package collection; evitare dipendenze extra mantiene il pubspec pulito.

  Associazione? byIdAssociazione(String? id) {
    if (id == null) return null;
    try {
      return associazioni.firstWhere((a) => a.id == id);
    } catch (_) {
      return null;
    }
  }

  Persona? byIdPersona(String? id) {
    if (id == null) return null;
    try {
      return persone.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  Ospedale? byIdOspedale(String? id) {
    if (id == null) return null;
    try {
      return ospedali.firstWhere((o) => o.id == id);
    } catch (_) {
      return null;
    }
  }

  TipologiaTurno? byIdTipologia(String? id) {
    if (id == null) return null;
    try {
      return tipologieTurno.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }
}

/// Provider per la lista turni. Mantiene il filtro associazione e la ricerca
/// testuale attivi tra una navigazione e l'altra (ricarica() li riusa senza
/// doverli ripassare).
class TurniProvider extends ChangeNotifier {
  List<Turno> turni = [];
  String? _filtroAssociazioneId;
  String? _ricerca;

  String? get filtroAssociazioneId => _filtroAssociazioneId;
  String? get ricerca => _ricerca;

  Future<void> carica({String? associazioneId, String? ricerca}) async {
    _filtroAssociazioneId = associazioneId;
    _ricerca = ricerca;
    turni = await getTurni(associazioneId: associazioneId, ricerca: ricerca);
    notifyListeners();
  }

  /// Ricarica con lo stesso filtro/ricerca già impostati (usato dopo create/edit/delete).
  Future<void> ricarica() async {
    turni = await getTurni(associazioneId: _filtroAssociazioneId, ricerca: _ricerca);
    notifyListeners();
  }
}

/// Provider per le statistiche aggregate. Stesso pattern di TurniProvider
/// (mantiene il filtro associazione tra un caricamento e l'altro). Introdotto
/// per risolvere il mancato aggiornamento delle ore dopo un import backup:
/// prima StatisticheScreen caricava i dati una sola volta in uno stato locale
/// mai invalidato da altre schermate (l'IndexedStack di AppNavigator tiene
/// tutte le tab montate, quindi cambiare tab non la ricostruiva).
class StatisticheProvider extends ChangeNotifier {
  StatisticheData? dati;
  String? _filtroAssociazioneId;

  String? get filtroAssociazioneId => _filtroAssociazioneId;
  bool get caricato => dati != null;

  Future<void> carica({String? associazioneId}) async {
    _filtroAssociazioneId = associazioneId;
    dati = await getStatistiche(associazioneId: associazioneId);
    notifyListeners();
  }

  /// Ricarica con lo stesso filtro già impostato (usato dopo l'import backup).
  Future<void> ricarica() async {
    dati = await getStatistiche(associazioneId: _filtroAssociazioneId);
    notifyListeners();
  }
}

/// Provider per la lista assistenze. Stesso pattern di TurniProvider
/// (filtro associazione + ricerca testuale mantenuti tra le navigazioni).
class AssistenzeProvider extends ChangeNotifier {
  List<Assistenza> assistenze = [];
  String? _filtroAssociazioneId;
  String? _ricerca;

  String? get filtroAssociazioneId => _filtroAssociazioneId;
  String? get ricerca => _ricerca;

  Future<void> carica({String? associazioneId, String? ricerca}) async {
    _filtroAssociazioneId = associazioneId;
    _ricerca = ricerca;
    assistenze = await getAssistenze(associazioneId: associazioneId, ricerca: ricerca);
    notifyListeners();
  }

  /// Ricarica con lo stesso filtro/ricerca già impostati.
  Future<void> ricarica() async {
    assistenze = await getAssistenze(
        associazioneId: _filtroAssociazioneId, ricerca: _ricerca);
    notifyListeners();
  }
}

/// Provider per quali tool (Materiali usati, Piano turni, Lista ospedali...)
/// sono attivi nella tab Tools, scelti da Impostazioni → Tools attivi.
/// Stesso motivo di StatisticheProvider: ToolsScreen e ImpostazioniScreen
/// restano entrambe montate nell'IndexedStack di AppNavigator, quindi uno
/// switch cambiato in Impostazioni non farebbe ricostruire da solo la lista
/// già mostrata in Tools senza un provider condiviso che le tiene allineate.
class ToolsProvider extends ChangeNotifier {
  Set<String> _attivi = {};
  bool _caricato = false;

  bool get caricato => _caricato;

  bool attivo(String id) => _attivi.contains(id);

  /// Se la preferenza non è mai stata salvata si applicano i default del
  /// catalogo (kToolsDisponibili).
  /// Un tool presente nel catalogo ma assente da kPrefToolsConosciuti (mai
  /// proposto prima su questo device, es. un tool aggiunto in un
  /// aggiornamento successivo) prende anche lui il proprio default invece di
  /// essere considerato disattivato: altrimenti un id nuovo con
  /// attivoDiDefault true resterebbe invisibile per chi ha già personalizzato
  /// Tools attivi in passato (kPrefToolsAttivi salvato non conterrebbe quell'id
  /// semplicemente perché non esisteva ancora quando è stato scritto).
  Future<void> carica() async {
    final prefs = await SharedPreferences.getInstance();
    final salvati = prefs.getStringList(kPrefToolsAttivi);
    final conosciuti = prefs.getStringList(kPrefToolsConosciuti)?.toSet() ?? {};
    if (salvati == null) {
      _attivi = {for (final t in kToolsDisponibili) if (t.attivoDiDefault) t.id};
    } else {
      _attivi = salvati.toSet();
      for (final t in kToolsDisponibili) {
        if (!conosciuti.contains(t.id) && t.attivoDiDefault) _attivi.add(t.id);
      }
    }
    // Persiste subito lo stato risolto: i tool appena "scoperti" qui sopra
    // diventano noti, così uno spegnimento esplicito futuro viene rispettato
    // invece di essere ririconosciuto come "nuovo" a ogni avvio. Scrive solo
    // se il risultato differisce da quanto già salvato: senza questo
    // confronto, ogni avvio dell'app riscriverebbe due List<String> in
    // SharedPreferences anche a parità di contenuto.
    final attiviOrdinati = _attivi.toList()..sort();
    final salvatiOrdinati = (salvati ?? const <String>[]).toList()..sort();
    if (!listEquals(attiviOrdinati, salvatiOrdinati)) {
      await prefs.setStringList(kPrefToolsAttivi, _attivi.toList());
    }
    final conosciutiAttesi = kToolsDisponibili.map((t) => t.id).toList()..sort();
    final conosciutiOrdinati = (prefs.getStringList(kPrefToolsConosciuti) ?? const <String>[]).toList()..sort();
    if (!listEquals(conosciutiAttesi, conosciutiOrdinati)) {
      await prefs.setStringList(
          kPrefToolsConosciuti, kToolsDisponibili.map((t) => t.id).toList());
    }
    _caricato = true;
    notifyListeners();
  }

  Future<void> setAttivo(String id, bool valore) async {
    if (valore) {
      _attivi.add(id);
    } else {
      _attivi.remove(id);
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(kPrefToolsAttivi, _attivi.toList());
  }
}

/// Le pagine tra cui si può scegliere come "pagina principale" mostrata
/// all'avvio (Impostazioni → Navigazione). Statistiche e Impostazioni non
/// sono proponibili come home: sono destinazioni secondarie, non un punto
/// di partenza sensato per aprire l'app. `pianoTurni` è selezionabile solo
/// quando il tool è stato spostato in navbar (kPrefPianoTurniInNavbar).
enum PaginaPrincipale { attivita, tools, pianoTurni }

/// Converte [PaginaPrincipale] nella stringa persistita in
/// kPrefPaginaPrincipale, e viceversa (usata sia da carica() sia dai setter,
/// per non duplicare l'encoding in più punti).
String _paginaAStringa(PaginaPrincipale p) => switch (p) {
      PaginaPrincipale.tools => 'tools',
      PaginaPrincipale.pianoTurni => 'piano_turni',
      PaginaPrincipale.attivita => 'attivita',
    };

PaginaPrincipale _paginaDaStringa(String? s) => switch (s) {
      'tools' => PaginaPrincipale.tools,
      'attivita' => PaginaPrincipale.attivita,
      _ => PaginaPrincipale.pianoTurni,
    };

/// Provider per le impostazioni di navigazione (AppNavigator): quale pagina
/// è la "home" mostrata all'avvio, se le tab Attività (turni + assistenze) e
/// Statistiche sono visibili (un solo interruttore per entrambe: le
/// statistiche aggregano proprio i dati di turni/assistenze, quindi senza
/// Attività non avrebbero nulla da mostrare) e se il tool Piano turni è
/// spostato dalla tab Tools a una voce propria in navbar. Stesso motivo di
/// ToolsProvider: AppNavigator, ToolsScreen e ImpostazioniScreen restano
/// tutte montate nell'IndexedStack, quindi uno switch cambiato in
/// Impostazioni non farebbe aggiornare da soli la NavigationBar/la lista
/// Tools già mostrate senza un provider condiviso.
/// **Default (assente qualunque preferenza salvata, anche su un device con
/// dati già esistenti): Attività/Statistiche disattivate, Piano turni in
/// navbar e come pagina principale** — richiesta esplicita dell'utente,
/// non il comportamento "storico" (che sarebbe stato Attività attiva/pagina
/// principale): dato che nessuna versione con queste preferenze è mai stata
/// rilasciata, non c'è alcun device che le abbia già scritte, quindi
/// cambiare qui il fallback si applica a tutti, dati compresi (i dati non
/// vengono toccati: solo la tab da cui si parte cambia).
class NavigazioneProvider extends ChangeNotifier {
  bool _attivitaStatisticheAttive = false;
  bool _pianoTurniInNavbar = true;
  PaginaPrincipale _paginaPrincipale = PaginaPrincipale.pianoTurni;
  bool _caricato = false;

  bool get caricato => _caricato;
  bool get attivitaStatisticheAttive => _attivitaStatisticheAttive;
  bool get pianoTurniInNavbar => _pianoTurniInNavbar;
  PaginaPrincipale get paginaPrincipale => _paginaPrincipale;

  /// true se [pagina] corrisponde a una tab attualmente visibile in navbar:
  /// usata per correggere una pagina principale salvata ma non più valida
  /// (es. Attività scelta come home e poi disattivata).
  bool _paginaValida(PaginaPrincipale pagina) => switch (pagina) {
        PaginaPrincipale.attivita => _attivitaStatisticheAttive,
        PaginaPrincipale.pianoTurni => _pianoTurniInNavbar,
        PaginaPrincipale.tools => true,
      };

  Future<void> carica() async {
    final prefs = await SharedPreferences.getInstance();
    _attivitaStatisticheAttive = prefs.getBool(kPrefAttivitaStatisticheAttive) ?? false;
    _pianoTurniInNavbar = prefs.getBool(kPrefPianoTurniInNavbar) ?? true;
    _paginaPrincipale = _paginaDaStringa(prefs.getString(kPrefPaginaPrincipale));
    if (!_paginaValida(_paginaPrincipale)) _paginaPrincipale = PaginaPrincipale.tools;
    _caricato = true;
    notifyListeners();
  }

  /// Disattivare Attività/Statistiche mentre Attività è la pagina principale
  /// sposta la scelta su Tools (persistito subito): altrimenti l'app
  /// aprirebbe una tab che non esiste più nella NavigationBar.
  Future<void> setAttivitaStatisticheAttive(bool valore) async {
    _attivitaStatisticheAttive = valore;
    final sposta = !valore && _paginaPrincipale == PaginaPrincipale.attivita;
    if (sposta) _paginaPrincipale = PaginaPrincipale.tools;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kPrefAttivitaStatisticheAttive, valore);
    if (sposta) await prefs.setString(kPrefPaginaPrincipale, _paginaAStringa(_paginaPrincipale));
  }

  /// Attivare questa opzione sposta subito Piano turni come pagina
  /// principale (richiesta esplicita: è il motivo per cui la si attiva).
  /// Disattivarla mentre Piano turni è la pagina principale ripiega su
  /// Attività (se attiva) o Tools, per lo stesso motivo del metodo sopra.
  Future<void> setPianoTurniInNavbar(bool valore) async {
    _pianoTurniInNavbar = valore;
    if (valore) {
      _paginaPrincipale = PaginaPrincipale.pianoTurni;
    } else if (_paginaPrincipale == PaginaPrincipale.pianoTurni) {
      _paginaPrincipale = _attivitaStatisticheAttive ? PaginaPrincipale.attivita : PaginaPrincipale.tools;
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kPrefPianoTurniInNavbar, valore);
    await prefs.setString(kPrefPaginaPrincipale, _paginaAStringa(_paginaPrincipale));
  }

  Future<void> setPaginaPrincipale(PaginaPrincipale valore) async {
    _paginaPrincipale = valore;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPrefPaginaPrincipale, _paginaAStringa(valore));
  }
}

/// Stato del tutorial di navigazione a schermo intero
/// (widgets/tutorial_overlay.dart): mostrato una sola volta al primo avvio
/// (kPrefTutorialCompletato assente) e rivedibile in ogni momento dal
/// pulsante in Impostazioni → Navigazione. Provider condiviso per lo stesso
/// motivo di ToolsProvider/NavigazioneProvider: il pulsante "Rivedi
/// tutorial" vive in ImpostazioniScreen, ma solo AppNavigator ha la
/// NavigationBar reale da cui calcolare le aree da evidenziare — le due
/// schermate restano entrambe montate nell'IndexedStack, quindi serve stato
/// condiviso perché un tap nell'una faccia scattare l'overlay nell'altra.
/// `richiesta` è un contatore, non un bool: incrementarlo fa sempre scattare
/// una nuova comparsa anche a tutorial già completato (rivedibile a
/// piacere), mentre `completato` decide solo se mostrarlo in automatico al
/// primo avvio.
class TutorialProvider extends ChangeNotifier {
  bool _completato = false;
  int _richiesta = 0;
  // Cognome inserito nel primo passo del tutorial (vedi app_navigator.dart):
  // scritto nella stessa preferenza già usata dalla ricerca volontario del
  // Piano turni (kPrefPianoTurniUltimaRicerca, impostaNomeCercato sotto), il
  // campo qui serve solo a notificare PianoTurniScreen se è già montata con
  // uno stato ormai vecchio — stesso motivo di richiesta/AppNavigator: con
  // IndexedStack la schermata non si ricostruisce da sola. Sempre non-null
  // dopo il primo utilizzo (mai azzerato): PianoTurniScreen confronta il
  // valore con l'ultimo già applicato, non con la sua presenza.
  String? _nomeDalTutorial;

  bool get completato => _completato;
  int get richiesta => _richiesta;
  String? get nomeDalTutorial => _nomeDalTutorial;

  Future<void> carica() async {
    final prefs = await SharedPreferences.getInstance();
    _completato = prefs.getBool(kPrefTutorialCompletato) ?? false;
    if (!_completato) _richiesta++;
    notifyListeners();
  }

  /// Richiamato dal pulsante "Rivedi il tutorial" in Impostazioni.
  void richiediReplay() {
    _richiesta++;
    notifyListeners();
  }

  Future<void> segnaCompletato() async {
    if (_completato) return;
    _completato = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kPrefTutorialCompletato, true);
  }

  /// Chiamato dal primo passo del tutorial (chiedi cognome): persiste il
  /// nome nella stessa preferenza della ricerca volontario del Piano turni,
  /// così i segnalini "sei di turno" compaiono da subito sul calendario
  /// senza dover passare dalla sua lente di ricerca. Un cognome vuoto non fa
  /// nulla (l'utente ha saltato il campo): stessa semantica "vuoto = non
  /// impostare" già in uso per quella preferenza.
  Future<void> impostaNomeCercato(String nome) async {
    final valore = nome.trim();
    if (valore.isEmpty) return;
    _nomeDalTutorial = valore;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPrefPianoTurniUltimaRicerca, valore);
  }
}

/// Le tre modalità di tema scelte da Impostazioni → Aspetto. `sistema`
/// (default) segue il tema chiaro/scuro del sistema operativo; `chiaro`/
/// `scuro` forzano una scelta indipendente dal device.
enum ModalitaTema { sistema, chiaro, scuro }

/// Provider per la modalità di tema dell'app (Impostazioni → Aspetto).
/// Stesso motivo di ToolsProvider/NavigazioneProvider: il MaterialApp (in
/// main.dart, che deve applicare subito il tema) e ImpostazioniScreen sono
/// parti diverse dell'albero widget, serve stato condiviso perché la scelta
/// cambiata in un punto si rifletta subito sul tema in uso nell'altro.
/// Default `sistema` (richiesta esplicita): a differenza di `locale`
/// (fissato a `it` a prescindere dal device, vedi CLAUDE.md), qui l'app
/// segue il tema del sistema operativo finché l'utente non forza
/// esplicitamente chiaro o scuro. Riusa `kPrefModalitaChiara` (bool
/// nullable) invece di una nuova chiave stringa: `null` (mai toccata) =
/// sistema, `true`/`false` = scelta esplicita chiara/scura — lo stesso
/// significato di "assente" già usato da altre preferenze del progetto
/// (assente = comportamento di default), qui applicato a un tri-stato invece
/// che a un booleano.
class TemaProvider extends ChangeNotifier {
  ModalitaTema _modalita = ModalitaTema.sistema;
  bool _caricato = false;

  bool get caricato => _caricato;
  ModalitaTema get modalita => _modalita;
  ThemeMode get themeMode => switch (_modalita) {
        ModalitaTema.sistema => ThemeMode.system,
        ModalitaTema.chiaro => ThemeMode.light,
        ModalitaTema.scuro => ThemeMode.dark,
      };

  Future<void> carica() async {
    final prefs = await SharedPreferences.getInstance();
    final chiara = prefs.getBool(kPrefModalitaChiara);
    _modalita = chiara == null
        ? ModalitaTema.sistema
        : (chiara ? ModalitaTema.chiaro : ModalitaTema.scuro);
    _caricato = true;
    notifyListeners();
  }

  Future<void> setModalita(ModalitaTema valore) async {
    _modalita = valore;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    switch (valore) {
      case ModalitaTema.sistema:
        // Torna al default: nessuna preferenza esplicita salvata, coerente
        // con "assente = sistema" invece di scrivere un valore che poi
        // andrebbe interpretato come "sistema" a parte.
        await prefs.remove(kPrefModalitaChiara);
      case ModalitaTema.chiaro:
        await prefs.setBool(kPrefModalitaChiara, true);
      case ModalitaTema.scuro:
        await prefs.setBool(kPrefModalitaChiara, false);
    }
  }
}

/// Provider per l'account "utente-app" che sblocca i contenuti riservati
/// dell'app (Repository formazione, Archivio comunicati). Le credenziali
/// sono create SOLO dalla pagina admin del backend condiviso, mai da questa
/// app (vedi CLAUDE.md): qui si può solo fare login, cambiare la propria
/// password e restare loggati. Provider condiviso per lo stesso motivo di
/// ToolsProvider/NavigazioneProvider: Impostazioni e il tool aperto restano
/// entrambe montate nell'IndexedStack, un login/logout/cambio-password
/// fatto in un punto deve riflettersi subito nell'altro.
class AccountProvider extends ChangeNotifier {
  String? _username;
  String? _token;
  bool _deveCambiarePassword = false;
  bool _caricato = false;

  bool get caricato => _caricato;
  bool get loggedIn => _token != null;
  String? get username => _username;
  String? get token => _token;
  bool get deveCambiarePassword => _deveCambiarePassword;

  /// Ripristina la sessione salvata (se presente) all'avvio dell'app.
  Future<void> carica() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(kPrefAccountToken);
    _username = prefs.getString(kPrefAccountUsername);
    _deveCambiarePassword = prefs.getBool(kPrefAccountDeveCambiarePassword) ?? false;
    _caricato = true;
    notifyListeners();
  }

  Future<void> login(String username, String password) async {
    final risultato = await BackendApi(baseUrl: await _backendUrl())
        .loginUtente(username: username, password: password);
    _username = username;
    _token = risultato.token;
    _deveCambiarePassword = risultato.deveCambiarePassword;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPrefAccountToken, risultato.token);
    await prefs.setString(kPrefAccountUsername, username);
    await prefs.setBool(kPrefAccountDeveCambiarePassword, risultato.deveCambiarePassword);
  }

  /// Cambia la password (attuale verificata sempre lato server, anche per
  /// il primo cambio obbligatorio) e azzera deveCambiarePassword.
  Future<void> cambiaPassword(String passwordAttuale, String passwordNuova) async {
    final t = _token;
    if (t == null) return;
    await BackendApi(baseUrl: await _backendUrl())
        .cambiaPassword(token: t, passwordAttuale: passwordAttuale, passwordNuova: passwordNuova);
    _deveCambiarePassword = false;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kPrefAccountDeveCambiarePassword, false);
  }

  /// Chiamato sia dal pulsante "Esci" sia internamente quando una chiamata
  /// autenticata torna 401 (token scaduto/revocato): l'utente torna al
  /// form di login invece di restare bloccato su un errore generico.
  Future<void> logout() async {
    _username = null;
    _token = null;
    _deveCambiarePassword = false;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kPrefAccountToken);
    await prefs.remove(kPrefAccountUsername);
    await prefs.remove(kPrefAccountDeveCambiarePassword);
  }

  /// Stessa fonte (kPrefBackendUrl) usata dagli altri tool del backend
  /// condiviso: nessuna configurazione separata per l'account.
  Future<String> _backendUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(kPrefBackendUrl) ?? kBackendUrlDefault;
  }
}
