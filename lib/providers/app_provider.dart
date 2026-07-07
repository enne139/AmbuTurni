import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import '../db/helpers.dart';
import '../db/models.dart';

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
