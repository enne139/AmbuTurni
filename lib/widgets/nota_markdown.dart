import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

/// Rende testo markdown con uno stile coerente con il tema scuro dell'app:
/// senza uno style sheet esplicito flutter_markdown_plus usa i colori di
/// default di Material (pensati per sfondo chiaro), poco leggibili sul
/// nostro sfondo scuro. Condiviso tra le note di turno/assistenza (stile di
/// default) e la descrizione dei servizi nel dettaglio turno (fontSize/color
/// più piccoli e attenuati, per restare coerente con lo stile "info
/// secondaria" già usato lì).
class NotaMarkdown extends StatelessWidget {
  final String data;
  final double fontSize;
  final Color color;
  const NotaMarkdown({super.key, required this.data, this.fontSize = 13, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    final testo = TextStyle(fontSize: fontSize, color: color);
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
        blockquote: testo.copyWith(color: Colors.white70),
        code: testo.copyWith(fontFamily: 'monospace', backgroundColor: Colors.white12),
        a: TextStyle(fontSize: fontSize, color: Colors.lightBlueAccent),
      ),
    );
  }
}
