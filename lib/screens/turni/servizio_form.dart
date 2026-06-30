import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../db/helpers.dart';
import '../../db/models.dart';
import '../../providers/app_provider.dart';
import '../../utils/theme.dart';

/// Form per aggiungere o modificare un servizio di un turno.
class ServizioForm extends StatefulWidget {
  final String turnoId;
  final String? servizioId;
  final int ordine;
  const ServizioForm({super.key, required this.turnoId, this.servizioId, required this.ordine});

  @override
  State<ServizioForm> createState() => _ServizioFormState();
}

class _ServizioFormState extends State<ServizioForm> {
  String? _codiceChiamata;
  String? _codiceUscita;
  String? _ospedaleId;
  late TextEditingController _descCtrl;
  bool _loading = true;
  bool _saving = false;
  String? _existingId;

  @override
  void initState() {
    super.initState();
    _descCtrl = TextEditingController();
    _caricaDati();
  }

  /// Apre un dialog per creare un nuovo ospedale al volo, lo salva e
  /// lo auto-seleziona nel campo ospedale del servizio.
  Future<void> _nuovoOspedale() async {
    final nomeCtrl = TextEditingController();
    final cittaCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuovo ospedale'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: nomeCtrl,
            decoration: const InputDecoration(labelText: 'Nome'),
            textCapitalization: TextCapitalization.words,
            autofocus: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: cittaCtrl,
            decoration: const InputDecoration(labelText: 'Città (opzionale)'),
            textCapitalization: TextCapitalization.words,
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salva')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final nome = nomeCtrl.text.trim();
    if (nome.isEmpty) return;
    final id = newId();
    final citta = cittaCtrl.text.trim().isEmpty ? null : cittaCtrl.text.trim();
    await saveOspedale(nome, citta, id: id);
    if (!mounted) return;
    await context.read<AnagraficheProvider>().carica();
    setState(() => _ospedaleId = id);
  }

  /// Carica i dati del servizio esistente in modalità modifica.
  /// Rilegge tutti i servizi del turno e filtra per ID: più semplice che
  /// aggiungere una getServizioById dedicata per un caso così raro.
  Future<void> _caricaDati() async {
    if (widget.servizioId != null) {
      final servizi = await getServizi(widget.turnoId);
      final s = servizi.where((s) => s.id == widget.servizioId).firstOrNull;
      if (s != null && mounted) {
        setState(() {
          _existingId = s.id;
          _codiceChiamata = s.codiceChiamata;
          _codiceUscita = s.codiceUscita;
          _ospedaleId = s.ospedaleId;
          _descCtrl.text = s.descrizione ?? '';
        });
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _salva() async {
    setState(() => _saving = true);
    final s = Servizio(
      id: _existingId ?? newId(),
      turnoId: widget.turnoId,
      codiceChiamata: _codiceChiamata,
      codiceUscita: _codiceUscita,
      ospedaleId: _ospedaleId,
      descrizione: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      ordine: widget.ordine,
    );
    await saveServizio(s);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final anag = context.watch<AnagraficheProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.servizioId == null ? 'Nuovo servizio' : 'Modifica servizio'),
        actions: [
          if (_saving)
            const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
          else
            IconButton(icon: const Icon(Icons.check), onPressed: _salva),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Codice chiamata
          const Text('Codice chiamata', style: TextStyle(color: kPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: codiciChiamata.map((c) => ChoiceChip(
              label: Text(c),
              selected: _codiceChiamata == c,
              selectedColor: getCodiceColor(c).withOpacity(0.3),
              labelStyle: TextStyle(color: _codiceChiamata == c ? getCodiceColor(c) : Colors.white60),
              onSelected: (sel) => setState(() => _codiceChiamata = sel ? c : null),
            )).toList(),
          ),
          const SizedBox(height: 20),

          // Codice uscita
          const Text('Codice uscita', style: TextStyle(color: kPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: codiciUscita.map((c) => ChoiceChip(
              label: Text(c),
              selected: _codiceUscita == c,
              selectedColor: getCodiceColor(c).withOpacity(0.3),
              labelStyle: TextStyle(color: _codiceUscita == c ? getCodiceColor(c) : Colors.white60),
              onSelected: (sel) => setState(() => _codiceUscita = sel ? c : null),
            )).toList(),
          ),
          const SizedBox(height: 20),

          // Ospedale
          const Text('Ospedale', style: TextStyle(color: kPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _ospedaleId,
            hint: const Text('Seleziona ospedale (opzionale)'),
            dropdownColor: kSurface,
            decoration: const InputDecoration(),
            items: [
              const DropdownMenuItem(value: null, child: Text('—')),
              ...anag.ospedali.map((o) => DropdownMenuItem(value: o.id, child: Text(o.label))),
              const DropdownMenuItem(
                value: '__new__',
                child: Row(children: [
                  Icon(Icons.add, size: 14, color: kPrimary),
                  SizedBox(width: 6),
                  Text('Aggiungi...', style: TextStyle(color: kPrimary, fontSize: 13)),
                ]),
              ),
            ],
            onChanged: (v) {
              if (v == '__new__') {
                _nuovoOspedale();
              } else {
                setState(() => _ospedaleId = v);
              }
            },
          ),
          const SizedBox(height: 20),

          // Descrizione
          const Text('Descrizione', style: TextStyle(color: kPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextFormField(
            controller: _descCtrl,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'Descrizione del servizio (opzionale)'),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
