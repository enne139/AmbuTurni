import 'package:flutter/material.dart';
import '../db/helpers.dart';
import '../db/models.dart';

/// Provider per le anagrafiche (associazioni, persone, ospedali, tipologie).
/// Caricato all'avvio e invalidato dopo ogni modifica.
class AnagraficheProvider extends ChangeNotifier {
  List<Associazione> associazioni = [];
  List<Persona> persone = [];
  List<Ospedale> ospedali = [];
  List<TipologiaTurno> tipologieTurno = [];
  bool _caricato = false;

  Future<void> carica() async {
    associazioni = await getAssociazioni();
    persone = await getPersone();
    ospedali = await getOspedali();
    tipologieTurno = await getTipologieTurno();
    _caricato = true;
    notifyListeners();
  }

  bool get caricato => _caricato;

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

/// Provider per la lista turni.
class TurniProvider extends ChangeNotifier {
  List<Turno> turni = [];
  String? _filtroAssociazioneId;

  String? get filtroAssociazioneId => _filtroAssociazioneId;

  Future<void> carica({String? associazioneId}) async {
    _filtroAssociazioneId = associazioneId;
    turni = await getTurni(associazioneId: associazioneId);
    notifyListeners();
  }

  Future<void> ricarica() async {
    turni = await getTurni(associazioneId: _filtroAssociazioneId);
    notifyListeners();
  }
}

/// Provider per la lista assistenze.
class AssistezeProvider extends ChangeNotifier {
  List<Assistenza> assistenze = [];
  String? _filtroAssociazioneId;

  String? get filtroAssociazioneId => _filtroAssociazioneId;

  Future<void> carica({String? associazioneId}) async {
    _filtroAssociazioneId = associazioneId;
    assistenze = await getAssistenze(associazioneId: associazioneId);
    notifyListeners();
  }

  Future<void> ricarica() async {
    assistenze = await getAssistenze(associazioneId: _filtroAssociazioneId);
    notifyListeners();
  }
}
