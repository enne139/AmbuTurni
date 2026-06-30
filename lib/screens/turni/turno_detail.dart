import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../db/helpers.dart';
import '../../db/models.dart';
import '../../providers/app_provider.dart';
import '../../utils/format.dart';
import '../../utils/theme.dart';
import '../../widgets/codice_chip.dart';
import 'turno_form.dart';
import 'servizio_form.dart';

/// Dettaglio di un turno: info, equipaggio e lista servizi con riordino.
class TurnoDetail extends StatefulWidget {
  final String turnoId;
  const TurnoDetail({super.key, required this.turnoId});

  @override
  State<TurnoDetail> createState() => _TurnoDetailState();
}

class _TurnoDetailState extends State<TurnoDetail> {
  Turno? _turno;
  List<Servizio> _servizi = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _carica();
  }

  Future<void> _carica() async {
    final t = await getTurnoById(widget.turnoId);
    final s = await getServizi(widget.turnoId);
    if (mounted) setState(() { _turno = t; _servizi = s; _loading = false; });
  }

  Future<void> _eliminaTurno() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina turno'),
        content: const Text('Eliminare questo turno e tutti i suoi servizi?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Elimina', style: TextStyle(color: kPrimary))),
        ],
      ),
    );
    if (ok == true && mounted) {
      await deleteTurno(widget.turnoId);
      if (mounted) Navigator.pop(context, true);
    }
  }

  Future<void> _eliminaServizio(Servizio s) async {
    await deleteServizio(s.id, widget.turnoId);
    _carica();
  }

  Future<void> _sposta(int from, int to) async {
    await spostaServizio(widget.turnoId, from, to);
    _carica();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_turno == null) return const Scaffold(body: Center(child: Text('Turno non trovato')));
    final anag = context.watch<AnagraficheProvider>();
    final t = _turno!;

    return Scaffold(
      appBar: AppBar(
        title: Text('Turno ${formatDate(t.data)}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => TurnoForm(turnoId: t.id)));
              _carica();
            },
          ),
          IconButton(icon: const Icon(Icons.delete, color: kPrimary), onPressed: _eliminaTurno),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Riepilogo
          _InfoCard(t: t, anag: anag),
          const SizedBox(height: 16),

          // Equipaggio
          if (_hasEquipaggio(t)) ...[
            _EquipaggioCard(t: t, anag: anag),
            const SizedBox(height: 16),
          ],

          // Servizi
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Servizi (${_servizi.length})', style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
              FilledButton.icon(
                onPressed: () async {
                  await Navigator.push(context, MaterialPageRoute(
                    builder: (_) => ServizioForm(turnoId: t.id, ordine: _servizi.length),
                  ));
                  _carica();
                },
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Aggiungi'),
                style: FilledButton.styleFrom(
                  backgroundColor: kPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._servizi.asMap().entries.map((entry) {
            final i = entry.key;
            final s = entry.value;
            return _ServizioCard(
              servizio: s,
              index: i,
              total: _servizi.length,
              anag: anag,
              onEdit: () async {
                await Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ServizioForm(turnoId: t.id, servizioId: s.id, ordine: i),
                ));
                _carica();
              },
              onDelete: () => _eliminaServizio(s),
              onSu: i > 0 ? () => _sposta(i, i - 1) : null,
              onGiu: i < _servizi.length - 1 ? () => _sposta(i, i + 1) : null,
            );
          }),
        ],
      ),
    );
  }

  bool _hasEquipaggio(Turno t) =>
      t.eq1AutostaId != null || t.eq1CsId != null || t.eq1TerzoId != null ||
      t.eq1QuartoId != null || t.eq1CentralinistaId != null ||
      t.eq2AutostaId != null || t.eq2CsId != null || t.eq2TerzoId != null ||
      t.eq2QuartoId != null || t.eq2CentralinistaId != null;
}

