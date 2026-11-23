import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:screen_brightness/screen_brightness.dart';
import '../../db/helpers.dart';
import '../../db/models.dart';
import '../../utils/tessere_tipi.dart';
import '../../utils/theme.dart';
import 'tessera_form.dart';

/// Lista delle tessere salvate. Il tocco apre la tessera a schermo intero per
/// mostrarla al lettore; da lì o dal menu della riga si modifica o si elimina.
/// Dati solo locali su questo device (nessuna sincronizzazione), ma inclusi nel
/// backup JSON.
class TessereScreen extends StatefulWidget {
  const TessereScreen({super.key});

  @override
  State<TessereScreen> createState() => _TessereScreenState();
}

class _TessereScreenState extends State<TessereScreen> {
  List<Tessera> _tessere = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _carica();
  }

  Future<void> _carica() async {
    final lista = await getTessere();
    if (mounted) {
      setState(() {
        _tessere = lista;
        _loading = false;
      });
    }
  }

  Future<void> _apriForm([Tessera? esistente]) async {
    final salvata = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => TesseraForm(esistente: esistente)),
    );
    if (salvata == true) _carica();
  }

  Future<void> _elimina(Tessera t) async {
    final conferma = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminare la tessera?'),
        content: Text('"${t.nome}" verrà eliminata da questo dispositivo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Elimina')),
        ],
      ),
    );
    if (conferma == true) {
      await deleteTessera(t.id);
      _carica();
    }
  }

  void _mostra(Tessera t) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MostraTesseraScreen(tessera: t)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tessere')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _apriForm(),
        backgroundColor: kPrimary,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _tessere.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'Nessuna tessera. Aggiungine una col +: scansiona il codice o digitalo.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: coloreTesto(context, 0.54)),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: _tessere.map((t) => Card(
                        child: ListTile(
                          leading: Icon(
                            t.tipo == kTipoQr ? Icons.qr_code_2 : Icons.view_week,
                            color: kPrimary,
                          ),
                          title: Text(t.nome),
                          subtitle: Text('${etichettaTipoTessera(t.tipo)} · ${t.valore}'),
                          onTap: () => _mostra(t),
                          trailing: PopupMenuButton<String>(
                            onSelected: (v) {
                              if (v == 'modifica') _apriForm(t);
                              if (v == 'elimina') _elimina(t);
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'modifica', child: Text('Modifica')),
                              PopupMenuItem(value: 'elimina', child: Text('Elimina')),
                            ],
                          ),
                        ),
                      )).toList(),
                ),
    );
  }
}

/// Mostra una tessera a schermo intero, su fondo bianco e con la luminosità al
/// massimo, perché la legga un lettore. La luminosità torna da sola a quella di
/// sistema quando si lascia la schermata.
class MostraTesseraScreen extends StatefulWidget {
  final Tessera tessera;

  const MostraTesseraScreen({super.key, required this.tessera});

  @override
  State<MostraTesseraScreen> createState() => _MostraTesseraScreenState();
}

class _MostraTesseraScreenState extends State<MostraTesseraScreen> {
  @override
  void initState() {
    super.initState();
    _massimaLuminosita();
  }

  Future<void> _massimaLuminosita() async {
    // Non supportata ovunque (es. web): se fallisce la tessera si mostra
    // comunque, solo senza alzare la luminosità.
    try {
      await ScreenBrightness().setApplicationScreenBrightness(1.0);
    } catch (_) {}
  }

  @override
  void dispose() {
    try {
      ScreenBrightness().resetApplicationScreenBrightness();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tessera;
    final isQr = t.tipo == kTipoQr;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(t.nome),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              BarcodeWidget(
                barcode: barcodeDaTipo(t.tipo),
                data: t.valore,
                width: isQr ? 260 : double.infinity,
                height: isQr ? 260 : 140,
                color: Colors.black,
                backgroundColor: Colors.white,
                // Niente testo sotto il codice qui: lo mostriamo noi più sotto
                // con un font più leggibile per chi lo deve digitare a mano.
                drawText: false,
                // Un codice non disegnabile (es. valore incompatibile col tipo,
                // possibile dopo un import) non fa saltare la schermata.
                errorBuilder: (context, error) => Text(
                  'Codice non valido per ${etichettaTipoTessera(t.tipo)}',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
              const SizedBox(height: 24),
              SelectableText(
                t.valore,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 20,
                  letterSpacing: 1.5,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
