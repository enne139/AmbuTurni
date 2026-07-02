import 'package:flutter/material.dart';
import '../../db/helpers.dart';
import '../../db/models.dart';
import '../../utils/format.dart';
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
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _quantitaCtrl;
  late TextEditingController _noteCtrl;
  late TextEditingController _dataCtrl;

  String? _materialeId;
  DateTime _data = DateTime.now();
  List<Materiale> _materiali = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _quantitaCtrl = TextEditingController();
    _noteCtrl = TextEditingController();
    _dataCtrl = TextEditingController(text: todayIso());
    _carica();
  }

  Future<void> _carica() async {
    final materiali = await getMateriali();
    if (mounted) setState(() { _materiali = materiali; _loading = false; });
  }

  Future<void> _apriDatePicker() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _data,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: kPrimary),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _data = picked;
        _dataCtrl.text = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }

  Future<void> _salva() async {
    if (_materialeId == null || _quantitaCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleziona un materiale e indica la quantità')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final mu = MaterialeUsato(
        id: newId(),
        materialeId: _materialeId!,
        quantita: _quantitaCtrl.text.trim(),
        data: _dataCtrl.text,
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
    _quantitaCtrl.dispose();
    _noteCtrl.dispose();
    _dataCtrl.dispose();
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
      body: Form(
        key: _formKey,
        child: ListView(
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

            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _quantitaCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Quantità * (es. 2, 500ml, 1 confezione)',
                    prefixIcon: Icon(Icons.numbers, size: 18),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 20),

            TextFormField(
              controller: _dataCtrl,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: 'Data',
                prefixIcon: Icon(Icons.calendar_today, size: 18),
              ),
              onTap: _apriDatePicker,
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
      ),
    );
  }
}
