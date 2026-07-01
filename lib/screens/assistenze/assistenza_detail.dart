import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../db/helpers.dart';
import '../../db/models.dart';
import '../../providers/app_provider.dart';
import '../../utils/format.dart';
import '../../utils/theme.dart';
import 'assistenza_form.dart';

/// Dettaglio di un'assistenza: info e equipaggio.
class AssistenzaDetail extends StatefulWidget {
  final String assistenzaId;
  const AssistenzaDetail({super.key, required this.assistenzaId});

  @override
  State<AssistenzaDetail> createState() => _AssistenzaDetailState();
}

class _AssistenzaDetailState extends State<AssistenzaDetail> {
  Assistenza? _a;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _carica();
  }

  Future<void> _carica() async {
    final a = await getAssistenzaById(widget.assistenzaId);
    if (mounted) setState(() { _a = a; _loading = false; });
  }

  Future<void> _elimina() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina assistenza'),
        content: const Text('Eliminare questa assistenza?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Elimina', style: TextStyle(color: kPrimary))),
        ],
      ),
    );
    if (ok == true && mounted) {
      await deleteAssistenza(widget.assistenzaId);
      if (mounted) Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_a == null) return const Scaffold(body: Center(child: Text('Assistenza non trovata')));
    final anag = context.watch<AnagraficheProvider>();
    final a = _a!;

    return Scaffold(
      appBar: AppBar(
        title: Text('Assistenza ${formatDate(a.data)}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => AssistenzaForm(assistenzaId: a.id)));
              _carica();
            },
          ),
          IconButton(icon: const Icon(Icons.delete, color: kPrimary), onPressed: _elimina),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Row('Associazione', a.associazioneNome ?? '—'),
                  _Row('Data', formatDate(a.data)),
                  _Row('Ore', formatOre(a.ore)),
                  if (a.descrizione != null) _Row('Descrizione', a.descrizione!),
                  if (a.note != null) _Row('Note', a.note!),
                ],
              ),
            ),
          ),
          if (_hasEquipaggio(a)) ...[
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Equipaggio', style: TextStyle(color: kPrimary, fontWeight: FontWeight.w600)),
                    const Divider(height: 16),
                    const Text('1ª parte', style: TextStyle(color: Colors.white54, fontSize: 12)),
                    const SizedBox(height: 6),
                    ..._eqRows(anag, a.eq1AutostaId, a.eq1CsId, a.eq1TerzoId, a.eq1QuartoId, a.eq1CentralinistaId),
                    if (a.eq2AutostaId != null || a.eq2CsId != null || a.eq2TerzoId != null ||
                        a.eq2QuartoId != null || a.eq2CentralinistaId != null) ...[
                      const SizedBox(height: 12),
                      const Text('2ª parte', style: TextStyle(color: Colors.white54, fontSize: 12)),
                      const SizedBox(height: 6),
                      ..._eqRows(anag, a.eq2AutostaId, a.eq2CsId, a.eq2TerzoId, a.eq2QuartoId, a.eq2CentralinistaId),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  bool _hasEquipaggio(Assistenza a) =>
      a.eq1AutostaId != null || a.eq1CsId != null || a.eq1TerzoId != null ||
      a.eq1QuartoId != null || a.eq1CentralinistaId != null ||
      a.eq2AutostaId != null || a.eq2CsId != null || a.eq2TerzoId != null ||
      a.eq2QuartoId != null || a.eq2CentralinistaId != null;

  /// Mostra solo i ruoli valorizzati, omettendo quelli null per non sprecare spazio.
  List<Widget> _eqRows(AnagraficheProvider anag, String? aut, String? cs, String? terzo, String? quarto, String? central) {
    final roles = {'Autista': aut, 'CS': cs, 'Terzo': terzo, 'Quarto': quarto, 'Centralinista': central};
    return roles.entries
        .where((e) => e.value != null)
        .map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                SizedBox(width: 100, child: Text(e.key, style: const TextStyle(color: Colors.white38, fontSize: 12))),
                Text(anag.byIdPersona(e.value)?.nomeCompleto ?? '', style: const TextStyle(fontSize: 13)),
              ]),
            ))
        .toList();
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String val;
  const _Row(this.label, this.val);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 110, child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13))),
          Expanded(child: Text(val, style: const TextStyle(fontSize: 13))),
        ]),
      );
}
