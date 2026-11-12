import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../db/helpers.dart';
import '../../db/models.dart';
import '../../providers/app_provider.dart';
import '../../utils/theme.dart';
import '../../widgets/campi_servizio.dart';

/// Impostazioni → Campi dei servizi: i campi in più del form di ogni
/// servizio (nome, tipo, valori possibili, mostrato o nascosto). L'elenco
/// viene da AnagraficheProvider, così form e dettaglio dei servizi vedono
/// subito ogni modifica fatta qui.
class CampiServizioScreen extends StatelessWidget {
  const CampiServizioScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final campi = context.watch<AnagraficheProvider>().campiServizio;
    return Scaffold(
      appBar: AppBar(title: const Text('Campi dei servizi')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _apriForm(context, null),
        icon: const Icon(Icons.add),
        label: const Text('Nuovo campo'),
      ),
      body: ListView(
        // Spazio in fondo per non finire sotto il pulsante "Nuovo campo".
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          Text(
            'Campi in più nel modulo di ogni servizio, dopo l\'ospedale. '
            'Quelli nascosti non compaiono nel modulo e nel dettaglio, ma i '
            'valori già salvati restano.',
            style: TextStyle(color: coloreTesto(context, 0.6), fontSize: 13),
          ),
          const SizedBox(height: 12),
          if (campi.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text('Nessun campo: aggiungine uno con "Nuovo campo".',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: coloreTesto(context, 0.5))),
            ),
          for (var i = 0; i < campi.length; i++)
            _CampoCard(
              campo: campi[i],
              onTap: () => _apriForm(context, campi[i]),
              onVisibile: (v) => _cambiaVisibile(context, campi[i], v),
              onSu: i > 0 ? () => _sposta(context, i, i - 1) : null,
              onGiu: i < campi.length - 1 ? () => _sposta(context, i, i + 1) : null,
              onElimina: () => _elimina(context, campi[i]),
            ),
        ],
      ),
    );
  }

  Future<void> _apriForm(BuildContext context, CampoServizio? campo) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => CampoServizioForm(campo: campo)),
      );

  Future<void> _cambiaVisibile(BuildContext context, CampoServizio campo, bool visibile) async {
    await setCampoServizioVisibile(campo.id, visibile);
    if (context.mounted) await context.read<AnagraficheProvider>().ricaricaCampiServizio();
  }

  Future<void> _sposta(BuildContext context, int da, int a) async {
    await spostaCampoServizio(da, a);
    if (context.mounted) await context.read<AnagraficheProvider>().ricaricaCampiServizio();
  }

  /// Conferma con quanti servizi usano il campo (decisione dell'utente),
  /// poi elimina il campo e i suoi valori.
  Future<void> _elimina(BuildContext context, CampoServizio campo) async {
    final n = await contaServiziConCampo(campo.id);
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Eliminare «${campo.nome}»?'),
        content: Text(switch (n) {
          0 => 'Nessun servizio ha un valore in questo campo.',
          1 => 'Un servizio ha un valore in questo campo: verrà tolto.',
          _ => '$n servizi hanno un valore in questo campo: verrà tolto da tutti.',
        }),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina', style: TextStyle(color: kPrimary)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await deleteCampoServizio(campo.id);
    if (context.mounted) await context.read<AnagraficheProvider>().ricaricaCampiServizio();
  }
}

/// Icona del tipo di campo, usata nell'elenco.
IconData _iconaTipo(String tipo) => switch (tipo) {
      kCampoTendina => Icons.arrow_drop_down_circle_outlined,
      kCampoColori => Icons.palette_outlined,
      kCampoNumero => Icons.pin_outlined,
      _ => Icons.short_text,
    };

class _CampoCard extends StatelessWidget {
  final CampoServizio campo;
  final VoidCallback onTap;
  final ValueChanged<bool> onVisibile;
  final VoidCallback? onSu;
  final VoidCallback? onGiu;
  final VoidCallback onElimina;

  const _CampoCard({
    required this.campo,
    required this.onTap,
    required this.onVisibile,
    required this.onSu,
    required this.onGiu,
    required this.onElimina,
  });

