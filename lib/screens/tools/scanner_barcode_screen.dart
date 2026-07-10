import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Scanner barcode/QR a schermo intero: si chiude da solo alla prima lettura
/// restituendo il valore del codice via Navigator.pop (null se l'utente torna
/// indietro senza scansionare). Mobile e web (il chiamante apre questa
/// schermata dietro !isDesktop): su mobile il permesso CAMERA sta nel
/// manifest del plugin stesso (arriva via manifest merger anche in release)
/// e la richiesta runtime la gestisce il plugin; sul web la richiesta è
/// quella nativa del browser (getUserMedia, richiede un contesto sicuro:
/// HTTPS o localhost, come già il login in produzione) e la libreria di
/// decodifica (ZXing) viene caricata da uno script esterno al primo uso,
/// nessuna config aggiuntiva in index.html richiesta dal plugin dalla v5.
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

  /// Messaggio per l'errore della fotocamera, differenziato su web perché lì
  /// il permesso e i requisiti (HTTPS) sono del browser, non dell'app.
  String _messaggioErrore(MobileScannerErrorCode codice) {
    if (codice == MobileScannerErrorCode.permissionDenied) {
      return kIsWeb
          ? 'Permesso fotocamera negato: concedilo dalle impostazioni del '
              'sito nel browser per scansionare.'
          : 'Permesso fotocamera negato: concedilo dalle impostazioni di '
              'sistema dell\'app per scansionare.';
    }
    if (kIsWeb && codice == MobileScannerErrorCode.unsupported) {
      return 'Il browser non supporta l\'accesso alla fotocamera: serve una '
          'connessione HTTPS e un browser aggiornato (Chrome, Edge, Firefox).';
    }
    return 'Fotocamera non disponibile (${codice.name}).';
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
          // La torcia non è supportata sui video track del web (limite del
          // browser, non del plugin: toggleTorch() lancia UnsupportedError
          // lì), quindi il pulsante compare solo su mobile.
          if (!kIsWeb)
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
            // Testo diverso su web: è il browser a chiedere il permesso
            // (site settings), non le impostazioni di sistema dell'app.
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  _messaggioErrore(error.errorCode),
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
