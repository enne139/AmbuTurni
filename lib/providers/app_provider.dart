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
  List<TipologiaAssistenza> tipologieAssistenza = [];
  bool _caricato = false;

  Future<void> carica() async {
    associazioni = await getAssociazioni();
    persone = await getPersone();
    ospedali = await getOspedali();
    tipologieTurno = await getTipologieTurno();
    tipologieAssistenza = await getTipologieAssistenza();
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

/// Provider per la lista turni. Mantiene il filtro associazione attivo
/// tra una navigazione e l'altra (ricarica() lo riusa senza doverlo ripassare).
class TurniProvider extends ChangeNotifier {
  List<Turno> turni = [];
  String? _filtroAssociazioneId;

  String? get filtroAssociazioneId => _filtroAssociazioneId;

  Future<void> carica({String? associazioneId}) async {
    _filtroAssociazioneId = associazioneId;
    turni = await getTurni(associazioneId: associazioneId);
    notifyListeners();
  }

  /// Ricarica con lo stesso filtro già impostato (usato dopo create/edit/delete).
  Future<void> ricarica() async {
    turni = await getTurni(associazioneId: _filtroAssociazioneId);
    notifyListeners();
  }
}

/// Provider per la lista assistenze. Stesso pattern di TurniProvider.
class AssistezeProvider extends ChangeNotifier {
  List<Assistenza> assistenze = [];
  String? _filtroAssociazioneId;

  String? get filtroAssociazioneId => _filtroAssociazioneId;

  Future<void> carica({String? associazioneId}) async {
    _filtroAssociazioneId = associazioneId;
    assistenze = await getAssistenze(associazioneId: associazioneId);
    notifyListeners();
  }

  /// Ricarica con lo stesso filtro già impostato.
  Future<void> ricarica() async {
    assistenze = await getAssistenze(associazioneId: _filtroAssociazioneId);
    notifyListeners();
  }
}
