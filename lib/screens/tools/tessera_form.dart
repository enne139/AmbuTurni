import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../db/helpers.dart';
import '../../db/models.dart';
import '../../utils/platform_check.dart';
import '../../utils/tessere_tipi.dart';
import '../../utils/theme.dart';
import 'tessera_scan_screen.dart';

/// Form per creare o modificare una tessera. Con [esistente] non-null si è in
/// modifica: i campi partono pieni e il salvataggio aggiorna la riga.
class TesseraForm extends StatefulWidget {
  final Tessera? esistente;

  const TesseraForm({super.key, this.esistente});

  @override
  State<TesseraForm> createState() => _TesseraFormState();
}

class _TesseraFormState extends State<TesseraForm> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nomeCtrl;
  late TextEditingController _valoreCtrl;
  late TextEditingController _noteCtrl;
  late String _tipo;
  bool _saving = false;

  bool get _inModifica => widget.esistente != null;

  // La scansione esiste solo dove mobile_scanner ha un'implementazione:
  // Android/iOS e web. Sul desktop (Windows/Linux/macOS) il codice si digita.
  bool get _puoScansionare => isMobile || kIsWeb;

  @override
  void initState() {
    super.initState();
    final t = widget.esistente;
    _nomeCtrl = TextEditingController(text: t?.nome ?? '');
    _valoreCtrl = TextEditingController(text: t?.valore ?? '');
    _noteCtrl = TextEditingController(text: t?.note ?? '');
    _tipo = t?.tipo ?? kTipoCode128;
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _valoreCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _scansiona() async {
    final esito = await Navigator.of(context).push<ScansioneTessera>(
      MaterialPageRoute(builder: (_) => const TesseraScanScreen()),
    );
    if (esito == null || !mounted) return;
    setState(() {
      _valoreCtrl.text = esito.valore;
      // Se la simbologia letta è tra quelle disegnabili si adotta, altrimenti
      // si lascia il tipo scelto finora (default Code 128, che accetta tutto).
      if (esito.tipo != null) _tipo = esito.tipo!;
    });
  }

  Future<void> _salva() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final t = widget.esistente;
    final tessera = (t ?? Tessera(id: newId(), nome: '', valore: '', tipo: _tipo))
        .copyWith(
      nome: _nomeCtrl.text.trim(),
      valore: _valoreCtrl.text.trim(),
      tipo: _tipo,
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
    );
    await saveTessera(tessera);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_inModifica ? 'Modifica tessera' : 'Nuova tessera')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nomeCtrl,
              decoration: const InputDecoration(
                labelText: 'Nome',
                hintText: 'es. Tessera biblioteca',
              ),
              textCapitalization: TextCapitalization.sentences,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Dai un nome alla tessera' : null,
            ),
            const SizedBox(height: 16),
            if (_puoScansionare) ...[
              OutlinedButton.icon(
                onPressed: _saving ? null : _scansiona,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scansiona il codice'),
              ),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _valoreCtrl,
              decoration: const InputDecoration(
                labelText: 'Codice',
                hintText: 'il contenuto del codice',
              ),
              validator: (v) {
                final val = (v ?? '').trim();
                if (val.isEmpty) return 'Inserisci o scansiona il codice';
                if (!valoreValidoPerTipo(_tipo, val)) {
                  return '${etichettaTipoTessera(_tipo)} non va con questo codice';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _tipo,
              decoration: const InputDecoration(labelText: 'Tipo di codice'),
              items: [
                for (final t in tipiTessera)
                  DropdownMenuItem(value: t, child: Text(etichettaTipoTessera(t))),
              ],
              onChanged: (v) => setState(() => _tipo = v ?? _tipo),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Note (facoltative)',
              ),
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _salva,
              style: FilledButton.styleFrom(backgroundColor: kPrimary),
              child: Text(_saving ? 'Salvataggio…' : 'Salva'),
            ),
          ],
        ),
      ),
    );
  }
}