  @override
  Widget build(BuildContext context) {
    // Un campo nascosto resta in elenco ma attenuato, come un'opzione spenta.
    final opacita = campo.visibile ? 1.0 : 0.5;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          child: Row(
            children: [
              Opacity(
                opacity: opacita,
                child: Icon(_iconaTipo(campo.tipo), color: coloreTesto(context, 0.7)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Opacity(
                  opacity: opacita,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(campo.nome, style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      _anteprima(context),
                    ],
                  ),
                ),
              ),
              Switch(
                value: campo.visibile,
                activeTrackColor: kPrimary,
                onChanged: onVisibile,
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_upward, size: 18),
                    color: coloreTesto(context, 0.6),
                    onPressed: onSu,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Sposta su',
                  ),
                  IconButton(
                    icon: const Icon(Icons.arrow_downward, size: 18),
                    color: coloreTesto(context, 0.6),
                    onPressed: onGiu,
                    visualDensity: VisualDensity.compact,
                    tooltip: 'Sposta giù',
                  ),
                ],
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, size: 20, color: coloreTesto(context, 0.54)),
                onSelected: (v) {
                  if (v == 'edit') onTap();
                  if (v == 'del') onElimina();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Modifica')),
                  PopupMenuItem(value: 'del', child: Text('Elimina', style: TextStyle(color: kPrimary))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Riga sotto il nome: tipo e valori possibili ("Tendina · M, F, A"),
  /// con i pallini per i campi a colori, e "nascosto" se non è mostrato.
  Widget _anteprima(BuildContext context) {
    final stile = TextStyle(color: coloreTesto(context, 0.55), fontSize: 12);
    final nascosto = campo.visibile ? '' : ' · nascosto';
    if (campo.tipo == kCampoColori) {
      return Wrap(
        spacing: 6,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Colori ·', style: stile),
          for (final o in campo.opzioni)
            Row(mainAxisSize: MainAxisSize.min, children: [
              PallinoColore(colore: o.colore, size: 10),
              const SizedBox(width: 3),
              Text(o.nome, style: stile),
            ]),
          if (nascosto.isNotEmpty) Text(nascosto.substring(3), style: stile),
        ],
      );
    }
    final valori = campo.tipo == kCampoTendina ? ' · ${campo.opzioni.map((o) => o.nome).join(', ')}' : '';
    return Text('${nomeTipoCampo(campo.tipo)}$valori$nascosto', style: stile);
  }
}

/// Un valore dell'elenco mentre lo si modifica nel form: l'id resta quello
/// salvato (i servizi puntano all'id), il nome sta nel controller.
class _OpzioneInModifica {
  final String id;
  final TextEditingController ctrl;
  String? colore;
  _OpzioneInModifica({required this.id, required String nome, this.colore})
      : ctrl = TextEditingController(text: nome);
}

/// Form per creare o modificare un campo personalizzato.
class CampoServizioForm extends StatefulWidget {
  final CampoServizio? campo;
  const CampoServizioForm({super.key, this.campo});

  @override
  State<CampoServizioForm> createState() => _CampoServizioFormState();
}

class _CampoServizioFormState extends State<CampoServizioForm> {
  late final TextEditingController _nomeCtrl;
  late String _tipo;
  late bool _visibile;
  // I valori restano in memoria anche passando a testo o numero: se si torna
  // a tendina o colori prima di salvare si ritrovano. Si salvano solo per i
  // tipi che li usano.
  late final List<_OpzioneInModifica> _opzioni;
  bool _saving = false;

  bool get _haOpzioni => _tipo == kCampoTendina || _tipo == kCampoColori;

  @override
  void initState() {
    super.initState();
    final c = widget.campo;
    _nomeCtrl = TextEditingController(text: c?.nome ?? '');
    _tipo = c?.tipo ?? kCampoTendina;
    _visibile = c?.visibile ?? true;
    _opzioni = [
      for (final o in c?.opzioni ?? const <OpzioneCampo>[])
        _OpzioneInModifica(id: o.id, nome: o.nome, colore: o.colore),
    ];
    if (_opzioni.isEmpty) _aggiungiOpzione(aggiorna: false);
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    for (final o in _opzioni) {
      o.ctrl.dispose();
    }
    super.dispose();
  }

  /// Primo colore della palette non ancora usato dagli altri valori, così
  /// ogni valore nuovo parte con un colore diverso.
  String _coloreLibero() {
    final usati = _opzioni.map((o) => o.colore).toSet();
    return kColorPalette.firstWhere((c) => !usati.contains(c), orElse: () => kColorPalette.first);
  }

  void _aggiungiOpzione({bool aggiorna = true}) {
    final nuova = _OpzioneInModifica(
      id: newId(),
      nome: '',
      colore: _tipo == kCampoColori ? _coloreLibero() : null,
    );
    if (aggiorna) {
      setState(() => _opzioni.add(nuova));
    } else {
      _opzioni.add(nuova);
    }
  }

  void _togliOpzione(_OpzioneInModifica o) {
    setState(() => _opzioni.remove(o));
    o.ctrl.dispose();
  }

  /// Passando a "Colori" i valori senza colore ne ricevono uno: tendina e
  /// colori hanno gli stessi valori (stessi id), quindi i servizi tengono
  /// quello che avevano.
  void _cambiaTipo(String tipo) => setState(() {
        _tipo = tipo;
        if (tipo == kCampoColori) {
          for (final o in _opzioni) {
            o.colore ??= _coloreLibero();
          }
        }
      });

