import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../../utils/format.dart';
import '../../utils/theme.dart' show kPrimary, colorFromHex;

/// Schermata statistiche con filtro per associazione (chip).
/// I dati vivono in StatisticheProvider (non più in uno stato locale): con
/// IndexedStack che tiene tutte le tab montate, uno stato locale caricato solo
/// in initState non si aggiornava mai dopo un import backup da un'altra tab.
class StatisticheScreen extends StatefulWidget {
  const StatisticheScreen({super.key});

  @override
  State<StatisticheScreen> createState() => _StatisticheScreenState();
}

class _StatisticheScreenState extends State<StatisticheScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StatisticheProvider>().carica();
    });
  }

  @override
  Widget build(BuildContext context) {
    final anag = context.watch<AnagraficheProvider>();
    final stats = context.watch<StatisticheProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Statistiche')),
      body: !stats.caricato
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Filtro associazione
                if (anag.associazioni.isNotEmpty) ...[
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      _FiltroChip(
                        label: 'Tutti',
                        sel: stats.filtroAssociazioneId == null,
                        onTap: () => context.read<StatisticheProvider>().carica(),
                      ),
                      ...anag.associazioni.map((a) => _FiltroChip(
                            label: a.nome,
                            sel: stats.filtroAssociazioneId == a.id,
                            onTap: () => context.read<StatisticheProvider>().carica(associazioneId: a.id),
                            colore: colorFromHex(a.colore),
                          )),
                    ]),
                  ),
                  const SizedBox(height: 20),
                ],
                // Cards
                Row(children: [
                  Expanded(child: _StatCard(label: 'Turni', valore: '${stats.dati!.totTurni}', icon: Icons.calendar_today)),
                  const SizedBox(width: 12),
                  Expanded(child: _StatCard(label: 'Servizi', valore: '${stats.dati!.totServizi}', icon: Icons.medical_services_outlined)),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _StatCard(label: 'Ore turni', valore: formatOre(stats.dati!.oreTurni), icon: Icons.schedule)),
                  const SizedBox(width: 12),
                  Expanded(child: _StatCard(label: 'Assistenze', valore: '${stats.dati!.totAssistenze}', icon: Icons.local_hospital_outlined)),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: _StatCard(label: 'Ore assist.', valore: formatOre(stats.dati!.oreAssistenze), icon: Icons.schedule_outlined)),
                  const SizedBox(width: 12),
                  Expanded(child: _StatCard(label: 'Ore totali', valore: formatOre(stats.dati!.oreTotali), icon: Icons.timer, highlight: true)),
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
