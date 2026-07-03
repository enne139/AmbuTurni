import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../db/backup.dart';
import '../../db/helpers.dart';
import '../../db/models.dart';
import '../../providers/app_provider.dart';
import '../../utils/theme.dart';
import 'turni_filtrati_screen.dart';

/// Schermata Impostazioni: CRUD di associazioni, persone, ospedali, tipologie.
/// Ogni sezione è collassata di default e ha una barra di ricerca interna.
class ImpostazioniScreen extends StatelessWidget {
  const ImpostazioniScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Impostazioni')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: const [
          _SezioneBackup(),
          Divider(height: 24),
          _SezioneAssociazioni(),
          Divider(height: 1),
          _SezionePersone(),
          Divider(height: 1),
          _SezioneOspedali(),
          Divider(height: 1),
          _SezioneTipologie(),
          SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Associazioni
// ---------------------------------------------------------------------------

class _SezioneAssociazioni extends StatelessWidget {
  const _SezioneAssociazioni();

  @override
  Widget build(BuildContext context) {
    final anag = context.watch<AnagraficheProvider>();
    return _SezioneAnag<Associazione>(
      titolo: 'Associazioni',
      icon: Icons.business,
      items: anag.associazioni,
      labelOf: (a) => a.nome,
      sublabelOf: (_) => null,
      colorOf: (a) => colorFromHex(a.colore),
      onAdd: () => _dialogNomeEColore(context, 'Nuova associazione', (nome, colore) async {
        await saveAssociazione(nome, colore: colore);
        if (context.mounted) context.read<AnagraficheProvider>().carica();
      }),
      onEdit: (a) => _dialogNomeEColore(context, 'Modifica associazione', (nome, colore) async {
        await saveAssociazione(nome, id: a.id, colore: colore);
        if (context.mounted) context.read<AnagraficheProvider>().carica();
      }, iniziale: a.nome, coloreIniziale: a.colore),
      onDelete: (a) async {
        await deleteAssociazione(a.id);
        if (context.mounted) context.read<AnagraficheProvider>().carica();
      },
      messaggioVincolo: 'è usata da turni o assistenze esistenti.',
    );
  }
}

// ---------------------------------------------------------------------------
// Persone
// ---------------------------------------------------------------------------

class _SezionePersone extends StatelessWidget {
  const _SezionePersone();

