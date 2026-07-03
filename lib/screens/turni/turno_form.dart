import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../db/helpers.dart';
import '../../db/models.dart';
import '../../providers/app_provider.dart';
import '../../utils/format.dart';
import '../../utils/theme.dart' show kPrimary, kSurface, kCardBorder, colorFromHex;
import '../../widgets/anag_pickers.dart';

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
  // Lista ordinata delle tipologie selezionate; multi-select con FilterChip.
  List<String> _tipologieSel = [];
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

  /// Carica i dati del turno esistente se siamo in modalità modifica.
  /// Il check `mounted` dopo l'await previene eccezioni se il widget
  /// viene smontato mentre la query è in corso (es. l'utente preme Back).
  Future<void> _caricaDati() async {
    if (widget.turnoId != null) {
      final t = await getTurnoById(widget.turnoId!);
      if (t != null && mounted) {
        setState(() {
          _existingId = t.id;
          _associazioneId = t.associazioneId;
          _tipologieSel = List.of(t.tipologie);
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

  /// Salva il turno nel DB usando l'id esistente (modifica) o un UUID nuovo (create).
  /// L'associazione è l'unico campo obbligatorio: senza di essa la numerazione
  /// progressiva e il filtro lista non funzionerebbero correttamente.
  Future<void> _salva() async {
    if (!_formKey.currentState!.validate()) return;
    if (_associazioneId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleziona un\'associazione')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final turno = Turno(
        id: _existingId ?? newId(),
        associazioneId: _associazioneId,
        data: _dataCtrl.text,
        ore: parseOre(_oreCtrl.text),
        tipologie: List.of(_tipologieSel),
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
                  // Senza validator un testo non parsabile diventava
                  // silenziosamente ore = null: il turno si salvava ma le
                  // ore digitate sparivano senza alcun avviso.
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

            // --- Tipologia ---
            // Chip multi-select: tocca per selezionare/deselezionare.
            _Sezione(titolo: 'Tipologia'),
            if (anag.tipologieTurno.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: anag.tipologieTurno.map((t) {
                  final accent = colorFromHex(t.colore) ?? kPrimary;
                  final sel = _tipologieSel.contains(t.id);
                  return FilterChip(
                    label: Text(t.nome),
                    selected: sel,
                    selectedColor: accent.withValues(alpha: 0.25),
                    checkmarkColor: accent,
                    labelStyle: TextStyle(color: sel ? accent : Colors.white70),
                    onSelected: (v) => setState(() {
                      if (v) {
                        _tipologieSel.add(t.id);
                      } else {
                        _tipologieSel.remove(t.id);
                      }
                    }),
                  );
                }).toList(),
              )
            else
              const Text('Nessuna tipologia configurata',
                  style: TextStyle(color: Colors.white38, fontSize: 13)),
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
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Equipaggio — 2ª parte',
                      style: TextStyle(color: kPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
                  TextButton.icon(
                    icon: const Icon(Icons.content_copy, size: 14),
                    label: const Text('Copia 1ª parte', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: kPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => setState(() {
                      _eq2Autista = _eq1Autista;
                      _eq2Cs = _eq1Cs;
                      _eq2Terzo = _eq1Terzo;
                      _eq2Quarto = _eq1Quarto;
                      _eq2Central = _eq1Central;
                    }),
                  ),
                ],
              ),
            ),
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

/// Sezione equipaggio: ogni ruolo ha la propria riga con label fissa a sinistra
/// (sempre visibile anche dopo la selezione) e dropdown a destra.
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

  @override
  Widget build(BuildContext context) {
    final ruoli = [
      (icona: Icons.drive_eta, label: 'Autista', val: autista, onChange: onAutista),
      (icona: Icons.medical_services, label: 'Capo Servizio', val: cs, onChange: onCs),
      (icona: Icons.person, label: 'Terzo', val: terzo, onChange: onTerzo),
      (icona: Icons.person_outline, label: 'Quarto', val: quarto, onChange: onQuarto),
      (icona: Icons.headset_mic, label: 'Centralinista', val: centralinista, onChange: onCentralinista),
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
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(
                  children: [
                    Icon(r.icona, size: 16, color: Colors.white38),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 110,
                      child: Text(
                        r.label,
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                    Expanded(
                      child: PersonaPicker(
                        persone: persone,
                        selectedId: r.val,
                        onChanged: r.onChange,
                      ),
                    ),
                  ],
                ),
              ),
              if (i < ruoli.length - 1) const Divider(height: 1, indent: 12, endIndent: 12),
            ],
          );
        }).toList(),
      ),
    );
  }
}
