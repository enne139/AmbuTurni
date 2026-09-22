import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import '../utils/theme.dart';

/// Rende testo markdown con uno stile coerente col tema attivo (scuro o
/// chiaro): senza uno style sheet esplicito flutter_markdown_plus usa i
/// colori di default di Material (pensati per sfondo chiaro), poco
/// leggibili sul nostro sfondo scuro di default. Condiviso tra le note di
/// turno/assistenza (stile di default) e la descrizione dei servizi nel
/// dettaglio turno (fontSize/color più piccoli e attenuati, per restare
/// coerente con lo stile "info secondaria" già usato lì). [color] è
/// nullable (non un default costante) perché il colore "principale" dipende
/// dal tema attivo, noto solo a runtime tramite BuildContext.
class NotaMarkdown extends StatelessWidget {
  final String data;
  final double fontSize;
  final Color? color;
  const NotaMarkdown({super.key, required this.data, this.fontSize = 13, this.color});

  @override
  Widget build(BuildContext context) {
    final coloreBase = color ?? coloreTesto(context);
    final testo = TextStyle(fontSize: fontSize, color: coloreBase);
    return MarkdownBody(
      data: data,
      styleSheet: MarkdownStyleSheet(
        p: testo,
        h1: testo.copyWith(fontSize: 20, fontWeight: FontWeight.bold),
        h2: testo.copyWith(fontSize: 18, fontWeight: FontWeight.bold),
        h3: testo.copyWith(fontSize: 16, fontWeight: FontWeight.bold),
        h4: testo.copyWith(fontWeight: FontWeight.bold),
        h5: testo.copyWith(fontWeight: FontWeight.bold),
        h6: testo.copyWith(fontWeight: FontWeight.bold),
        strong: testo.copyWith(fontWeight: FontWeight.bold),
        em: testo.copyWith(fontStyle: FontStyle.italic),
        del: testo.copyWith(decoration: TextDecoration.lineThrough),
        listBullet: testo,
        blockquote: testo.copyWith(color: coloreTesto(context, 0.7)),
        code: testo.copyWith(fontFamily: 'monospace', backgroundColor: coloreTesto(context, 0.12)),
        a: TextStyle(fontSize: fontSize, color: Colors.lightBlueAccent),
      ),
    );
  }
}
