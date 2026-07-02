// Picker con ricerca inline (combobox) per persone e ospedali.
// Il pulsante + è nel campo stesso (suffixIcon) — sempre visibile, anche quando la lista
// è vuota. Evita conflitti di gesture con l'overlay di RawAutocomplete.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../db/helpers.dart';
import '../db/models.dart';
import '../providers/app_provider.dart';
import '../utils/theme.dart';

// ---------------------------------------------------------------------------
// PersonaPicker
// ---------------------------------------------------------------------------

/// Combobox con ricerca per selezionare una persona dall'anagrafica.
/// Il suffixIcon alterna tra + (crea nuova voce) e × (deseleziona),
/// così la creazione è sempre accessibile anche quando la lista è vuota.
class PersonaPicker extends StatefulWidget {
  final List<Persona> persone;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  const PersonaPicker({
    super.key,
    required this.persone,
    this.selectedId,
    required this.onChanged,
  });

  @override
  State<PersonaPicker> createState() => _PersonaPickerState();
}

class _PersonaPickerState extends State<PersonaPicker> {
  late TextEditingController _ctrl;
  late FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _nomeOf(widget.selectedId));
    _focus = FocusNode();
  }

  /// Aggiorna il testo quando il parent cambia selectedId (es. dopo creazione inline).
  /// addPostFrameCallback evita modifiche al controller durante il build.
  @override
  void didUpdateWidget(PersonaPicker old) {
    super.didUpdateWidget(old);
    if (old.selectedId != widget.selectedId) {
      final name = _nomeOf(widget.selectedId);
      if (_ctrl.text != name) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _ctrl.text = name;
        });
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _nomeOf(String? id) {
    if (id == null) return '';
    return widget.persone.where((p) => p.id == id).firstOrNull?.nomeCompleto ?? '';
  }

  /// Apre il dialog di creazione, salva con UUID pre-generato e auto-seleziona.
  Future<void> _creaPersona() async {
    _focus.unfocus();
    final cognCtrl = TextEditingController();
    final nomeCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuova persona'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: cognCtrl,
            decoration: const InputDecoration(labelText: 'Cognome'),
            textCapitalization: TextCapitalization.words,
            autofocus: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: nomeCtrl,
            decoration: const InputDecoration(labelText: 'Nome'),
            textCapitalization: TextCapitalization.words,
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salva')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final cognome = cognCtrl.text.trim();
    final nome = nomeCtrl.text.trim();
    if (cognome.isEmpty || nome.isEmpty) return;
    // Salva senza passare l'id: savePersona con id esegue un UPDATE (aggiorna una riga
    // esistente), ma qui la riga non esiste ancora → zero righe aggiornate, niente salvato.
    // L'id restituito permette l'auto-selezione diretta: ritrovare la voce per
    // nome nella lista ricaricata selezionerebbe quella sbagliata con gli omonimi.
    final id = await savePersona(cognome, nome);
    if (!mounted) return;
    await context.read<AnagraficheProvider>().carica();
    if (!mounted) return;
    _ctrl.text = '$cognome $nome';
    widget.onChanged(id);
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<Persona>(
      textEditingController: _ctrl,
      focusNode: _focus,
      displayStringForOption: (p) => p.nomeCompleto,
      optionsBuilder: (tev) {
        final q = tev.text.toLowerCase();
        return q.isEmpty
            ? widget.persone
            : widget.persone.where((p) => p.nomeCompleto.toLowerCase().contains(q));
      },
      onSelected: (p) => widget.onChanged(p.id),
      fieldViewBuilder: (ctx, ctrl, focus, _) => TextField(
        controller: ctrl,
        focusNode: focus,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: InputDecoration(
          isDense: true,
          hintText: '—',
          hintStyle: const TextStyle(color: Colors.white38),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          // × deseleziona; + apre il dialog di creazione (sempre visibile, anche lista vuota)
          suffixIcon: widget.selectedId != null
              ? InkWell(
                  onTap: () {
                    ctrl.clear();
                    focus.unfocus();
                    widget.onChanged(null);
                  },
                  child: const Icon(Icons.clear, size: 14, color: Colors.white38),
                )
              : InkWell(
                  onTap: _creaPersona,
                  child: const Icon(Icons.add, size: 14, color: kPrimary),
                ),
        ),
      ),
      optionsViewBuilder: (ctx, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          color: kSurface,
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220, maxWidth: 260),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: options.map(
                (p) => InkWell(
                  onTap: () => onSelected(p),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Text(p.nomeCompleto, style: const TextStyle(fontSize: 13)),
                  ),
                ),
              ).toList(),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// OspedalePicker
// ---------------------------------------------------------------------------

/// Combobox con ricerca per selezionare un ospedale.
/// Stesso pattern di PersonaPicker: + nel suffixIcon per creare, × per deselezionare.
class OspedalePicker extends StatefulWidget {
  final List<Ospedale> ospedali;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  const OspedalePicker({
    super.key,
    required this.ospedali,
    this.selectedId,
    required this.onChanged,
  });

  @override
  State<OspedalePicker> createState() => _OspedalePickerState();
}

class _OspedalePickerState extends State<OspedalePicker> {
  late TextEditingController _ctrl;
  late FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _labelOf(widget.selectedId));
    _focus = FocusNode();
  }

  @override
  void didUpdateWidget(OspedalePicker old) {
    super.didUpdateWidget(old);
    if (old.selectedId != widget.selectedId) {
      final label = _labelOf(widget.selectedId);
      if (_ctrl.text != label) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _ctrl.text = label;
        });
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  /// La label include la città tra parentesi per disambiguare ospedali con lo stesso nome.
  String _labelOf(String? id) {
    if (id == null) return '';
    return widget.ospedali.where((o) => o.id == id).firstOrNull?.label ?? '';
  }

  Future<void> _creaOspedale() async {
    _focus.unfocus();
    final nomeCtrl = TextEditingController();
    final cittaCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuovo ospedale'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: nomeCtrl,
            decoration: const InputDecoration(labelText: 'Nome'),
            textCapitalization: TextCapitalization.words,
            autofocus: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: cittaCtrl,
            decoration: const InputDecoration(labelText: 'Città (opzionale)'),
            textCapitalization: TextCapitalization.words,
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salva')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final nome = nomeCtrl.text.trim();
    if (nome.isEmpty) return;
    final citta = cittaCtrl.text.trim().isEmpty ? null : cittaCtrl.text.trim();
    // Salva senza id per fare INSERT (stessa ragione di _creaPersona);
    // l'id restituito evita la ricerca per nome (ambigua con gli omonimi).
    final id = await saveOspedale(nome, citta);
    if (!mounted) return;
    await context.read<AnagraficheProvider>().carica();
    if (!mounted) return;
    // Stessa logica di Ospedale.label: nome + città se presente.
    _ctrl.text = citta != null ? '$nome - $citta' : nome;
    widget.onChanged(id);
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<Ospedale>(
      textEditingController: _ctrl,
      focusNode: _focus,
      displayStringForOption: (o) => o.label,
      optionsBuilder: (tev) {
        final q = tev.text.toLowerCase();
        return q.isEmpty
            ? widget.ospedali
            : widget.ospedali.where((o) =>
                o.nome.toLowerCase().contains(q) ||
                (o.citta?.toLowerCase().contains(q) ?? false));
      },
      onSelected: (o) => widget.onChanged(o.id),
      fieldViewBuilder: (ctx, ctrl, focus, _) => TextField(
        controller: ctrl,
        focusNode: focus,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Cerca ospedale...',
          hintStyle: const TextStyle(color: Colors.white38),
          prefixIcon: const Icon(Icons.search, size: 18, color: Colors.white38),
          suffixIcon: widget.selectedId != null
              ? InkWell(
                  onTap: () {
                    ctrl.clear();
                    focus.unfocus();
                    widget.onChanged(null);
                  },
                  child: const Icon(Icons.clear, size: 16, color: Colors.white38),
                )
              : InkWell(
                  onTap: _creaOspedale,
                  child: const Icon(Icons.add, size: 16, color: kPrimary),
                ),
        ),
      ),
      optionsViewBuilder: (ctx, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          color: kSurface,
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 250),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: options.map(
                (o) => InkWell(
                  onTap: () => onSelected(o),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(o.nome, style: const TextStyle(fontSize: 14)),
                        if (o.citta != null)
                          Text(o.citta!, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                      ],
                    ),
                  ),
                ),
              ).toList(),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// MaterialePicker
