import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/helpers.dart';
import '../db/models.dart';
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

  // Ogni load è indipendente: se una query fallisce (es. migrazione DB non ancora
  // applicata) le altre continuano e notifyListeners() viene chiamato comunque.
  // Gli errori vengono comunque loggati: un catch completamente muto mascherava
  // eventuali problemi reali del DB (liste vuote senza alcuna traccia del perché).
  Future<void> carica() async {
    try { associazioni = await getAssociazioni(); } catch (e) { debugPrint('[anagrafiche] associazioni non caricate: $e'); }
    try { persone = await getPersone(); } catch (e) { debugPrint('[anagrafiche] persone non caricate: $e'); }
    try { ospedali = await getOspedali(); } catch (e) { debugPrint('[anagrafiche] ospedali non caricati: $e'); }
    try { tipologieTurno = await getTipologieTurno(); } catch (e) { debugPrint('[anagrafiche] tipologie non caricate: $e'); }
    _caricato = true;
    notifyListeners();
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

/// Provider per quali tool (Materiali usati, Piano turni, Magazzino Verde...)
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
  /// catalogo (kToolsDisponibili): il Magazzino Verde parte disattivato.
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
    // invece di essere ririconosciuto come "nuovo" a ogni avvio.
    await prefs.setStringList(kPrefToolsAttivi, _attivi.toList());
    await prefs.setStringList(
        kPrefToolsConosciuti, kToolsDisponibili.map((t) => t.id).toList());
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
