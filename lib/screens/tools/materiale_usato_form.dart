import 'package:flutter/material.dart';
import '../../db/helpers.dart';
import '../../db/models.dart';
import '../../utils/theme.dart';
import '../../widgets/anag_pickers.dart';

/// Form per registrare un utilizzo di materiale da ripristinare.
/// Solo creazione: gli utilizzi non si modificano, si eliminano o si
/// segnano come ripristinati dalla lista (vedi MaterialiUsatiScreen).
class MaterialeUsatoForm extends StatefulWidget {
  const MaterialeUsatoForm({super.key});

  @override
  State<MaterialeUsatoForm> createState() => _MaterialeUsatoFormState();
}

class _MaterialeUsatoFormState extends State<MaterialeUsatoForm> {
  late TextEditingController _unitaCtrl;
  late TextEditingController _noteCtrl;

  String? _materialeId;
  int _quantita = 1;
  String? _posizione;
  List<Materiale> _materiali = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _unitaCtrl = TextEditingController();
    _noteCtrl = TextEditingController();
    _carica();
  }

  Future<void> _carica() async {
    final materiali = await getMateriali();
    if (mounted) setState(() { _materiali = materiali; _loading = false; });
  }

  Future<void> _salva() async {
    if (_materialeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleziona un materiale')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final mu = MaterialeUsato(
        id: newId(),
        materialeId: _materialeId!,
        quantita: _quantita,
        unita: _unitaCtrl.text.trim().isEmpty ? null : _unitaCtrl.text.trim(),
        posizione: _posizione,
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      );
      await saveMaterialeUsato(mu);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore durante il salvataggio: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _unitaCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Materiale usato'),
        actions: [
          if (_saving)
            const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
          else
            IconButton(icon: const Icon(Icons.check), onPressed: _salva),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Materiale *', style: TextStyle(color: kPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          MaterialePicker(
            materiali: _materiali,
            selectedId: _materialeId,
            onChanged: (v) async {
              // Se il materiale è stato creato al volo dal picker, ricarica
              // il catalogo per includerlo nella lista locale.
              if (v != null && _materiali.where((m) => m.id == v).isEmpty) {
                _materiali = await getMateriali();
              }
              setState(() => _materialeId = v);
            },
          ),
          const SizedBox(height: 20),

          const Text('Quantità', style: TextStyle(color: kPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: _quantita > 1 ? () => setState(() => _quantita--) : null,
            ),
            SizedBox(
              width: 48,
              child: Text('$_quantita', textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => setState(() => _quantita++),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _unitaCtrl,
                decoration: const InputDecoration(hintText: 'Unità (opzionale: flaconi, ml, confezioni...)'),
              ),
            ),
          ]),
          const SizedBox(height: 20),

          const Text('Posizione', style: TextStyle(color: kPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: posizioniMateriale.map((p) => ChoiceChip(
              label: Text(p),
              selected: _posizione == p,
              onSelected: (sel) => setState(() => _posizione = sel ? p : null),
            )).toList(),
          ),
          const SizedBox(height: 20),

          const Text('Note', style: TextStyle(color: kPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextFormField(
            controller: _noteCtrl,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'Note (opzionale)'),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