  Future<void> _scegliColore(_OpzioneInModifica o) async {
    final scelto = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Colore'),
        content: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: kColorPalette.map((hex) {
            final sel = o.colore == hex;
            return GestureDetector(
              onTap: () => Navigator.pop(ctx, hex),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colorFromHex(hex),
                  shape: BoxShape.circle,
                  border: sel ? Border.all(color: coloreTesto(ctx), width: 3) : null,
                ),
                child: sel ? Icon(Icons.check, color: coloreTesto(ctx), size: 18) : null,
              ),
            );
          }).toList(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annulla')),
        ],
      ),
    );
    if (scelto != null) setState(() => o.colore = scelto);
  }

  void _avvisa(String testo) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(testo)));

  Future<void> _salva() async {
    final nome = _nomeCtrl.text.trim();
    if (nome.isEmpty) return _avvisa('Scrivi il nome del campo');
    final anag = context.read<AnagraficheProvider>();
    final doppione = anag.campiServizio.any(
        (c) => c.id != widget.campo?.id && c.nome.toLowerCase() == nome.toLowerCase());
    if (doppione) return _avvisa('Esiste già un campo «$nome»');

    final opzioni = <OpzioneCampo>[];
    if (_haOpzioni) {
      final visti = <String>{};
      for (final o in _opzioni) {
        final n = o.ctrl.text.trim();
        if (n.isEmpty) continue; // righe lasciate vuote: si ignorano
        if (!visti.add(n.toLowerCase())) return _avvisa('Il valore «$n» c\'è due volte');
        opzioni.add(OpzioneCampo(
          id: o.id,
          nome: n,
          colore: _tipo == kCampoColori ? (o.colore ?? kColorPalette.first) : null,
        ));
      }
      if (opzioni.isEmpty) return _avvisa('Aggiungi almeno un valore');
    }

    final campo = CampoServizio(
      id: widget.campo?.id ?? newId(),
      nome: nome,
      tipo: _tipo,
      opzioni: opzioni,
      visibile: _visibile,
      ordine: widget.campo?.ordine ?? 0,
    );

    // In modifica: se dei servizi perdono il valore (tipo cambiato o valore
    // tolto dall'elenco) lo si dice prima, con quanti sono.
    if (widget.campo != null) {
      final n = await contaValoriNonPiuValidi(campo);
      if (!mounted) return;
      if (n > 0) {
        final tipoCambiato = !(widget.campo!.haOpzioni && campo.haOpzioni) && widget.campo!.tipo != campo.tipo;
        final quanti = n == 1 ? 'un servizio' : '$n servizi';
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Togliere dei valori?'),
            content: Text(tipoCambiato
                ? 'Cambiando il tipo, il valore di «$nome» viene tolto da $quanti.'
                : 'Hai tolto dall\'elenco un valore usato da $quanti: verrà tolto anche da lì.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Salva', style: TextStyle(color: kPrimary)),
              ),
            ],
          ),
        );
        if (ok != true) return;
      }
    }

    setState(() => _saving = true);
    try {
      await saveCampoServizio(campo);
      await anag.ricaricaCampiServizio();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _avvisa('Errore durante il salvataggio: $e');
    }
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
      );

  @override
  Widget build(BuildContext context) {
    final spiegazione = switch (_tipo) {
      kCampoTendina => 'Si sceglie un valore da un menu a tendina.',
      kCampoColori => 'Si sceglie un valore tra quelli dell\'elenco, ognuno col suo colore.',
      kCampoNumero => 'Si scrive un numero, per esempio un\'età.',
      _ => 'Si scrive un testo libero.',
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.campo == null ? 'Nuovo campo' : 'Modifica campo'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(icon: const Icon(Icons.check), onPressed: _salva, tooltip: 'Salva'),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _label('Nome'),
          TextField(
            controller: _nomeCtrl,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'es. Sesso'),
          ),
          const SizedBox(height: 20),
          _label('Tipo'),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              for (final t in tipiCampoServizio)
                ButtonSegment(value: t, label: Text(nomeTipoCampo(t))),
            ],
            selected: {_tipo},
            onSelectionChanged: (s) => _cambiaTipo(s.first),
          ),
          const SizedBox(height: 6),
          Text(spiegazione, style: TextStyle(color: coloreTesto(context, 0.55), fontSize: 12)),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mostra nel servizio'),
            subtitle: Text(
              'Se lo nascondi non compare nel modulo e nel dettaglio, ma i valori già salvati restano.',
              style: TextStyle(color: coloreTesto(context, 0.55), fontSize: 12),
            ),
            value: _visibile,
            activeTrackColor: kPrimary,
            onChanged: (v) => setState(() => _visibile = v),
          ),
          if (_haOpzioni) ...[
            const SizedBox(height: 12),
            _label('Valori'),
            for (var i = 0; i < _opzioni.length; i++)
              Padding(
                key: ObjectKey(_opzioni[i]),
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    if (_tipo == kCampoColori) ...[
                      InkWell(
                        onTap: () => _scegliColore(_opzioni[i]),
                        customBorder: const CircleBorder(),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: PallinoColore(colore: _opzioni[i].colore, size: 28),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: TextField(
                        controller: _opzioni[i].ctrl,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(hintText: 'Valore ${i + 1}'),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Togli valore',
                      color: coloreTesto(context, 0.54),
                      onPressed: _opzioni.length > 1 ? () => _togliOpzione(_opzioni[i]) : null,
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _aggiungiOpzione,
                icon: const Icon(Icons.add),
                label: const Text('Aggiungi valore'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