// ---------------------------------------------------------------------------

/// Combobox con ricerca per selezionare un materiale dal catalogo (Tools ->
/// Materiali usati). Stesso pattern di OspedalePicker ma con solo il nome.
class MaterialePicker extends StatefulWidget {
  final List<Materiale> materiali;
  final String? selectedId;
  final ValueChanged<String?> onChanged;

  const MaterialePicker({
    super.key,
    required this.materiali,
    this.selectedId,
    required this.onChanged,
  });

  @override
  State<MaterialePicker> createState() => _MaterialePickerState();
}

class _MaterialePickerState extends State<MaterialePicker> {
  late TextEditingController _ctrl;
  late FocusNode _focus;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _nomeOf(widget.selectedId));
    _focus = FocusNode();
  }

  @override
  void didUpdateWidget(MaterialePicker old) {
    super.didUpdateWidget(old);
    if (old.selectedId != widget.selectedId) {
      final name = _nomeOf(widget.selectedId);
      if (_ctrl.text != name) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _ctrl.text = name;
        });
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  String _nomeOf(String? id) {
    if (id == null) return '';
    return widget.materiali.where((m) => m.id == id).firstOrNull?.nome ?? '';
  }

  Future<void> _creaMateriale() async {
    _focus.unfocus();
    final nomeCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuovo materiale'),
        content: TextField(
          controller: nomeCtrl,
          decoration: const InputDecoration(labelText: 'Nome'),
          textCapitalization: TextCapitalization.sentences,
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salva')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final nome = nomeCtrl.text.trim();
    if (nome.isEmpty) return;
    // L'id restituito evita di ricaricare il catalogo solo per ritrovare
    // la voce appena creata (il parent lo ricarica già in onChanged).
    final id = await saveMateriale(nome);
    if (!mounted) return;
    _ctrl.text = nome;
    widget.onChanged(id);
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<Materiale>(
      textEditingController: _ctrl,
      focusNode: _focus,
      displayStringForOption: (m) => m.nome,
      optionsBuilder: (tev) {
        final q = tev.text.toLowerCase();
        return q.isEmpty
            ? widget.materiali
            : widget.materiali.where((m) => m.nome.toLowerCase().contains(q));
      },
      onSelected: (m) => widget.onChanged(m.id),
      fieldViewBuilder: (ctx, ctrl, focus, _) => TextField(
        controller: ctrl,
        focusNode: focus,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Cerca materiale...',
          hintStyle: const TextStyle(color: Colors.white38),
          prefixIcon: const Icon(Icons.search, size: 18, color: Colors.white38),
          suffixIcon: widget.selectedId != null
              ? InkWell(
                  onTap: () {
                    ctrl.clear();
                    focus.unfocus();
                    widget.onChanged(null);
                  },
                  child: const Icon(Icons.clear, size: 16, color: Colors.white38),
                )
              : InkWell(
                  onTap: _creaMateriale,
                  child: const Icon(Icons.add, size: 16, color: kPrimary),
                ),
        ),
      ),
      optionsViewBuilder: (ctx, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          color: kSurface,
          elevation: 8,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              children: options.map(
                (m) => InkWell(
                  onTap: () => onSelected(m),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Text(m.nome, style: const TextStyle(fontSize: 14)),
                  ),
                ),
              ).toList(),
            ),
          ),
        ),
      ),
    );
  }
}
