import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../db/helpers.dart';
import '../../db/models.dart';
import '../../providers/app_provider.dart';
import '../../utils/format.dart';
import '../../utils/theme.dart';

/// Form per creare o modificare un turno.
/// Se [turnoId] è non-null, è in modalità modifica.
class TurnoForm extends StatefulWidget {
  final String? turnoId;
  const TurnoForm({super.key, this.turnoId});

  @override
  State<TurnoForm> createState() => _TurnoFormState();
}

class _TurnoFormState extends State<TurnoForm> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _oreCtrl;
  late TextEditingController _descrizioneCtrl;
  late TextEditingController _noteCtrl;
  late TextEditingController _dataCtrl;

  String? _associazioneId;
  String? _tipologiaId;
  List<String> _tipologieExtra = [];
  DateTime _data = DateTime.now();
  bool _loading = true;
  bool _saving = false;
  String? _existingId;

  // Equipaggio
  String? _eq1Autista, _eq1Cs, _eq1Terzo, _eq1Quarto, _eq1Central;
  String? _eq2Autista, _eq2Cs, _eq2Terzo, _eq2Quarto, _eq2Central;

  @override
  void initState() {
    super.initState();
    _oreCtrl = TextEditingController();
    _descrizioneCtrl = TextEditingController();
    _noteCtrl = TextEditingController();
    _dataCtrl = TextEditingController(text: todayIso());
    _caricaDati();
  }

  Future<void> _caricaDati() async {
    if (widget.turnoId != null) {
      final t = await getTurnoById(widget.turnoId!);
      if (t != null && mounted) {
        setState(() {
          _existingId = t.id;
          _associazioneId = t.associazioneId;
          _tipologiaId = t.tipologiaId;
          _tipologieExtra = List.from(t.tipologieExtra);
          _data = DateTime.tryParse(t.data) ?? DateTime.now();
          _dataCtrl.text = t.data;
          _oreCtrl.text = t.ore != null ? formatOre(t.ore) : '';
          _descrizioneCtrl.text = t.descrizione ?? '';
          _noteCtrl.text = t.note ?? '';
          _eq1Autista = t.eq1AutostaId;
          _eq1Cs = t.eq1CsId;
          _eq1Terzo = t.eq1TerzoId;
          _eq1Quarto = t.eq1QuartoId;
          _eq1Central = t.eq1CentralinistaId;
          _eq2Autista = t.eq2AutostaId;
          _eq2Cs = t.eq2CsId;
          _eq2Terzo = t.eq2TerzoId;
          _eq2Quarto = t.eq2QuartoId;
          _eq2Central = t.eq2CentralinistaId;
        });
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _salva() async {
    if (!_formKey.currentState!.validate()) return;
    if (_associazioneId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleziona un\'associazione')),
      );
      return;
    }
    setState(() => _saving = true);
    final turno = Turno(
      id: _existingId ?? newId(),
      associazioneId: _associazioneId,
      data: _dataCtrl.text,
      ore: parseOre(_oreCtrl.text),
      tipologiaId: _tipologiaId,
      tipologieExtra: _tipologieExtra,
      descrizione: _descrizioneCtrl.text.trim().isEmpty ? null : _descrizioneCtrl.text.trim(),
      note: _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      eq1AutostaId: _eq1Autista,
      eq1CsId: _eq1Cs,
      eq1TerzoId: _eq1Terzo,
      eq1QuartoId: _eq1Quarto,
      eq1CentralinistaId: _eq1Central,
      eq2AutostaId: _eq2Autista,
      eq2CsId: _eq2Cs,
      eq2TerzoId: _eq2Terzo,
      eq2QuartoId: _eq2Quarto,
      eq2CentralinistaId: _eq2Central,
    );
    await saveTurno(turno);
    if (mounted) Navigator.pop(context, true);
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
        title: Text(widget.turnoId == null ? 'Nuovo turno' : 'Modifica turno'),
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
            // --- Associazione ---
            _Sezione(titolo: 'Associazione *'),
            _DropdownAnag<Associazione>(
              valore: _associazioneId,
              items: anag.associazioni,
              label: (a) => a.nome,
              id: (a) => a.id,
              hint: 'Seleziona associazione',
              onChanged: (v) => setState(() => _associazioneId = v),
            ),
            const SizedBox(height: 20),

            // --- Data e Ore ---
            _Sezione(titolo: 'Data e ore'),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _dataCtrl,
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Data',
                    prefixIcon: Icon(Icons.calendar_today, size: 18),
                  ),
                  onTap: _apriDatePicker,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _oreCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Ore (es. 8h 30m)',
                    prefixIcon: Icon(Icons.schedule, size: 18),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 20),

            // --- Tipologia ---
            _Sezione(titolo: 'Tipologia'),
            _DropdownAnag<TipologiaTurno>(
              valore: _tipologiaId,
              items: anag.tipologieTurno,
              label: (t) => t.nome,
              id: (t) => t.id,
              hint: 'Seleziona tipologia',
              nullable: true,
              onChanged: (v) => setState(() => _tipologiaId = v),
            ),
            if (anag.tipologieTurno.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: anag.tipologieTurno
                    .where((t) => t.id != _tipologiaId)
                    .map((t) => FilterChip(
                          label: Text(t.nome),
                          selected: _tipologieExtra.contains(t.id),
                          onSelected: (sel) => setState(() {
                            if (sel) {
                              _tipologieExtra.add(t.id);
                            } else {
                              _tipologieExtra.remove(t.id);
                            }
                          }),
                        ))
                    .toList(),
              ),
            ],
            const SizedBox(height: 20),

            // --- Equipaggio 1ª parte ---
            _Sezione(titolo: 'Equipaggio — 1ª parte'),
            _EquipaggioGrid(
              persone: anag.persone,
              autista: _eq1Autista,
              cs: _eq1Cs,
              terzo: _eq1Terzo,
              quarto: _eq1Quarto,
              centralinista: _eq1Central,
              onAutista: (v) => setState(() => _eq1Autista = v),
              onCs: (v) => setState(() => _eq1Cs = v),
              onTerzo: (v) => setState(() => _eq1Terzo = v),
              onQuarto: (v) => setState(() => _eq1Quarto = v),
              onCentralinista: (v) => setState(() => _eq1Central = v),
            ),
            const SizedBox(height: 20),

            // --- Equipaggio 2ª parte ---
            _Sezione(titolo: 'Equipaggio — 2ª parte'),
            _EquipaggioGrid(
              persone: anag.persone,
              autista: _eq2Autista,
              cs: _eq2Cs,
              terzo: _eq2Terzo,
              quarto: _eq2Quarto,
              centralinista: _eq2Central,
              onAutista: (v) => setState(() => _eq2Autista = v),
              onCs: (v) => setState(() => _eq2Cs = v),
              onTerzo: (v) => setState(() => _eq2Terzo = v),
              onQuarto: (v) => setState(() => _eq2Quarto = v),
              onCentralinista: (v) => setState(() => _eq2Central = v),
            ),
            const SizedBox(height: 20),

            // --- Note e Descrizione ---
            _Sezione(titolo: 'Note'),
            TextFormField(
              controller: _descrizioneCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Descrizione'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _noteCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Note'),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
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
        _dataCtrl.text =
            '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }
}

