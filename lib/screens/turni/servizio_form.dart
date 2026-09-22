import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../db/helpers.dart';
import '../../db/models.dart';
import '../../providers/app_provider.dart';
import '../../utils/theme.dart';
import '../../widgets/anag_pickers.dart';

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
  String? _erroreCaricamento;

  @override
  void initState() {
    super.initState();
    _descCtrl = TextEditingController();
    _caricaDati();
  }

  /// Carica i dati del servizio esistente in modalità modifica.
  /// Rilegge tutti i servizi del turno e filtra per ID: più semplice che
  /// aggiungere una getServizioById dedicata per un caso così raro.
  Future<void> _caricaDati() async {
    try {
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
    } catch (e) {
      if (mounted) setState(() { _loading = false; _erroreCaricamento = e.toString(); });
    }
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
    try {
      await saveServizio(s);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore durante il salvataggio: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_erroreCaricamento != null) {
      return Scaffold(body: Center(child: Text('Errore: $_erroreCaricamento')));
    }
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
      // CustomScrollView + SliverFillRemaining invece di una Column con
      // Expanded diretto: quando la tastiera riduce l'altezza disponibile
      // (o su schermi piccoli), i campi fissi sopra la descrizione non ci
      // starebbero più nello spazio rimasto e Flutter andrebbe in overflow
      // (il tipico rettangolo giallo/nero). Con lo sliver, se il contenuto
      // fisso non lascia spazio, l'intera schermata diventa scrollabile
      // invece di rompersi; quando lo spazio c'è, il campo lo riempie tutto
      // come richiesto.
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Codice chiamata
                  const Text('Codice chiamata', style: TextStyle(color: kPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: codiciChiamata.map((c) => ChoiceChip(
                      label: Text(c),
                      selected: _codiceChiamata == c,
                      selectedColor: getCodiceColor(c).withValues(alpha: 0.3),
                      labelStyle: TextStyle(color: _codiceChiamata == c ? getCodiceColor(c) : coloreTesto(context, 0.6)),
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
                      selectedColor: getCodiceColor(c).withValues(alpha: 0.3),
                      labelStyle: TextStyle(color: _codiceUscita == c ? getCodiceColor(c) : coloreTesto(context, 0.6)),
                      onSelected: (sel) => setState(() => _codiceUscita = sel ? c : null),
                    )).toList(),
                  ),
                  const SizedBox(height: 20),

                  // Ospedale
                  const Text('Ospedale', style: TextStyle(color: kPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  OspedalePicker(
                    ospedali: anag.ospedali,
                    selectedId: _ospedaleId,
                    onChanged: (v) => setState(() => _ospedaleId = v),
                  ),
                  const SizedBox(height: 20),

                  // Descrizione: accetta markdown.
                  const Text('Descrizione', style: TextStyle(color: kPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            sliver: SliverFillRemaining(
              hasScrollBody: false,
              child: TextFormField(
                controller: _descCtrl,
                expands: true,
                maxLines: null,
                minLines: null,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  hintText: 'Descrizione del servizio in markdown (opzionale)',
                  alignLabelWithHint: true,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
