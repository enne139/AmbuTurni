import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../db/backup.dart';
import '../../db/helpers.dart';
import '../../db/models.dart';
import '../../providers/app_provider.dart';
import '../../utils/theme.dart';

/// Schermata Impostazioni: CRUD di associazioni, persone, ospedali, tipologie.
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
          Divider(height: 32),
          _SezioneAssociazioni(),
          Divider(height: 32),
          _SezionePersone(),
          Divider(height: 32),
          _SezioneOspedali(),
          Divider(height: 32),
          _SezioneTipologie(),
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
      onAdd: () => _dialogNome(context, 'Nuova associazione', 'Nome', (nome) async {
        await saveAssociazione(nome);
        if (context.mounted) context.read<AnagraficheProvider>().carica();
      }),
      onEdit: (a) => _dialogNome(context, 'Modifica associazione', 'Nome', (nome) async {
        await saveAssociazione(nome, id: a.id);
        if (context.mounted) context.read<AnagraficheProvider>().carica();
      }, iniziale: a.nome),
      onDelete: (a) async {
        await deleteAssociazione(a.id);
        if (context.mounted) context.read<AnagraficheProvider>().carica();
      },
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
      onDelete: (p) async {
        await deletePersona(p.id);
        if (context.mounted) context.read<AnagraficheProvider>().carica();
      },
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
          TextField(controller: cognCtrl, decoration: const InputDecoration(labelText: 'Cognome')),
          const SizedBox(height: 12),
          TextField(controller: nomeCtrl, decoration: const InputDecoration(labelText: 'Nome')),
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
      onDelete: (o) async {
        await deleteOspedale(o.id);
        if (context.mounted) context.read<AnagraficheProvider>().carica();
      },
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
          TextField(controller: nomeCtrl, decoration: const InputDecoration(labelText: 'Nome')),
          const SizedBox(height: 12),
          TextField(controller: cittaCtrl, decoration: const InputDecoration(labelText: 'Città (opzionale)')),
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
      onAdd: () => _dialogNome(context, 'Nuova tipologia', 'Nome', (nome) async {
        await saveTipologiaTurno(nome);
        if (context.mounted) context.read<AnagraficheProvider>().carica();
      }),
      onEdit: (t) => _dialogNome(context, 'Modifica tipologia', 'Nome', (nome) async {
        await saveTipologiaTurno(nome, id: t.id);
        if (context.mounted) context.read<AnagraficheProvider>().carica();
      }, iniziale: t.nome),
      onDelete: null, // Le tipologie non si eliminano (come da spec originale)
    );
  }
}

// ---------------------------------------------------------------------------
// Sezione generica (lista + FAB add + swipe/popup edit/delete)
// ---------------------------------------------------------------------------

class _SezioneAnag<T> extends StatelessWidget {
  final String titolo;
  final IconData icon;
  final List<T> items;
  final String Function(T) labelOf;
  final String? Function(T) sublabelOf;
  final VoidCallback onAdd;
  final Future<void> Function(T) onEdit;
  final Future<void> Function(T)? onDelete;

  const _SezioneAnag({
    required this.titolo,
    required this.icon,
    required this.items,
    required this.labelOf,
    required this.sublabelOf,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Icon(icon, size: 18, color: kPrimary),
                const SizedBox(width: 8),
                Text(titolo, style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
              ]),
              IconButton(icon: const Icon(Icons.add, size: 20), onPressed: onAdd),
            ],
          ),
        ),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text('Nessun elemento', style: TextStyle(color: Colors.white38, fontSize: 13)),
          )
        else
          ...items.map((item) => ListTile(
                dense: true,
                title: Text(labelOf(item)),
                subtitle: sublabelOf(item) != null ? Text(sublabelOf(item)!, style: const TextStyle(color: Colors.white54)) : null,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    icon: const Icon(Icons.edit, size: 18, color: Colors.white54),
                    onPressed: () => onEdit(item),
                    visualDensity: VisualDensity.compact,
                  ),
                  if (onDelete != null)
                    IconButton(
                      icon: const Icon(Icons.delete, size: 18, color: kPrimary),
                      onPressed: () => onDelete!(item),
                      visualDensity: VisualDensity.compact,
                    ),
                ]),
              )),
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
      await exportBackup();
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
            child: Row(children: [
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
          ),
      ],
    );
  }
}

// Helper per dialog con un solo campo di testo (associazione, tipologia…).
Future<void> _dialogNome(
  BuildContext context,
  String titolo,
  String campo,
  Future<void> Function(String) onSalva, {
  String iniziale = '',
}) async {
  final ctrl = TextEditingController(text: iniziale);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titolo),
      content: TextField(controller: ctrl, decoration: InputDecoration(labelText: campo)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salva')),
      ],
    ),
  );
  if (ok == true && ctrl.text.trim().isNotEmpty) {
    await onSalva(ctrl.text.trim());
  }
}
