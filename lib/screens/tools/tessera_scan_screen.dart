import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../utils/tessere_tipi.dart';

/// Esito di una scansione: il contenuto letto e il tipo già tradotto nelle
/// stringhe di tessere_tipi.dart (null se la simbologia non è tra quelle che
/// l'app sa disegnare: il form ripiega su Code 128).
class ScansioneTessera {
  final String valore;
  final String? tipo;
  const ScansioneTessera(this.valore, this.tipo);
}

/// Traduce la simbologia rilevata da mobile_scanner nel tipo salvato dall'app.
/// I codici a barre 1D lineari diventano tutti Code 128 (l'unico 1D generico
/// che l'app ridisegna); EAN e QR mantengono il loro tipo; il resto è null.
String? _tipoDaFormat(BarcodeFormat f) {
  switch (f) {
    case BarcodeFormat.ean13:
      return kTipoEan13;
    case BarcodeFormat.ean8:
      return kTipoEan8;
    case BarcodeFormat.qrCode:
      return kTipoQr;
    case BarcodeFormat.code128:
    case BarcodeFormat.code39:
    case BarcodeFormat.code93:
    case BarcodeFormat.codabar:
      return kTipoCode128;
    default:
      return null;
  }
}

/// Fotocamera a schermo intero per leggere il codice di una tessera. Chiude la
/// schermata restituendo la prima lettura valida come [ScansioneTessera], o
/// null se l'utente torna indietro senza scansionare. Raggiungibile solo dove
/// mobile_scanner ha un'implementazione (Android/iOS/web): il form nasconde il
/// pulsante sul desktop.
class TesseraScanScreen extends StatefulWidget {
  const TesseraScanScreen({super.key});

  @override
  State<TesseraScanScreen> createState() => _TesseraScanScreenState();
}

class _TesseraScanScreenState extends State<TesseraScanScreen> {
  final MobileScannerController _controller = MobileScannerController();
  // Una lettura valida chiude la schermata: il flag evita che i frame
  // successivi, che arrivano finché la fotocamera non si ferma, provochino
  // più Navigator.pop in cascata.
  bool _preso = false;

  void _onDetect(BarcodeCapture capture) {
    if (_preso) return;
    for (final b in capture.barcodes) {
      final valore = b.rawValue;
      if (valore != null && valore.isNotEmpty) {
        _preso = true;
        Navigator.of(context).pop(ScansioneTessera(valore, _tipoDaFormat(b.format)));
        return;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Inquadra il codice')),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          // Riquadro di mira: nessun effetto sulla lettura (mobile_scanner
          // legge tutto il frame), solo un aiuto a centrare il codice.
          IgnorePointer(
            child: Container(
              width: 260,
              height: 160,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
