import 'package:flutter/material.dart';
import '../db/models.dart';
import '../utils/theme.dart';

/// Pallino pieno del colore di un'opzione di un campo a colori. Usato nel
/// form del servizio, nel dettaglio e nelle Impostazioni, così lo stesso
/// valore ha lo stesso aspetto ovunque.
class PallinoColore extends StatelessWidget {
  final String? colore;
  final double size;
  const PallinoColore({super.key, required this.colore, this.size = 12});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: colorFromHex(colore) ?? coloreTesto(context, 0.24),
          shape: BoxShape.circle,
        ),
      );
}

/// Valori dei campi personalizzati di un servizio, nella card del dettaglio
/// turno: "Sesso F  Età 45  Colore invio ● Giallo". Solo i campi [campi]
/// passati (quelli visibili) e solo quelli con un valore valido; se non ce
/// n'è nessuno non occupa spazio. Il campo speciale mostra sesso ed età come
/// due voci, come nel form.
class ValoriCampiServizio extends StatelessWidget {
  final List<CampoServizio> campi;
  final Map<String, dynamic> valori;
  const ValoriCampiServizio({super.key, required this.campi, required this.valori});

  @override
  Widget build(BuildContext context) {
    final voci = <Widget>[];
    // Le tabelle orari vanno sotto le altre voci, ognuna come tabellina
    // nome | ora, come nel form: in fila con le altre non si leggerebbero.
    final tabelle = <Widget>[];
    Widget voce(String nome, String valore) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$nome ', style: TextStyle(color: coloreTesto(context, 0.45), fontSize: 12)),
            Text(valore, style: TextStyle(color: coloreTesto(context, 0.8), fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        );
    for (final campo in campi) {
      final valore = campo.pulisci(valori[campo.id]);
      if (campo.speciale) {
        final sesso = campo.sessoDi(valore);
        final eta = campo.etaDi(valore);
        if (sesso != null) voci.add(voce('Sesso', sesso.nome));
        if (eta != null) voci.add(voce('Età', formatNumeroCampo(eta)));
        continue;
      }
      if (campo.tipo == kCampoTabellaOrari) {
        if (valore is Map) tabelle.add(_tabella(context, campo, valore));
        continue;
      }
      final etichetta = campo.etichetta(valore);
      if (etichetta == null) continue;
      voci.add(Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${campo.nome} ', style: TextStyle(color: coloreTesto(context, 0.45), fontSize: 12)),
          if (campo.tipo == kCampoColori) ...[
            PallinoColore(colore: campo.opzione(valore as String)?.colore, size: 10),
            const SizedBox(width: 4),
          ],
          Text(etichetta, style: TextStyle(color: coloreTesto(context, 0.8), fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ));
    }
    if (voci.isEmpty && tabelle.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (voci.isNotEmpty) Wrap(spacing: 12, runSpacing: 2, children: voci),
          ...tabelle,
        ],
      ),
    );
  }

  /// Tabellina di una tabella orari: titolo e una riga per ogni ora segnata.
  Widget _tabella(BuildContext context, CampoServizio campo, Map<dynamic, dynamic> orari) {
    final attenuato = TextStyle(color: coloreTesto(context, 0.45), fontSize: 12);
    final forte = TextStyle(
      color: coloreTesto(context, 0.8),
      fontSize: 12,
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(campo.nome, style: attenuato),
          Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            children: [
              for (final o in campo.opzioni)
                if (orari.containsKey(o.id))
                  TableRow(children: [
                    Padding(padding: const EdgeInsets.only(right: 12), child: Text(o.nome, style: attenuato)),
                    Text(orari[o.id] as String, style: forte),
                  ]),
            ],
          ),
        ],
      ),
    );
  }
}

/// Combo con ricerca: più valori scelti cercandoli. In alto i valori già
/// scelti come chip con la x, sotto un campo di ricerca che filtra l'elenco
/// mentre si scrive (senza testo mostra tutti quelli non ancora scelti).
/// Scelto un valore il campo si svuota e resta pronto per il successivo.
/// [scelti] e [onChanged] usano gli id, nell'ordine dell'elenco del campo,
/// come la combo box: i due tipi salvano lo stesso valore.
class SceltaConRicerca extends StatefulWidget {
  final CampoServizio campo;
  final List<String> scelti;
  final ValueChanged<List<String>> onChanged;
  const SceltaConRicerca({super.key, required this.campo, required this.scelti, required this.onChanged});

  @override
  State<SceltaConRicerca> createState() => _SceltaConRicercaState();
}

class _SceltaConRicercaState extends State<SceltaConRicerca> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// Gli id scelti dopo aver aggiunto o tolto [id], nell'ordine dell'elenco.
  List<String> _con(String id, bool scelto) => [
        for (final o in widget.campo.opzioni)
          if (o.id == id ? scelto : widget.scelti.contains(o.id)) o.id,
      ];

  @override
  Widget build(BuildContext context) {
    final scelti = widget.campo.opzioni.where((o) => widget.scelti.contains(o.id)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (scelti.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final o in scelti)
                InputChip(
                  label: Text(o.nome),
                  onDeleted: () => widget.onChanged(_con(o.id, false)),
                  deleteButtonTooltipMessage: 'Togli',
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        LayoutBuilder(
          builder: (context, vincoli) => RawAutocomplete<OpzioneCampo>(
            textEditingController: _ctrl,
            focusNode: _focus,
            displayStringForOption: (o) => o.nome,
            optionsBuilder: (testo) {
              final q = testo.text.trim().toLowerCase();
              return widget.campo.opzioni.where(
                  (o) => !widget.scelti.contains(o.id) && (q.isEmpty || o.nome.toLowerCase().contains(q)));
            },
            onSelected: (o) {
              widget.onChanged(_con(o.id, true));
              // RawAutocomplete ha appena scritto il nome nel campo: lo si
              // svuota e gli si ridà il cursore, per cercare subito il
              // valore successivo.
              _ctrl.clear();
              _focus.requestFocus();
            },
            fieldViewBuilder: (context, ctrl, focus, invia) => TextField(
              controller: ctrl,
              focusNode: focus,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Cerca e aggiungi',
                prefixIcon: Icon(Icons.search, size: 18),
              ),
              // Invio sceglie il primo valore trovato.
              onSubmitted: (_) => invia(),
            ),
            optionsViewBuilder: (ctx, scegli, valori) => Align(
              alignment: Alignment.topLeft,
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                elevation: 8,
                borderRadius: BorderRadius.circular(8),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: 250, maxWidth: vincoli.maxWidth),
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    children: [
                      for (final o in valori)
                        InkWell(
                          onTap: () => scegli(o),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            child: Text(o.nome, style: const TextStyle(fontSize: 14)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
