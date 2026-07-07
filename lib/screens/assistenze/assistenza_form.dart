import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../db/helpers.dart';
import '../../db/models.dart';
import '../../providers/app_provider.dart';
import '../../utils/format.dart';
import '../../utils/theme.dart';
import '../../widgets/anag_pickers.dart';

/// Form per creare o modificare un'assistenza.
class AssistenzaForm extends StatefulWidget {
  final String? assistenzaId;
  /// Data ISO precompilata per una nuova assistenza (come in TurnoForm:
  /// creazione dal giorno selezionato della vista calendario).
  final String? dataIniziale;
  const AssistenzaForm({super.key, this.assistenzaId, this.dataIniziale});

  @override
  State<AssistenzaForm> createState() => _AssistenzaFormState();
}

class _AssistenzaFormState extends State<AssistenzaForm> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _oreCtrl;
  late TextEditingController _descrizioneCtrl;
  late TextEditingController _noteCtrl;
  late TextEditingController _dataCtrl;

  String? _associazioneId;
  DateTime _data = DateTime.now();
  bool _loading = true;
  bool _saving = false;
  String? _existingId;

  String? _eq1Autista, _eq1Cs, _eq1Terzo, _eq1Quarto, _eq1Central;
  String? _eq2Autista, _eq2Cs, _eq2Terzo, _eq2Quarto, _eq2Central;

  @override
  void initState() {
    super.initState();
    _oreCtrl = TextEditingController();
    _descrizioneCtrl = TextEditingController();
    _noteCtrl = TextEditingController();
    // dataIniziale vince su oggi solo in creazione; in modifica _caricaDati
    // sovrascrive comunque con la data dell'assistenza.
    final dataIso = widget.dataIniziale ?? todayIso();
    _data = DateTime.tryParse(dataIso) ?? DateTime.now();
    _dataCtrl = TextEditingController(text: dataIso);
    _caricaDati();
  }

  /// Carica i dati dell'assistenza se siamo in modalità modifica.
  /// `mounted` check dopo l'await: se l'utente preme Back prima che la query finisca
  /// il widget non è più nell'albero e setState lancerebbe un'eccezione.
  Future<void> _caricaDati() async {
    if (widget.assistenzaId != null) {
      final a = await getAssistenzaById(widget.assistenzaId!);
      if (a != null && mounted) {
        setState(() {
          _existingId = a.id;
          _associazioneId = a.associazioneId;
          _data = DateTime.tryParse(a.data) ?? DateTime.now();
          _dataCtrl.text = a.data;
          _oreCtrl.text = a.ore != null ? formatOre(a.ore) : '';
          _descrizioneCtrl.text = a.descrizione ?? '';
          _noteCtrl.text = a.note ?? '';
          _eq1Autista = a.eq1AutistaId;
          _eq1Cs = a.eq1CsId;
          _eq1Terzo = a.eq1TerzoId;
          _eq1Quarto = a.eq1QuartoId;
          _eq1Central = a.eq1CentralinistaId;
          _eq2Autista = a.eq2AutistaId;
          _eq2Cs = a.eq2CsId;
          _eq2Terzo = a.eq2TerzoId;
          _eq2Quarto = a.eq2QuartoId;
          _eq2Central = a.eq2CentralinistaId;
        });
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _scegliData() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _data,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: kPrimary)),
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
    // validate() mancava: il Form c'era ma nessun validator veniva eseguito
    // (il form turno lo chiama già da sempre).
    if (!_formKey.currentState!.validate()) return;
    if (_associazioneId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Seleziona un\'associazione')));
      return;
    }
    setState(() => _saving = true);
    try {
      final a = Assistenza(
        id: _existingId ?? newId(),
        associazioneId: _associazioneId,
        data: _dataCtrl.text,
        ore: parseOre(_oreCtrl.text),
        descrizione: _descrizioneCtrl.text.trim().isEmpty ? null : _descrizioneCtrl.text.trim(),
        note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        eq1AutistaId: _eq1Autista,
        eq1CsId: _eq1Cs,
        eq1TerzoId: _eq1Terzo,
        eq1QuartoId: _eq1Quarto,
        eq1CentralinistaId: _eq1Central,
        eq2AutistaId: _eq2Autista,
        eq2CsId: _eq2Cs,
        eq2TerzoId: _eq2Terzo,
        eq2QuartoId: _eq2Quarto,
        eq2CentralinistaId: _eq2Central,
      );
      await saveAssistenza(a);
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
    _oreCtrl.dispose();
    _descrizioneCtrl.dispose();
    _noteCtrl.dispose();
    _dataCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final anag = context.watch<AnagraficheProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.assistenzaId == null ? 'Nuova assistenza' : 'Modifica assistenza'),
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
            _label('Associazione *'),
            DropdownButtonFormField<String>(
              value: _associazioneId,
              hint: const Text('Seleziona associazione'),
              dropdownColor: kSurface,
              decoration: const InputDecoration(),
              items: anag.associazioni.map((a) => DropdownMenuItem(value: a.id, child: Text(a.nome))).toList(),
              onChanged: (v) => setState(() => _associazioneId = v),
            ),
            const SizedBox(height: 20),
            _label('Data e ore'),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _dataCtrl,
                  readOnly: true,
                  decoration: const InputDecoration(labelText: 'Data', prefixIcon: Icon(Icons.calendar_today, size: 18)),
                  onTap: _scegliData,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _oreCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Ore', prefixIcon: Icon(Icons.schedule, size: 18)),
                  // Stesso validator del form turno: un testo non parsabile
                  // diventava silenziosamente ore = null (ore perse al salvataggio).
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    return parseOre(v) == null
                        ? 'Formato non valido (es. 8, 8,5 o 8h 30m)'
                        : null;
                  },
                ),
              ),
            ]),
            const SizedBox(height: 20),
            _label('Equipaggio — 1ª parte'),
            _eqGrid(anag.persone, _eq1Autista, _eq1Cs, _eq1Terzo, _eq1Quarto, _eq1Central, true),
            const SizedBox(height: 20),
            _label('Equipaggio — 2ª parte'),
            _eqGrid(anag.persone, _eq2Autista, _eq2Cs, _eq2Terzo, _eq2Quarto, _eq2Central, false),
            const SizedBox(height: 20),
            _label('Note'),
            TextFormField(controller: _descrizioneCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Descrizione')),
            const SizedBox(height: 12),
            TextFormField(controller: _noteCtrl, maxLines: 3, decoration: const InputDecoration(labelText: 'Note')),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
      );

  /// Equipaggio con label fissa sempre visibile a sinistra del combobox.
  Widget _eqGrid(List<Persona> p, String? aut, String? cs, String? terzo, String? quarto, String? central, bool prima) {
    final ruoli = [
      (icona: Icons.drive_eta, label: 'Autista', val: aut, onChange: (String? v) => setState(() => prima ? _eq1Autista = v : _eq2Autista = v)),
      (icona: Icons.medical_services, label: 'Capo Servizio', val: cs, onChange: (String? v) => setState(() => prima ? _eq1Cs = v : _eq2Cs = v)),
      (icona: Icons.person, label: 'Terzo', val: terzo, onChange: (String? v) => setState(() => prima ? _eq1Terzo = v : _eq2Terzo = v)),
      (icona: Icons.person_outline, label: 'Quarto', val: quarto, onChange: (String? v) => setState(() => prima ? _eq1Quarto = v : _eq2Quarto = v)),
      (icona: Icons.headset_mic, label: 'Centralinista', val: central, onChange: (String? v) => setState(() => prima ? _eq1Central = v : _eq2Central = v)),
    ];
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: kCardBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: ruoli.asMap().entries.map((entry) {
          final i = entry.key;
          final r = entry.value;
          return Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Row(children: [
                Icon(r.icona, size: 16, color: Colors.white38),
                const SizedBox(width: 8),
                SizedBox(
                  width: 110,
                  child: Text(r.label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ),
                Expanded(
                  child: PersonaPicker(
                    persone: p,
                    selectedId: r.val,
                    onChanged: r.onChange,
                  ),
                ),
              ]),
            ),
            if (i < ruoli.length - 1) const Divider(height: 1, indent: 12, endIndent: 12),
          ]);
        }).toList(),
      ),
    );
  }
}