  @override
  Widget build(BuildContext context) {
    final anag = context.watch<AnagraficheProvider>();
    return _SezioneAnag<Persona>(
      titolo: 'Persone',
      icon: Icons.people,
      items: anag.persone,
      labelOf: (p) => p.nomeCompleto,
      sublabelOf: (_) => null,
      onAdd: () => _dialogPersona(context, null),
      onEdit: (p) => _dialogPersona(context, p),
      onView: (p) async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => TurniPersonaScreen(persona: p)));
      },
      onDelete: (p) async {
        await deletePersona(p.id);
        if (context.mounted) context.read<AnagraficheProvider>().carica();
      },
      messaggioVincolo: 'fa parte dell\'equipaggio di turni o assistenze esistenti.',
    );
  }

  Future<void> _dialogPersona(BuildContext context, Persona? p) async {
    final cognCtrl = TextEditingController(text: p?.cognome ?? '');
    final nomeCtrl = TextEditingController(text: p?.nome ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p == null ? 'Nuova persona' : 'Modifica persona'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: cognCtrl, decoration: const InputDecoration(labelText: 'Cognome'), textCapitalization: TextCapitalization.words),
          const SizedBox(height: 12),
          TextField(controller: nomeCtrl, decoration: const InputDecoration(labelText: 'Nome'), textCapitalization: TextCapitalization.words),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salva')),
        ],
      ),
    );
    if (ok == true) {
      final c = cognCtrl.text.trim();
      final n = nomeCtrl.text.trim();
      if (c.isNotEmpty && n.isNotEmpty) {
        await savePersona(c, n, id: p?.id);
        if (context.mounted) context.read<AnagraficheProvider>().carica();
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Ospedali
// ---------------------------------------------------------------------------

class _SezioneOspedali extends StatelessWidget {
  const _SezioneOspedali();

  @override
  Widget build(BuildContext context) {
    final anag = context.watch<AnagraficheProvider>();
    return _SezioneAnag<Ospedale>(
      titolo: 'Ospedali',
      icon: Icons.local_hospital,
      items: anag.ospedali,
      labelOf: (o) => o.nome,
      sublabelOf: (o) => o.citta,
      onAdd: () => _dialogOspedale(context, null),
      onEdit: (o) => _dialogOspedale(context, o),
      onView: (o) async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => TurniOspedaleScreen(ospedale: o)));
      },
      onDelete: (o) async {
        await deleteOspedale(o.id);
        if (context.mounted) context.read<AnagraficheProvider>().carica();
      },
      messaggioVincolo: 'è usato da servizi di turni esistenti.',
    );
  }

  Future<void> _dialogOspedale(BuildContext context, Ospedale? o) async {
    final nomeCtrl = TextEditingController(text: o?.nome ?? '');
    final cittaCtrl = TextEditingController(text: o?.citta ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(o == null ? 'Nuovo ospedale' : 'Modifica ospedale'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nomeCtrl, decoration: const InputDecoration(labelText: 'Nome'), textCapitalization: TextCapitalization.words),
          const SizedBox(height: 12),
          TextField(controller: cittaCtrl, decoration: const InputDecoration(labelText: 'Città (opzionale)'), textCapitalization: TextCapitalization.words),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salva')),
        ],
      ),
    );
    if (ok == true) {
      final n = nomeCtrl.text.trim();
      if (n.isNotEmpty) {
        await saveOspedale(n, cittaCtrl.text.trim().isEmpty ? null : cittaCtrl.text.trim(), id: o?.id);
        if (context.mounted) context.read<AnagraficheProvider>().carica();
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Tipologie turno
// ---------------------------------------------------------------------------

class _SezioneTipologie extends StatelessWidget {
  const _SezioneTipologie();

  @override
  Widget build(BuildContext context) {
    final anag = context.watch<AnagraficheProvider>();
    return _SezioneAnag<TipologiaTurno>(
      titolo: 'Tipologie turno',
      icon: Icons.label,
      items: anag.tipologieTurno,
      labelOf: (t) => t.nome,
      sublabelOf: (_) => null,
      colorOf: (t) => colorFromHex(t.colore),
      onAdd: () => _dialogNomeEColore(context, 'Nuova tipologia', (nome, colore) async {
        await saveTipologiaTurno(nome, colore: colore);
        if (context.mounted) context.read<AnagraficheProvider>().carica();
      }),
      onEdit: (t) => _dialogNomeEColore(context, 'Modifica tipologia', (nome, colore) async {
        await saveTipologiaTurno(nome, id: t.id, colore: colore);
        if (context.mounted) context.read<AnagraficheProvider>().carica();
      }, iniziale: t.nome, coloreIniziale: t.colore),
      onDelete: null, // Le tipologie non si eliminano (come da spec originale)
      onMoveUp: (t) async {
        final idx = anag.tipologieTurno.indexWhere((x) => x.id == t.id);
        if (idx <= 0) return;
        await spostaTipologia(idx, idx - 1);
        if (context.mounted) await context.read<AnagraficheProvider>().carica();
      },
      onMoveDown: (t) async {
        final idx = anag.tipologieTurno.indexWhere((x) => x.id == t.id);
        if (idx < 0 || idx >= anag.tipologieTurno.length - 1) return;
        await spostaTipologia(idx, idx + 1);
        if (context.mounted) await context.read<AnagraficheProvider>().carica();
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Sezione generica collassabile con ricerca
// ---------------------------------------------------------------------------

/// Sezione con header cliccabile (collassa/espande), contatore badge,
/// pulsante + sempre accessibile e campo ricerca quando espansa.
/// Collassata di default per non sovraccaricare la schermata con liste lunghe.
class _SezioneAnag<T> extends StatefulWidget {
  final String titolo;
  final IconData icon;
  final List<T> items;
  final String Function(T) labelOf;
  final String? Function(T) sublabelOf;
  final Color? Function(T)? colorOf;
  final VoidCallback onAdd;
  final Future<void> Function(T) onEdit;
  final Future<void> Function(T)? onDelete;
  // Messaggio mostrato quando il DB blocca l'eliminazione per vincolo FK:
  // spiega all'utente PERCHÉ la voce non si può eliminare (es. usata in turni).
  final String? messaggioVincolo;
  // Frecce di riordino: se non null, compaiono ↑↓ per ogni voce (disabilitate con filtro attivo).
  final Future<void> Function(T)? onMoveUp;
  final Future<void> Function(T)? onMoveDown;
  // Se non null, mostra un pulsante per vedere i turni/assistenze in cui compare la voce
  // (usato da Persone e Ospedali per navigare all'elenco filtrato).
  final Future<void> Function(T)? onView;

  const _SezioneAnag({
    required this.titolo,
    required this.icon,
    required this.items,
    required this.labelOf,
    required this.sublabelOf,
    this.colorOf,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    this.messaggioVincolo,
    this.onMoveUp,
    this.onMoveDown,
    this.onView,
  });

  @override
  State<_SezioneAnag<T>> createState() => _SezioneAnagState<T>();
}

class _SezioneAnagState<T> extends State<_SezioneAnag<T>> {
  bool _expanded = false;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Filtra la lista per il testo corrente cercando in label e sublabel.
  List<T> get _filtered {
    if (_query.isEmpty) return widget.items;
    final q = _query.toLowerCase();
    return widget.items.where((item) {
      return widget.labelOf(item).toLowerCase().contains(q) ||
          (widget.sublabelOf(item)?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  /// Chiede conferma prima di eliminare (un tap accidentale non deve perdere
  /// dati per sempre) e gestisce il rifiuto del DB per vincolo FK: senza il
  /// catch, eliminare una voce ancora referenziata (es. persona in un turno)
  /// fallirebbe senza alcun feedback per l'utente.
  Future<void> _confermaEdElimina(T item) async {
    final label = widget.labelOf(item);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina'),
        content: Text('Eliminare "$label"? L\'operazione non è reversibile.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina', style: TextStyle(color: kPrimary)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.onDelete!(item);
    } catch (e) {
      if (!mounted) return;
      // Le eccezioni FK di sqflite (nativo e FFI) contengono sempre
      // "FOREIGN KEY constraint failed": basta il match sulla stringa,
      // senza importare i tipi di sqflite in una schermata UI.
      final vincoloFk = e.toString().contains('FOREIGN KEY');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(vincoloFk
            ? 'Impossibile eliminare "$label": ${widget.messaggioVincolo ?? 'è ancora usata da altri dati.'}'
            : 'Errore durante l\'eliminazione: $e'),
      ));
    }
  }

  /// Resetta la ricerca quando si chiude la sezione così riaprendo è pulita.
  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      if (!_expanded) {
        _query = '';
        _searchCtrl.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header: tutta la riga collassa/espande tranne il tasto +
        InkWell(
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                Icon(widget.icon, size: 18, color: kPrimary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.titolo,
                    style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                // Badge col numero di elementi totali (visibile anche da collassato)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: kPrimary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${widget.items.length}',
                    style: const TextStyle(color: kPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
                // Pulsante aggiunta sempre visibile (non richiede di espandere prima)
                IconButton(
                  icon: const Icon(Icons.add, size: 20, color: Colors.white70),
                  onPressed: widget.onAdd,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Aggiungi',
                ),
                Icon(
                  _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  color: Colors.white38,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        // Contenuto (solo quando espanso)
        if (_expanded) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Cerca in ${widget.titolo.toLowerCase()}...',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () => setState(() {
                          _query = '';
                          _searchCtrl.clear();
                        }),
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                _query.isEmpty ? 'Nessun elemento' : 'Nessun risultato per "$_query"',
                style: const TextStyle(color: Colors.white38, fontSize: 13),
              ),
            )
          else
            ...filtered.asMap().entries.map((entry) {
              final i = entry.key;
              final item = entry.value;
              final canUp = widget.onMoveUp != null && _query.isEmpty && i > 0;
              final canDown = widget.onMoveDown != null && _query.isEmpty && i < filtered.length - 1;
              final dot = widget.colorOf != null ? widget.colorOf!(item) : null;
              return ListTile(
                dense: true,
                leading: dot != null
                    ? Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                      )
                    : (widget.colorOf != null ? const SizedBox(width: 14, height: 14) : null),
                title: Text(widget.labelOf(item)),
                subtitle: widget.sublabelOf(item) != null
                    ? Text(widget.sublabelOf(item)!, style: const TextStyle(color: Colors.white54))
                    : null,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (widget.onMoveUp != null && _query.isEmpty) ...[
                    IconButton(
                      icon: Icon(Icons.arrow_upward, size: 16, color: canUp ? Colors.white54 : Colors.white12),
                      onPressed: canUp ? () => widget.onMoveUp!(item) : null,
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      icon: Icon(Icons.arrow_downward, size: 16, color: canDown ? Colors.white54 : Colors.white12),
                      onPressed: canDown ? () => widget.onMoveDown!(item) : null,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                  if (widget.onView != null)
                    IconButton(
                      icon: const Icon(Icons.event_note, size: 18, color: Colors.white54),
                      onPressed: () => widget.onView!(item),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Vedi turni',
                    ),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 18, color: Colors.white54),
                    onPressed: () => widget.onEdit(item),
                    visualDensity: VisualDensity.compact,
                  ),
                  if (widget.onDelete != null)
                    IconButton(
                      icon: const Icon(Icons.delete, size: 18, color: kPrimary),
                      onPressed: () => _confermaEdElimina(item),
                      visualDensity: VisualDensity.compact,
                    ),
                ]),
              );
            }),
          const SizedBox(height: 4),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Backup / Ripristino
// ---------------------------------------------------------------------------

class _SezioneBackup extends StatefulWidget {
  const _SezioneBackup();
  @override
  State<_SezioneBackup> createState() => _SezioneBackupState();
}

class _SezioneBackupState extends State<_SezioneBackup> {
  bool _busy = false;

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final path = await exportBackup();
      if (mounted) {
        final msg = path != null ? 'Backup salvato.' : 'Export annullato.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore export: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportSemplificato() async {
    setState(() => _busy = true);
    try {
      final path = await exportSemplificato();
      if (mounted) {
        final msg = path != null ? 'Export leggibile salvato.' : 'Export annullato.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore export: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    // Chiede conferma prima di sovrascrivere tutti i dati.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Importa backup'),
        content: const Text(
          'L\'import sovrascrive TUTTI i dati locali con quelli del file scelto. '
          'Questa operazione non è reversibile.\n\nContinuare?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Importa', style: TextStyle(color: kPrimary)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    final msg = await importBackup();
    if (!mounted) return;
    setState(() => _busy = false);

    // Ricarica tutti i provider dopo l'import.
    if (mounted) {
      context.read<AnagraficheProvider>().carica();
      context.read<TurniProvider>().ricarica();
      context.read<AssistezeProvider>().ricarica();
      context.read<StatisticheProvider>().ricarica();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            const Icon(Icons.backup, size: 18, color: kPrimary),
            const SizedBox(width: 8),
            const Text('Backup / Ripristino', style: TextStyle(color: kPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
          ]),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: LinearProgressIndicator(),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.upload_file, size: 18),
                    label: const Text('Esporta JSON'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kPrimary,
                      side: const BorderSide(color: kPrimary),
                    ),
                    onPressed: _export,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Importa JSON'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    onPressed: _import,
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.table_rows_outlined, size: 18),
                  label: const Text('Esporta JSON leggibile (turni e assistenze)'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white54,
                    side: const BorderSide(color: Colors.white12),
                  ),
                  onPressed: _exportSemplificato,
                ),
              ),
            ]),
          ),
      ],
    );
  }
}

/// Dialog con campo nome e palette colori per associazioni e tipologie.
Future<void> _dialogNomeEColore(
  BuildContext context,
  String titolo,
  Future<void> Function(String nome, String? colore) onSalva, {
  String iniziale = '',
  String? coloreIniziale,
}) async {
  final ctrl = TextEditingController(text: iniziale);
  String? coloreSelezionato = coloreIniziale;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocalState) => AlertDialog(
        title: Text(titolo),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(labelText: 'Nome'),
              textCapitalization: TextCapitalization.words,
              autofocus: true,
            ),
            const SizedBox(height: 16),
            const Text('Colore', style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kColorPalette.map((hex) {
                final c = colorFromHex(hex)!;
                final sel = coloreSelezionato == hex;
                return GestureDetector(
                  onTap: () => setLocalState(() => coloreSelezionato = sel ? null : hex),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: sel ? Border.all(color: Colors.white, width: 3) : null,
                    ),
                    child: sel ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salva')),
        ],
      ),
    ),
  );
  if (ok == true && ctrl.text.trim().isNotEmpty) {
    await onSalva(ctrl.text.trim(), coloreSelezionato);
  }
}

