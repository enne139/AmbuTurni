import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../utils/platform_check.dart';
import '../../utils/scanner_errors.dart';

/// Contatore rapido, indipendente dal resto del magazzino: serve a contare a
/// mano pacchi/materiali mentre si maneggiano fisicamente (es. scarico di un
/// furgone), senza legarlo a un materiale né toccare la giacenza sul server —
/// solo un numero che sale/scende. Due modalità, cambiate dal pulsante in
/// AppBar: manuale (due pulsanti grandi +1/-1, pensati per essere premuti
/// anche con i guanti o tenendo in mano delle scatole) e scansione (ogni
/// codice a barre/QR inquadrato incrementa di 1, per contare oggetti che
/// passano davanti alla fotocamera uno dopo l'altro).
class ContaScreen extends StatefulWidget {
  const ContaScreen({super.key});

  @override
  State<ContaScreen> createState() => _ContaScreenState();
}

class _ContaScreenState extends State<ContaScreen> {
  int _conteggio = 0;
  bool _modalitaScan = false;
  // Creato al volo alla prima scansione: in modalità manuale non serve tenere
  // la fotocamera pronta.
  MobileScannerController? _controller;
  DateTime? _ultimoConteggioScan;

  // Tempo minimo tra due conteggi in modalità scansione: senza, lo stesso
  // codice inquadrato per più di un istante verrebbe contato più volte
  // (onDetect arriva a raffica finché il codice resta a fuoco).
  static const _cooldownScan = Duration(milliseconds: 1200);

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _incrementa() => setState(() => _conteggio++);

  void _decrementa() {
    if (_conteggio == 0) return; // un conteggio fisico non va sotto zero
    setState(() => _conteggio--);
  }

  void _reset() => setState(() => _conteggio = 0);

  /// Passa tra modalità manuale e scansione, avviando/fermando la fotocamera
  /// di conseguenza: tenerla accesa mentre si conta a mano sprecherebbe
  /// batteria senza motivo.
  void _cambiaModalita() {
    setState(() => _modalitaScan = !_modalitaScan);
    if (_modalitaScan) {
      _controller ??= MobileScannerController(autoStart: false);
      _controller!.start();
    } else {
      _controller?.stop();
    }
  }

  void _onDetect(BarcodeCapture capture) {
    final haCodice = capture.barcodes.any((b) => (b.rawValue ?? '').isNotEmpty);
    if (!haCodice) return;
    final ora = DateTime.now();
    if (_ultimoConteggioScan != null &&
        ora.difference(_ultimoConteggioScan!) < _cooldownScan) {
      return;
    }
    _ultimoConteggioScan = ora;
    _incrementa();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conta'),
        actions: [
          // Modalità scansione solo su Android/iOS/web: mobile_scanner non
          // ha canale per il desktop nativo (stesso limite del resto
          // dell'app), quindi lì resta solo il conteggio manuale.
          if (!isDesktop)
            IconButton(
              icon: Icon(_modalitaScan
                  ? Icons.touch_app_outlined
                  : Icons.qr_code_scanner),
              tooltip: _modalitaScan
                  ? 'Passa al conteggio manuale'
                  : 'Passa al conteggio con la fotocamera',
              onPressed: _cambiaModalita,
            ),
          IconButton(
            icon: const Icon(Icons.restart_alt),
            tooltip: 'Azzera',
            onPressed: _conteggio == 0 ? null : _reset,
          ),
        ],
      ),
      body: _modalitaScan ? _buildScan() : _buildManuale(),
    );
  }

  Widget _buildManuale() {
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Text(
              '$_conteggio',
              style: const TextStyle(fontSize: 96, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Row(
            children: [
              Expanded(
                child: _PulsanteGrosso(
                  icon: Icons.remove,
                  colore: const Color(0xFFF44336),
                  onTap: _conteggio == 0 ? null : _decrementa,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _PulsanteGrosso(
                  icon: Icons.add,
                  colore: const Color(0xFF4CAF50),
                  onTap: _incrementa,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildScan() {
    return Stack(
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
                messaggioErroreFotocamera(error.errorCode),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: Container(
            margin: const EdgeInsets.all(24),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$_conteggio',
              style: const TextStyle(
                  color: Colors.white, fontSize: 40, fontWeight: FontWeight.bold),
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
              'Inquadra i codici uno alla volta per contarli',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

/// Pulsante quadrato e grande (+1/-1), pensato per essere premuto facilmente
/// anche con i guanti o tenendo in mano delle scatole.
class _PulsanteGrosso extends StatelessWidget {
  final IconData icon;
  final Color colore;
  final VoidCallback? onTap;

  const _PulsanteGrosso({required this.icon, required this.colore, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final attivo = onTap != null;
    return AspectRatio(
      aspectRatio: 1,
      child: Material(
        color: attivo ? colore : colore.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Icon(icon, size: 64, color: Colors.white),
        ),
      ),
    );
  }
}
