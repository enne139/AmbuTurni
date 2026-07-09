import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Scanner barcode/QR a schermo intero: si chiude da solo alla prima lettura
/// restituendo il valore del codice via Navigator.pop (null se l'utente torna
/// indietro senza scansionare). Solo mobile: il plugin non ha implementazione
/// desktop, quindi il chiamante apre questa schermata dietro isMobile — lo
/// stesso pattern già usato per add_2_calendar nel Piano turni. Il permesso
/// CAMERA sta nel manifest del plugin stesso (arriva via manifest merger
/// anche in release) e la richiesta runtime la gestisce il plugin.
class ScannerBarcodeScreen extends StatefulWidget {
  const ScannerBarcodeScreen({super.key});

  @override
  State<ScannerBarcodeScreen> createState() => _ScannerBarcodeScreenState();
}

class _ScannerBarcodeScreenState extends State<ScannerBarcodeScreen> {
  // Controller esplicito solo per la torcia (magazzini bui): per il resto
  // valgono i default del plugin (tutti i formati, camera posteriore).
  final _controller = MobileScannerController();
  // onDetect arriva a raffica finché il codice resta inquadrato: senza il
  // guard si farebbero pop multipli della route.
  bool _trovato = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_trovato) return;
    final valore = capture.barcodes
        .map((b) => b.rawValue)
        .whereType<String>()
        .where((v) => v.isNotEmpty)
        .firstOrNull;
    if (valore == null) return;
    _trovato = true;
    Navigator.pop(context, valore);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scansiona codice'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flashlight_on_outlined),
            tooltip: 'Torcia',
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            // Il caso tipico è il permesso fotocamera negato: senza
            // errorBuilder resterebbe uno schermo nero senza spiegazioni.
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  error.errorCode == MobileScannerErrorCode.permissionDenied
                      ? 'Permesso fotocamera negato: concedilo dalle '
                          'impostazioni di sistema dell\'app per scansionare.'
                      : 'Fotocamera non disponibile (${error.errorCode.name}).',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Inquadra il codice a barre o il QR del materiale',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