// Widget helper per i titoli delle sezioni del form.
class _Sezione extends StatelessWidget {
  final String titolo;
  const _Sezione({required this.titolo});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(titolo, style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
      );
}

// Dropdown generico per le anagrafiche.
class _DropdownAnag<T> extends StatelessWidget {
  final String? valore;
  final List<T> items;
  final String Function(T) label;
  final String Function(T) id;
  final String hint;
  final bool nullable;
  final ValueChanged<String?> onChanged;

  const _DropdownAnag({
    super.key,
    this.valore,
    required this.items,
    required this.label,
    required this.id,
    required this.hint,
    this.nullable = false,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      value: valore,
      hint: Text(hint),
      decoration: const InputDecoration(),
      dropdownColor: kSurface,
      items: [
        if (nullable) const DropdownMenuItem(value: null, child: Text('—')),
        ...items.map((e) => DropdownMenuItem(value: id(e), child: Text(label(e)))),
      ],
      onChanged: onChanged,
    );
  }
}

// Grid a 2 colonne per i 5 campi equipaggio.
class _EquipaggioGrid extends StatelessWidget {
  final List<Persona> persone;
  final String? autista, cs, terzo, quarto, centralinista;
  final ValueChanged<String?> onAutista, onCs, onTerzo, onQuarto, onCentralinista;

  const _EquipaggioGrid({
    required this.persone,
    this.autista,
    this.cs,
    this.terzo,
    this.quarto,
    this.centralinista,
    required this.onAutista,
    required this.onCs,
    required this.onTerzo,
    required this.onQuarto,
    required this.onCentralinista,
  });

  Widget _campo(String label, String? val, ValueChanged<String?> onChange) =>
      _DropdownAnag<Persona>(
        valore: val,
        items: persone,
        label: (p) => p.nomeCompleto,
        id: (p) => p.id,
        hint: label,
        nullable: true,
        onChanged: onChange,
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(children: [
          Expanded(child: _campo('Autista', autista, onAutista)),
          const SizedBox(width: 10),
          Expanded(child: _campo('Capo Servizio', cs, onCs)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _campo('Terzo', terzo, onTerzo)),
          const SizedBox(width: 10),
          Expanded(child: _campo('Quarto', quarto, onQuarto)),
        ]),
        const SizedBox(height: 10),
        _campo('Centralinista', centralinista, onCentralinista),
      ],
    );
  }
}
