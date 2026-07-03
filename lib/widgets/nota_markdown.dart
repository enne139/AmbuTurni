import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

/// Rende il testo markdown delle note con uno stile coerente con il tema
/// scuro dell'app: senza uno style sheet esplicito flutter_markdown_plus usa
/// i colori di default di Material (pensati per sfondo chiaro), poco
/// leggibili sul nostro sfondo scuro. Condiviso tra il dettaglio turno e il
/// dettaglio assistenza.
class NotaMarkdown extends StatelessWidget {
  final String data;
  const NotaMarkdown({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    const testo = TextStyle(fontSize: 13, color: Colors.white);
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
        a: const TextStyle(fontSize: 13, color: Colors.lightBlueAccent),
      ),
    );
  }
}
