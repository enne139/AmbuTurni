import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../db/helpers.dart';
import '../../providers/app_provider.dart';
import '../../utils/format.dart';
import '../../utils/theme.dart' show kPrimary, colorFromHex;

/// Schermata statistiche con filtro per associazione (chip).
class StatisticheScreen extends StatefulWidget {
  const StatisticheScreen({super.key});

  @override
  State<StatisticheScreen> createState() => _StatisticheScreenState();
}

class _StatisticheScreenState extends State<StatisticheScreen> {
  String? _filtroAssocId;
  StatisticheData? _dati;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _carica();
  }

  Future<void> _carica({String? assocId}) async {
    setState(() { _loading = true; _filtroAssocId = assocId; });
    final d = await getStatistiche(associazioneId: assocId);
    if (mounted) setState(() { _dati = d; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final anag = context.watch<AnagraficheProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Statistiche')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Filtro associazione
                if (anag.associazioni.isNotEmpty) ...[
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      _FiltroChip(label: 'Tutti', sel: _filtroAssocId == null, onTap: () => _carica()),
                      ...anag.associazioni.map((a) => _FiltroChip(
                            label: a.nome,
                            sel: _filtroAssocId == a.id,
                            onTap: () => _carica(assocId: a.id),
                            colore: colorFromHex(a.colore),
                          )),
                    ]),
                  ),
                  const SizedBox(height: 20),
                ],
                // Cards
                Row(children: [
                  Expanded(child: _StatCard(label: 'Turni', valore: '${_dati!.totTurni}', icon: Icons.calendar_today)),
                  const SizedBox(width: 12),
                  Expanded(child: _StatCard(label: 'Servizi', valore: '${_dati!.totServizi}', icon: Icons.medical_services_outlined)),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _StatCard(label: 'Ore turni', valore: formatOre(_dati!.oreTurni), icon: Icons.schedule)),
                  const SizedBox(width: 12),
                  Expanded(child: _StatCard(label: 'Assistenze', valore: '${_dati!.totAssistenze}', icon: Icons.local_hospital_outlined)),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _StatCard(label: 'Ore assist.', valore: formatOre(_dati!.oreAssistenze), icon: Icons.schedule_outlined)),
                  const SizedBox(width: 12),
                  Expanded(child: _StatCard(label: 'Ore totali', valore: formatOre(_dati!.oreTotali), icon: Icons.timer, highlight: true)),
                ]),
              ],
            ),
    );
  }
}

class _FiltroChip extends StatelessWidget {
  final String label;
  final bool sel;
  final VoidCallback onTap;
  final Color? colore;
  const _FiltroChip({required this.label, required this.sel, required this.onTap, this.colore});

  @override
  Widget build(BuildContext context) {
    final accent = colore ?? kPrimary;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: sel,
        onSelected: (_) => onTap(),
        selectedColor: accent.withValues(alpha: 0.25),
        checkmarkColor: accent,
        labelStyle: TextStyle(color: sel ? accent : Colors.white70),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String valore;
  final IconData icon;
  final bool highlight;
  const _StatCard({required this.label, required this.valore, required this.icon, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: highlight ? kPrimary : Colors.white38, size: 22),
            const SizedBox(height: 8),
            Text(valore,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: highlight ? kPrimary : Colors.white,
                )),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