class _InfoCard extends StatelessWidget {
  final Turno t;
  final AnagraficheProvider anag;
  const _InfoCard({required this.t, required this.anag});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Row('Associazione', t.associazioneNome ?? '—'),
            _Row('Data', formatDate(t.data)),
            _Row('Ore', formatOre(t.ore)),
            if (t.tipologiaNome != null) _Row('Tipologia', t.tipologiaNome!),
            if (t.tipologieExtra.isNotEmpty)
              _Row('Tipologie extra', t.tipologieExtra
                  .map((id) => anag.byIdTipologia(id)?.nome ?? id)
                  .join(', ')),
            if (t.descrizione != null) _Row('Descrizione', t.descrizione!),
            if (t.note != null) _Row('Note', t.note!),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String val;
  const _Row(this.label, this.val);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 110, child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13))),
            Expanded(child: Text(val, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );
}

class _EquipaggioCard extends StatelessWidget {
  final Turno t;
  final AnagraficheProvider anag;
  const _EquipaggioCard({required this.t, required this.anag});

  String _n(String? id) => anag.byIdPersona(id)?.nomeCompleto ?? '';

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Equipaggio', style: TextStyle(color: kPrimary, fontWeight: FontWeight.w600)),
            const Divider(height: 16),
            const Text('1ª parte', style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 6),
            ..._eq(t.eq1AutostaId, t.eq1CsId, t.eq1TerzoId, t.eq1QuartoId, t.eq1CentralinistaId),
            if (t.eq2AutostaId != null || t.eq2CsId != null || t.eq2TerzoId != null ||
                t.eq2QuartoId != null || t.eq2CentralinistaId != null) ...[
              const SizedBox(height: 12),
              const Text('2ª parte', style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 6),
              ..._eq(t.eq2AutostaId, t.eq2CsId, t.eq2TerzoId, t.eq2QuartoId, t.eq2CentralinistaId),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _eq(String? aut, String? cs, String? terzo, String? quarto, String? central) {
    final roles = {'Autista': aut, 'CS': cs, 'Terzo': terzo, 'Quarto': quarto, 'Centralinista': central};
    return roles.entries
        .where((e) => e.value != null)
        .map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                SizedBox(width: 100, child: Text(e.key, style: const TextStyle(color: Colors.white38, fontSize: 12))),
                Text(_n(e.value), style: const TextStyle(fontSize: 13)),
              ]),
            ))
        .toList();
  }
}

class _ServizioCard extends StatelessWidget {
  final Servizio servizio;
  final int index;
  final int total;
  final AnagraficheProvider anag;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onSu;
  final VoidCallback? onGiu;

  const _ServizioCard({
    required this.servizio,
    required this.index,
    required this.total,
    required this.anag,
    required this.onEdit,
    required this.onDelete,
    this.onSu,
    this.onGiu,
  });

  @override
  Widget build(BuildContext context) {
    final s = servizio;
    final osp = anag.byIdOspedale(s.ospedaleId);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Numero
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: Text('${index + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    CodiceChip(codice: s.codiceChiamata, prefisso: 'C'),
                    const SizedBox(width: 6),
                    CodiceChip(codice: s.codiceUscita, prefisso: 'U'),
                  ]),
                  if (osp != null) ...[
                    const SizedBox(height: 4),
                    Text(osp.label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ],
                  if (s.descrizione != null && s.descrizione!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(s.descrizione!, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ],
              ),
            ),
            // Azioni: riordina, modifica, elimina
            Column(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_upward, size: 18, color: onSu != null ? Colors.white60 : Colors.white24),
                  onPressed: onSu,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
                IconButton(
                  icon: Icon(Icons.arrow_downward, size: 18, color: onGiu != null ? Colors.white60 : Colors.white24),
                  onPressed: onGiu,
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 18, color: Colors.white54),
              onSelected: (v) {
                if (v == 'edit') onEdit();
                if (v == 'del') onDelete();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Modifica')),
                const PopupMenuItem(value: 'del', child: Text('Elimina', style: TextStyle(color: kPrimary))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
