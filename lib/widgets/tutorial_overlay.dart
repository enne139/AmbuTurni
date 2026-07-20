import 'dart:async';
import 'package:flutter/material.dart';
import '../utils/theme.dart';

/// Un passo del tutorial: area da evidenziare (in coordinate globali, già
/// calcolata da chi chiama avviaTutorial) più titolo e testo esplicativo
/// mostrati nella card accanto al "buco".
class TutorialStep {
  final Rect area;
  final String titolo;
  final String descrizione;
  const TutorialStep({required this.area, required this.titolo, required this.descrizione});
}

/// Mostra in sequenza un overlay a schermo intero con un "buco" ritagliato
/// sull'area di ogni passo e una card con titolo/descrizione (pulsanti
/// Salta/Avanti). Nessuna dipendenza esterna (stessa scelta "niente package
/// per poco codice" del calendario mensile, vedi CLAUDE.md): un solo
/// OverlayEntry con CustomPainter basta, niente GlobalKey per singola icona
/// da mantenere sincronizzati con l'animazione interna di NavigationBar.
/// Il Future restituito si completa quando l'utente arriva in fondo o salta.
// Guardia globale anti-concorrenza: un secondo avvio (es. doppio tap rapido
// su "Rivedi tutorial" prima che il primo overlay si chiuda) inserirebbe una
// seconda OverlayEntry sopra la prima; quella sotto non riceverebbe più
// alcun tap (il GestureDetector a schermo intero del secondo overlay li
// intercetta tutti) e la sua Future non si completerebbe mai, lasciando uno
// scrim residuo che blocca l'interazione.
bool _tutorialInCorso = false;

Future<void> avviaTutorial(BuildContext context, List<TutorialStep> passi) {
  if (passi.isEmpty || _tutorialInCorso) return Future.value();
  _tutorialInCorso = true;
  final completer = Completer<void>();
  late OverlayEntry entry;
  var indice = 0;

  void chiudi() {
    entry.remove();
    _tutorialInCorso = false;
    if (!completer.isCompleted) completer.complete();
  }

  void avanti() {
    indice++;
    if (indice >= passi.length) {
      chiudi();
    } else {
      entry.markNeedsBuild();
    }
  }

  entry = OverlayEntry(
    builder: (_) => _PassoTutorial(
      passo: passi[indice],
      indice: indice,
      totale: passi.length,
      onAvanti: avanti,
      onSalta: chiudi,
    ),
  );
  Overlay.of(context, rootOverlay: true).insert(entry);
  return completer.future;
}

class _PassoTutorial extends StatelessWidget {
  final TutorialStep passo;
  final int indice;
  final int totale;
  final VoidCallback onAvanti;
  final VoidCallback onSalta;

  const _PassoTutorial({
    required this.passo,
    required this.indice,
    required this.totale,
    required this.onAvanti,
    required this.onSalta,
  });

  @override
  Widget build(BuildContext context) {
    final area = passo.area;
    final mq = MediaQuery.of(context);
    final schermo = mq.size;
    // Card sopra il buco quando questo è nella metà inferiore dello schermo
    // (caso tipico: la NavigationBar è in fondo), sotto altrimenti.
    final cardSopra = area.center.dy > schermo.height / 2;
    // Altezza disponibile sul lato opposto al buco: su schermi bassi
    // (telefono in landscape) durante i passi con descrizione più lunga
    // (Piano turni) la Card poteva estendersi oltre il bordo dello schermo
    // e venire tagliata silenziosamente dal clip di default dello Stack.
    // Un minimo di 120 evita comunque un riquadro degenere se lo spazio
    // residuo fosse pochissimo.
    final maxHeight = (cardSopra
            ? area.top - 16 - mq.padding.top
            : schermo.height - area.bottom - 16 - mq.padding.bottom)
        .clamp(120.0, double.infinity);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Tocco ovunque = avanti; blocca anche i tap sulla NavigationBar
          // reale sottostante finché il tutorial è a schermo.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onAvanti,
              child: CustomPaint(painter: _SpotlightPainter(area)),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: cardSopra ? null : area.bottom + 16,
            bottom: cardSopra ? (schermo.height - area.top) + 16 : null,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: Card(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(passo.titolo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Text(passo.descrizione, style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(onPressed: onSalta, child: const Text('Salta')),
                          Text('${indice + 1}/$totale', style: const TextStyle(color: Colors.white38, fontSize: 12)),
                          FilledButton(
                            onPressed: onAvanti,
                            child: Text(indice + 1 == totale ? 'Fine' : 'Avanti'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Ritaglia un "buco" arrotondato nello scrim scuro sull'area evidenziata,
/// con un bordo del colore primario per farla risaltare.
class _SpotlightPainter extends CustomPainter {
  final Rect area;
  const _SpotlightPainter(this.area);

  @override
  void paint(Canvas canvas, Size size) {
    final buco = RRect.fromRectAndRadius(area.inflate(6), const Radius.circular(14));
    final path = Path.combine(
      PathOperation.difference,
      Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
      Path()..addRRect(buco),
    );
    canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: 0.78));
    canvas.drawRRect(
      buco,
      Paint()
        ..color = kPrimary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) => oldDelegate.area != area;
}
