import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../db/helpers.dart';
import '../../db/models.dart';
import '../../providers/app_provider.dart';
import '../../utils/format.dart';
import '../../utils/theme.dart';
import 'turno_form.dart';
import 'turno_detail.dart';

/// Lista turni ordinata per data decrescente, con filtro per associazione e
/// long-press per eliminare (con conferma).
class TurniList extends StatefulWidget {
  const TurniList({super.key});

  @override
  State<TurniList> createState() => _TurniListState();
}

class _TurniListState extends State<TurniList> {
  String? _filtroAssocId;

  @override
  void initState() {
    super.initState();
    // Carica i turni al primo avvio usando il provider.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TurniProvider>().carica();
    });
  }

  Future<void> _elimina(Turno turno) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina turno'),
        content: Text('Eliminare il turno del ${formatDate(turno.data)}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina', style: TextStyle(color: kPrimary)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await deleteTurno(turno.id);
      if (mounted) context.read<TurniProvider>().ricarica();
    }
  }

  @override
  Widget build(BuildContext context) {
    final anag = context.watch<AnagraficheProvider>();
    final turniProvider = context.watch<TurniProvider>();
    final turni = turniProvider.turni;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Turni'),
        actions: [
          // Filtro per associazione
          if (anag.associazioni.isNotEmpty)
            PopupMenuButton<String?>(
              icon: Icon(
                Icons.filter_list,
                color: _filtroAssocId != null ? kPrimary : Colors.white70,
              ),
              tooltip: 'Filtra per associazione',
              onSelected: (val) {
                setState(() => _filtroAssocId = val);
                context.read<TurniProvider>().carica(associazioneId: val);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: null, child: Text('Tutti')),
                ...anag.associazioni.map(
                  (a) => PopupMenuItem(value: a.id, child: Text(a.nome)),
                ),
              ],
            ),
        ],
      ),
      body: turni.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_today_outlined, size: 64, color: Colors.white24),
                  SizedBox(height: 16),
                  Text('Nessun turno', style: TextStyle(color: Colors.white54)),
                  SizedBox(height: 8),
                  Text('Tocca + per aggiungerne uno', style: TextStyle(color: Colors.white38, fontSize: 13)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
              itemCount: turni.length,
              itemBuilder: (ctx, i) => _TurnoCard(
                turno: turni[i],
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => TurnoDetail(turnoId: turni[i].id)),
                  );
                  if (mounted) context.read<TurniProvider>().ricarica();
                },
                onLongPress: () => _elimina(turni[i]),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const TurnoForm()));
          if (mounted) context.read<TurniProvider>().ricarica();
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// Card di un turno nella lista: mostra numero progressivo, data, associazione,
/// tipologia, ore e contatore servizi. Long-press per eliminare.
class _TurnoCard extends StatelessWidget {
  final Turno turno;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _TurnoCard({required this.turno, required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Numero progressivo
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: kPrimary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: kPrimary.withOpacity(0.4)),
                ),
                alignment: Alignment.center,
                child: Text(
                  '#${turno.numeroProgressivo ?? '—'}',
                  style: const TextStyle(color: kPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatDate(turno.data),
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (turno.associazioneNome != null)
                          Text(turno.associazioneNome!, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                        if (turno.associazioneNome != null && turno.tipologiaNome != null)
                          const Text(' · ', style: TextStyle(color: Colors.white38)),
                        if (turno.tipologiaNome != null)
                          Text(turno.tipologiaNome!, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatOre(turno.ore), style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  if (turno.numServizi > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${turno.numServizi} serv.',
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
