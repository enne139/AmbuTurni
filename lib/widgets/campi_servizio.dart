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
    if (voci.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(spacing: 12, runSpacing: 2, children: voci),
    );
  }
}
