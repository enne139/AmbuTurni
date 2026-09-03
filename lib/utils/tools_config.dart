import 'package:flutter/material.dart';

// ID persistenti dei tool disattivabili da Impostazioni → Tools attivi:
// vanno nel valore salvato in SharedPreferences (kPrefToolsAttivi), quindi
// cambiarli romperebbe la preferenza già scelta sui device esistenti.
const kToolMaterialiUsati = 'materiali_usati';
const kToolPianoTurni = 'piano_turni';
const kToolListaOspedali = 'lista_ospedali';
const kToolRepositoryFormazione = 'repository_formazione';
const kToolArchivioComunicati = 'archivio_comunicati';

/// Metadati di un tool per la card in Tools e lo switch in Impostazioni:
/// un'unica fonte così le due schermate restano coerenti (stesso titolo,
/// stessa icona) senza duplicarli.
class ToolInfo {
  final String id;
  final String titolo;
  final String sottotitolo;
  final IconData icon;
  // Un tool collegato a un servizio esterno da configurare (nessun default
  // universale) può partire disattivato per non ingombrare la lista Tools
  // finché l'utente non lo attiva esplicitamente.
  final bool attivoDiDefault;

  const ToolInfo({
    required this.id,
    required this.titolo,
    required this.sottotitolo,
    required this.icon,
    this.attivoDiDefault = true,
  });
}

const kToolsDisponibili = [
  ToolInfo(
    id: kToolMaterialiUsati,
    titolo: 'Materiali usati',
    sottotitolo: 'Segna i materiali usati da ripristinare',
    icon: Icons.inventory_2_outlined,
  ),
  ToolInfo(
    id: kToolPianoTurni,
    titolo: 'Piano turni',
    sottotitolo: 'Equipaggi e buchi dal foglio Google dei turni',
    icon: Icons.event_busy_outlined,
  ),
  ToolInfo(
    id: kToolListaOspedali,
    titolo: 'Lista ospedali',
    sottotitolo: 'Cerca, indirizzo, naviga e mappa degli ospedali',
    icon: Icons.local_hospital_outlined,
  ),
  ToolInfo(
    id: kToolRepositoryFormazione,
    titolo: 'Repository formazione',
    sottotitolo: 'Apri i materiali di formazione dell\'associazione',
    icon: Icons.school_outlined,
  ),
  ToolInfo(
    id: kToolArchivioComunicati,
    titolo: 'Archivio comunicati',
    sottotitolo: 'Comunicati e avvisi dell\'associazione (richiede login)',
    icon: Icons.campaign_outlined,
  ),
];
