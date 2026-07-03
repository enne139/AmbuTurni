import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../db/helpers.dart';
import '../../db/models.dart';
import '../../providers/app_provider.dart';
import '../../utils/format.dart';
import '../../utils/theme.dart';
import '../../widgets/nota_markdown.dart';
import '../shared/note_editor_screen.dart';
import 'assistenza_form.dart';

/// Dettaglio di un'assistenza: info, equipaggio e note.
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

  /// Modifica rapida delle sole note in un editor a schermo intero (le note
  /// accettano markdown). Il salvataggio passa da toMap/fromMap invece di
  /// copyWith perché copyWith non può riportare il campo a null (note vuote).
  Future<void> _modificaNote() async {
    final a = _a!;
    final nuovoTesto = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => NoteEditorScreen(notaIniziale: a.note)),
    );
    if (nuovoTesto == null) return;
    final map = a.toMap();
    map['note'] = nuovoTesto.isEmpty ? null : nuovoTesto;
    await saveAssistenza(Assistenza.fromMap(map));
    _carica();
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
                ],
              ),
            ),
          ),
          if (_hasEquipaggio(a)) ...[
            const SizedBox(height: 16),
            _EquipaggioCard(a: a, anag: anag),
          ],
          const SizedBox(height: 16),
          _NoteCard(note: a.note, onModifica: _modificaNote),
        ],
      ),
    );
  }

  bool _hasEquipaggio(Assistenza a) =>
      a.eq1AutostaId != null || a.eq1CsId != null || a.eq1TerzoId != null ||
      a.eq1QuartoId != null || a.eq1CentralinistaId != null ||
      a.eq2AutostaId != null || a.eq2CsId != null || a.eq2TerzoId != null ||
      a.eq2QuartoId != null || a.eq2CentralinistaId != null;
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

/// Card equipaggio nel dettaglio assistenza. Stesso pattern di
/// _EquipaggioCard in turno_detail.dart (non condiviso perché Turno e
/// Assistenza sono due classi diverse, pur con gli stessi 10 campi eq1/eq2):
/// quando c'è un 2° equipaggio le due parti sono affiancate riga per ruolo,
/// con un solo equipaggio resta l'elenco singolo.
class _EquipaggioCard extends StatelessWidget {
  final Assistenza a;
  final AnagraficheProvider anag;
  const _EquipaggioCard({required this.a, required this.anag});

  String _n(String? id) => anag.byIdPersona(id)?.nomeCompleto ?? '';

  bool get _ha2aParte =>
      a.eq2AutostaId != null || a.eq2CsId != null || a.eq2TerzoId != null ||
      a.eq2QuartoId != null || a.eq2CentralinistaId != null;

  List<({String label, String? v1, String? v2})> get _ruoliCompilati {
    final ruoli = [
      (label: 'Autista', v1: a.eq1AutostaId, v2: a.eq2AutostaId),
      (label: 'CS', v1: a.eq1CsId, v2: a.eq2CsId),
      (label: 'Terzo', v1: a.eq1TerzoId, v2: a.eq2TerzoId),
      (label: 'Quarto', v1: a.eq1QuartoId, v2: a.eq2QuartoId),
      (label: 'Centralino', v1: a.eq1CentralinistaId, v2: a.eq2CentralinistaId),
    ];
    return ruoli.where((r) => r.v1 != null || r.v2 != null).toList();
  }

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
            if (_ha2aParte) ..._righeAffiancate() else ..._righeSingole(),
          ],
        ),
      ),
    );
  }

  List<Widget> _righeAffiancate() {
    return [
      const Padding(
        padding: EdgeInsets.only(bottom: 6),
        child: Row(children: [
          SizedBox(width: 72),
          Expanded(child: Text('1ª parte', style: TextStyle(color: Colors.white54, fontSize: 12))),
          SizedBox(width: 12),
          Expanded(child: Text('2ª parte', style: TextStyle(color: Colors.white54, fontSize: 12))),
        ]),
      ),
      ..._ruoliCompilati.map((r) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 72, child: Text(r.label, style: const TextStyle(color: Colors.white38, fontSize: 12))),
                Expanded(child: _valorePersona(r.v1)),
                const SizedBox(width: 12),
                Expanded(child: _valorePersona(r.v2)),
              ],
            ),
          )),
    ];
  }

  List<Widget> _righeSingole() => _ruoliCompilati
      .map((r) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(children: [
              SizedBox(width: 72, child: Text(r.label, style: const TextStyle(color: Colors.white38, fontSize: 12))),
              Text(_n(r.v1), style: const TextStyle(fontSize: 13)),
            ]),
          ))
      .toList();

  Widget _valorePersona(String? id) => id == null
      ? const Text('—', style: TextStyle(fontSize: 13, color: Colors.white24))
      : Text(_n(id), style: const TextStyle(fontSize: 13));
}

/// Card dedicata alle note dell'assistenza, sempre visibile. Stesso pattern
/// di _NoteCard in turno_detail.dart: note in markdown (renderizzato con
/// NotaMarkdown), matita che apre l'editor a schermo intero.
class _NoteCard extends StatelessWidget {
  final String? note;
  final VoidCallback onModifica;
  const _NoteCard({required this.note, required this.onModifica});

  @override
  Widget build(BuildContext context) {
    final vuote = note == null || note!.isEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Note', style: TextStyle(color: kPrimary, fontWeight: FontWeight.w600)),
                IconButton(
                  icon: const Icon(Icons.edit, size: 18, color: Colors.white60),
                  onPressed: onModifica,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Modifica note',
                ),
              ],
            ),
            const Divider(height: 8),
            const SizedBox(height: 8),
            vuote
                ? const Text('Nessuna nota', style: TextStyle(fontSize: 13, color: Colors.white38, fontStyle: FontStyle.italic))
                : NotaMarkdown(data: note!),
          ],
        ),
      ),
    );
  }
}
