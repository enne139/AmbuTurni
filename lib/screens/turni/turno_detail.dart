import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../db/helpers.dart';
import '../../db/models.dart';
import '../../providers/app_provider.dart';
import '../../utils/format.dart';
import '../../utils/theme.dart';
import '../../widgets/codice_chip.dart';
import '../../widgets/nota_markdown.dart';
import '../shared/note_editor_screen.dart';
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
  String? _errore;
  // Disabilita le frecce di riordino durante l'operazione: senza questa
  // guardia, tap multipli rapidi sulla stessa freccia prima che _carica()
  // sia tornata fanno partire più spostaServizio in sequenza con indici
  // calcolati sullo stato "vecchio" della lista, invertendo l'ordine atteso.
  bool _riordinando = false;

  @override
  void initState() {
    super.initState();
    _carica();
  }

  Future<void> _carica() async {
    try {
      final t = await getTurnoById(widget.turnoId);
      final s = await getServizi(widget.turnoId);
      if (mounted) setState(() { _turno = t; _servizi = s; _loading = false; _errore = null; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _errore = e.toString(); });
    }
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
    if (ok != true || !mounted) return;
    try {
      await deleteTurno(widget.turnoId);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore durante l\'eliminazione: $e')),
        );
      }
    }
  }

  /// Chiede conferma prima di eliminare: stessa protezione già in uso per
  /// turno/assistenza, mancava qui — un tap impreciso sul menu a tre puntini
  /// cancellava il servizio senza possibilità di annullare.
  Future<void> _eliminaServizio(Servizio s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina servizio'),
        content: const Text('Eliminare questo servizio?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Elimina', style: TextStyle(color: kPrimary))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await deleteServizio(s.id, widget.turnoId);
      _carica();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore durante l\'eliminazione: $e')),
        );
      }
    }
  }

  /// Sposta un servizio su o giù di una posizione e ricarica la lista.
  Future<void> _sposta(int from, int to) async {
    if (_riordinando) return;
    setState(() => _riordinando = true);
    try {
      await spostaServizio(widget.turnoId, from, to);
      await _carica();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore durante il riordino: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _riordinando = false);
    }
  }

  /// Modifica rapida delle sole note in un editor a schermo intero (le note
  /// accettano markdown: il dialog piccolo di prima era troppo stretto per
  /// scrivere/scorrere testo lungo), senza passare dal form completo del
  /// turno. Il salvataggio passa da toMap/fromMap invece di copyWith perché
  /// copyWith non può riportare il campo a null (note vuote).
  Future<void> _modificaNote() async {
    final t = _turno!;
    final nuovoTesto = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => NoteEditorScreen(notaIniziale: t.note)),
    );
    if (nuovoTesto == null) return;
    final map = t.toMap();
    map['note'] = nuovoTesto.isEmpty ? null : nuovoTesto;
    try {
      await saveTurno(Turno.fromMap(map));
      _carica();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore durante il salvataggio: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_errore != null) return Scaffold(body: Center(child: Text('Errore: $_errore')));
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

          // Note: sezione dedicata prima dei servizi, sempre visibile così la
          // matita di modifica rapida è raggiungibile anche a note vuote
          _NoteCard(note: t.note, onModifica: _modificaNote),
          const SizedBox(height: 16),

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
              onSu: (!_riordinando && i > 0) ? () => _sposta(i, i - 1) : null,
              onGiu: (!_riordinando && i < _servizi.length - 1) ? () => _sposta(i, i + 1) : null,
            );
          }),
        ],
      ),
    );
  }

  /// Nasconde la sezione equipaggio se nessuna persona è stata assegnata,
  /// per non mostrare una card vuota a chi non usa il campo.
  bool _hasEquipaggio(Turno t) =>
      t.eq1AutistaId != null || t.eq1CsId != null || t.eq1TerzoId != null ||
      t.eq1QuartoId != null || t.eq1CentralinistaId != null ||
      t.eq2AutistaId != null || t.eq2CsId != null || t.eq2TerzoId != null ||
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
            if (t.tipologie.isNotEmpty)
              _Row('Tipologia', t.tipologie
                  .map((id) => anag.byIdTipologia(id)?.nome ?? id)
                  .join(', ')),
            if (t.descrizione != null) _Row('Descrizione', t.descrizione!),
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

/// Card dedicata alle note del turno: separata dal riepilogo perché le note
/// possono essere lunghe e schiacciate nella riga label/valore erano poco
/// leggibili. Le note accettano markdown, renderizzato con NotaMarkdown.
/// La matita apre l'editor a schermo intero per la modifica rapida.
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

/// Card equipaggio nel dettaglio turno. Quando c'è un 2° equipaggio (cambio a
/// metà turno), le due parti sono affiancate riga per ruolo invece che in due
/// blocchi impilati, per confrontarle a colpo d'occhio senza scorrere; con un
/// solo equipaggio resta una lista singola (non avrebbe senso una colonna
/// "2ª parte" vuota di trattini).
class _EquipaggioCard extends StatelessWidget {
  final Turno t;
  final AnagraficheProvider anag;
  const _EquipaggioCard({required this.t, required this.anag});

  String _n(String? id) => anag.byIdPersona(id)?.nomeCompleto ?? '';

  bool get _ha2aParte =>
      t.eq2AutistaId != null || t.eq2CsId != null || t.eq2TerzoId != null ||
      t.eq2QuartoId != null || t.eq2CentralinistaId != null;

  /// Ruoli con almeno una persona assegnata in una delle due parti, in
  /// ordine fisso (Autista, CS, Terzo, Quarto, Centralinista).
  List<({String label, String? v1, String? v2})> get _ruoliCompilati {
    final ruoli = [
      (label: 'Autista', v1: t.eq1AutistaId, v2: t.eq2AutistaId),
      (label: 'CS', v1: t.eq1CsId, v2: t.eq2CsId),
      (label: 'Terzo', v1: t.eq1TerzoId, v2: t.eq2TerzoId),
      (label: 'Quarto', v1: t.eq1QuartoId, v2: t.eq2QuartoId),
      (label: 'Centralino', v1: t.eq1CentralinistaId, v2: t.eq2CentralinistaId),
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

  /// Nome della persona, oppure un trattino attenuato se il ruolo non è
  /// coperto in questa parte del turno.
  Widget _valorePersona(String? id) => id == null
      ? const Text('—', style: TextStyle(fontSize: 13, color: Colors.white24))
      : Text(_n(id), style: const TextStyle(fontSize: 13));
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
                    NotaMarkdown(data: s.descrizione!, fontSize: 12, color: Colors.white54),
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
