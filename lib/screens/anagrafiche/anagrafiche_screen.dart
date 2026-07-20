import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../db/backup.dart';
import '../../db/helpers.dart';
import '../../db/models.dart';
import '../../providers/app_provider.dart';
import '../../utils/geocoding_api.dart';
import '../../utils/theme.dart';
import 'turni_filtrati_screen.dart';

/// Schermata Anagrafiche: CRUD di associazioni, persone, ospedali, tipologie
/// turno. Spostata da Impostazioni (dove viveva insieme a backup/tool/backend)
/// e resa raggiungibile dall'icona nell'AppBar della tab Attività: è lì che
/// si crea al volo una persona/ospedale/associazione nuova mentre si compila
/// un turno, non in Impostazioni. Ogni sezione è collassata di default e ha
/// una barra di ricerca interna.
class AnagraficheScreen extends StatelessWidget {
  const AnagraficheScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Anagrafiche')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: const [
          _SezioneAssociazioni(),
          Divider(height: 1),
          _SezionePersone(),
          Divider(height: 1),
          _SezioneOspedali(),
          Divider(height: 1),
          _SezioneTipologie(),
          SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Associazioni
// ---------------------------------------------------------------------------

class _SezioneAssociazioni extends StatelessWidget {
  const _SezioneAssociazioni();

  @override
  Widget build(BuildContext context) {
    final anag = context.watch<AnagraficheProvider>();
    return _SezioneAnag<Associazione>(
      titolo: 'Associazioni',
      icon: Icons.business,
      items: anag.associazioni,
      labelOf: (a) => a.nome,
      sublabelOf: (_) => null,
      colorOf: (a) => colorFromHex(a.colore),
      onAdd: () => _dialogNomeEColore(context, 'Nuova associazione', (nome, colore) async {
        await saveAssociazione(nome, colore: colore);
        if (context.mounted) context.read<AnagraficheProvider>().carica();
      }),
      onEdit: (a) => _dialogNomeEColore(context, 'Modifica associazione', (nome, colore) async {
        await saveAssociazione(nome, id: a.id, colore: colore);
        if (context.mounted) context.read<AnagraficheProvider>().carica();
      }, iniziale: a.nome, coloreIniziale: a.colore),
      onDelete: (a) async {
        await deleteAssociazione(a.id);
        if (context.mounted) context.read<AnagraficheProvider>().carica();
      },
      messaggioVincolo: 'è usata da turni o assistenze esistenti.',
    );
  }
}

// ---------------------------------------------------------------------------
// Persone
// ---------------------------------------------------------------------------

class _SezionePersone extends StatelessWidget {
  const _SezionePersone();

  @override
  Widget build(BuildContext context) {
    final anag = context.watch<AnagraficheProvider>();
    return _SezioneAnag<Persona>(
      titolo: 'Persone',
      icon: Icons.people,
      items: anag.persone,
      labelOf: (p) => p.nomeCompleto,
      sublabelOf: (_) => null,
      onAdd: () => _dialogPersona(context, null),
      onEdit: (p) => _dialogPersona(context, p),
      onView: (p) async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => TurniPersonaScreen(persona: p)));
      },
      onDelete: (p) async {
        await deletePersona(p.id);
        if (context.mounted) context.read<AnagraficheProvider>().carica();
      },
      messaggioVincolo: 'fa parte dell\'equipaggio di turni o assistenze esistenti.',
    );
  }

  Future<void> _dialogPersona(BuildContext context, Persona? p) async {
    final cognCtrl = TextEditingController(text: p?.cognome ?? '');
    final nomeCtrl = TextEditingController(text: p?.nome ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p == null ? 'Nuova persona' : 'Modifica persona'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: cognCtrl, decoration: const InputDecoration(labelText: 'Cognome'), textCapitalization: TextCapitalization.words),
          const SizedBox(height: 12),
          TextField(controller: nomeCtrl, decoration: const InputDecoration(labelText: 'Nome'), textCapitalization: TextCapitalization.words),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salva')),
        ],
      ),
    );
    if (ok == true) {
      final c = cognCtrl.text.trim();
      final n = nomeCtrl.text.trim();
      if (c.isNotEmpty && n.isNotEmpty) {
        await savePersona(c, n, id: p?.id);
        if (context.mounted) context.read<AnagraficheProvider>().carica();
      }
    }
  }
}

// ---------------------------------------------------------------------------
// Ospedali
// ---------------------------------------------------------------------------

class _SezioneOspedali extends StatelessWidget {
  const _SezioneOspedali();

  @override
  Widget build(BuildContext context) {
    final anag = context.watch<AnagraficheProvider>();
    return _SezioneAnag<Ospedale>(
      titolo: 'Ospedali',
      icon: Icons.local_hospital,
      items: anag.ospedali,
      labelOf: (o) => o.nome,
      sublabelOf: (o) => o.citta,
      onAdd: () => _dialogOspedale(context, null),
      onEdit: (o) => _dialogOspedale(context, o),
      onView: (o) async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => TurniOspedaleScreen(ospedale: o)));
      },
      onDelete: (o) async {
        await deleteOspedale(o.id);
        if (context.mounted) context.read<AnagraficheProvider>().carica();
      },
      messaggioVincolo: 'è usato da servizi di turni esistenti.',
      onExport: () => _export(context),
      onImport: () => _import(context),
    );
  }

  /// Esporta nome/via/città/coordinate di tutti gli ospedali in un file JSON
  /// portabile (utils/backup.dart: exportOspedali) — non il backup completo,
  /// solo l'anagrafica ospedali, per condividerla o scambiarla facilmente.
  Future<void> _export(BuildContext context) async {
    try {
      final path = await exportOspedali();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(path != null ? 'Ospedali esportati.' : 'Export annullato.'),
        ));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Errore export: $e')));
      }
    }
  }

  /// Importa ospedali da un file JSON (lo stesso prodotto da _export, o un
  /// backup completo). A differenza dell'import di backup NON è distruttivo:
  /// aggiorna gli ospedali già in anagrafica (per nome) e aggiunge i nuovi,
  /// senza toccare il resto dei dati né gli ospedali non presenti nel file.
  Future<void> _import(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Importa ospedali'),
        content: const Text(
          'Aggiunge o aggiorna gli ospedali del file scelto (in base al nome). '
          'Il resto dei dati e gli ospedali non presenti nel file restano invariati.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Importa')),
        ],
      ),
    );
    if (ok != true) return;
    final msg = await importOspedali();
    if (context.mounted) {
      context.read<AnagraficheProvider>().carica();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _dialogOspedale(BuildContext context, Ospedale? o) async {
    final nomeCtrl = TextEditingController(text: o?.nome ?? '');
    final cittaCtrl = TextEditingController(text: o?.citta ?? '');
    final viaCtrl = TextEditingController(text: o?.via ?? '');
    // Campi SEMPRE vuoti all'apertura, anche se l'ospedale ha già delle
    // coordinate/regione: precompilarli col valore esistente li avrebbe resi
    // "campi manuali" già valorizzati, e modificare solo via/città lasciandoli
    // intatti si sarebbe visto come "inseriti a mano" invece che "campi
    // vuoti" — il geocoding automatico non sarebbe mai ripartito dopo la
    // prima volta. Il valore attuale resta visibile come hintText.
    final latCtrl = TextEditingController();
    final lngCtrl = TextEditingController();
    final regioneCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(o == null ? 'Nuovo ospedale' : 'Modifica ospedale'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nomeCtrl, decoration: const InputDecoration(labelText: 'Nome'), textCapitalization: TextCapitalization.words),
            const SizedBox(height: 12),
            TextField(controller: viaCtrl, decoration: const InputDecoration(labelText: 'Via (opzionale)'), textCapitalization: TextCapitalization.sentences),
            const SizedBox(height: 12),
            TextField(controller: cittaCtrl, decoration: const InputDecoration(labelText: 'Città (opzionale)'), textCapitalization: TextCapitalization.words),
            const SizedBox(height: 12),
            TextField(
              controller: regioneCtrl,
              decoration: InputDecoration(labelText: 'Regione (opzionale)', hintText: o?.regione),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: latCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: InputDecoration(labelText: 'Latitudine', hintText: o?.lat?.toString()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: lngCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: InputDecoration(labelText: 'Longitudine', hintText: o?.lng?.toString()),
                ),
              ),
            ]),
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Lascia vuoti per calcolarli automaticamente dall\'indirizzo.',
                  style: TextStyle(fontSize: 12, color: Colors.white54),
                ),
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salva')),
        ],
      ),
    );
    if (ok == true) {
      final n = nomeCtrl.text.trim();
      if (n.isNotEmpty) {
        final via = viaCtrl.text.trim();
        final citta = cittaCtrl.text.trim().isEmpty ? null : cittaCtrl.text.trim();
        final id = await saveOspedale(n, citta, id: o?.id, via: via.isEmpty ? null : via);
        if (!context.mounted) return;
        context.read<AnagraficheProvider>().carica();
        // Lat/lng/regione inseriti a mano hanno priorità sul geocoding
        // automatico, che viene saltato del tutto se anche uno solo dei tre
        // è stato compilato (coordinate accettano sia punto che virgola come
        // separatore decimale).
        final latManuale = double.tryParse(latCtrl.text.trim().replaceAll(',', '.'));
        final lngManuale = double.tryParse(lngCtrl.text.trim().replaceAll(',', '.'));
        final regioneManuale = regioneCtrl.text.trim().isEmpty ? null : regioneCtrl.text.trim();
        if (latManuale != null || lngManuale != null || regioneManuale != null) {
          await aggiornaGeocodingOspedale(id, lat: latManuale, lng: lngManuale, regione: regioneManuale);
          if (context.mounted) context.read<AnagraficheProvider>().carica();
        } else if (via.isNotEmpty && (o == null || via != (o.via ?? '') || citta != o.citta)) {
          // Geocoding in sottofondo, solo se l'indirizzo è nuovo o cambiato:
          // non blocca il salvataggio (offline-first) e non ripete la
          // chiamata a Nominatim a ogni modifica banale (es. solo il nome).
          _geocodificaInSottofondo(context, id, via, citta);
        }
      }
    }
  }

  /// Risolve via+città in coordinate (e regione, se disponibile) e le salva
  /// se trovate; nessun feedback d'errore in UI (è un arricchimento
  /// best-effort per la mappa/il raggruppamento del tool Lista ospedali, non
  /// un'operazione che l'utente ha chiesto esplicitamente né di cui deve
  /// accorgersi se il device è offline).
  Future<void> _geocodificaInSottofondo(
      BuildContext context, String id, String via, String? citta) async {
    final indirizzo = [via, citta].whereType<String>().where((s) => s.isNotEmpty).join(', ');
    final coord = await GeocodingApi().geocodifica(indirizzo);
    if (coord == null) return;
    await aggiornaGeocodingOspedale(id, lat: coord.lat, lng: coord.lng, regione: coord.regione);
    if (context.mounted) context.read<AnagraficheProvider>().carica();
  }
}

// ---------------------------------------------------------------------------
// Tipologie turno
// ---------------------------------------------------------------------------

class _SezioneTipologie extends StatelessWidget {
  const _SezioneTipologie();

  @override
  Widget build(BuildContext context) {
    final anag = context.watch<AnagraficheProvider>();
    return _SezioneAnag<TipologiaTurno>(
      titolo: 'Tipologie turno',
      icon: Icons.label,
      items: anag.tipologieTurno,
      labelOf: (t) => t.nome,
      sublabelOf: (_) => null,
      colorOf: (t) => colorFromHex(t.colore),
      onAdd: () => _dialogNomeEColore(context, 'Nuova tipologia', (nome, colore) async {
        await saveTipologiaTurno(nome, colore: colore);
        if (context.mounted) context.read<AnagraficheProvider>().carica();
      }),
      onEdit: (t) => _dialogNomeEColore(context, 'Modifica tipologia', (nome, colore) async {
        await saveTipologiaTurno(nome, id: t.id, colore: colore);
        if (context.mounted) context.read<AnagraficheProvider>().carica();
      }, iniziale: t.nome, coloreIniziale: t.colore),
      onDelete: null, // Le tipologie non si eliminano (come da spec originale)
      onMoveUp: (t) async {
        final idx = anag.tipologieTurno.indexWhere((x) => x.id == t.id);
        if (idx <= 0) return;
        await spostaTipologia(idx, idx - 1);
        if (context.mounted) await context.read<AnagraficheProvider>().carica();
      },
      onMoveDown: (t) async {
        final idx = anag.tipologieTurno.indexWhere((x) => x.id == t.id);
        if (idx < 0 || idx >= anag.tipologieTurno.length - 1) return;
        await spostaTipologia(idx, idx + 1);
        if (context.mounted) await context.read<AnagraficheProvider>().carica();
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Sezione generica collassabile con ricerca
// ---------------------------------------------------------------------------

/// Sezione con header cliccabile (collassa/espande), contatore badge,
/// pulsante + sempre accessibile e campo ricerca quando espansa.
/// Collassata di default per non sovraccaricare la schermata con liste lunghe.
class _SezioneAnag<T> extends StatefulWidget {
  final String titolo;
  final IconData icon;
  final List<T> items;
  final String Function(T) labelOf;
  final String? Function(T) sublabelOf;
  final Color? Function(T)? colorOf;
  final VoidCallback onAdd;
  final Future<void> Function(T) onEdit;
  final Future<void> Function(T)? onDelete;
  // Messaggio mostrato quando il DB blocca l'eliminazione per vincolo FK:
  // spiega all'utente PERCHÉ la voce non si può eliminare (es. usata in turni).
  final String? messaggioVincolo;
  // Frecce di riordino: se non null, compaiono ↑↓ per ogni voce (disabilitate con filtro attivo).
  final Future<void> Function(T)? onMoveUp;
  final Future<void> Function(T)? onMoveDown;
  // Se non null, mostra un pulsante per vedere i turni/assistenze in cui compare la voce
  // (usato da Persone e Ospedali per navigare all'elenco filtrato).
  final Future<void> Function(T)? onView;
  // Se non null, mostrano due pulsanti export/import dell'anagrafica (per
  // ora solo Ospedali): a differenza di onAdd/onEdit/onDelete non riguardano
  // una singola voce, quindi niente parametro T.
  final Future<void> Function()? onExport;
  final Future<void> Function()? onImport;

  const _SezioneAnag({
    required this.titolo,
    required this.icon,
    required this.items,
    required this.labelOf,
    required this.sublabelOf,
    this.colorOf,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
    this.messaggioVincolo,
    this.onMoveUp,
    this.onMoveDown,
    this.onView,
    this.onExport,
    this.onImport,
  });

  @override
  State<_SezioneAnag<T>> createState() => _SezioneAnagState<T>();
}

class _SezioneAnagState<T> extends State<_SezioneAnag<T>> {
  bool _expanded = false;
  final _searchCtrl = TextEditingController();
  String _query = '';
  // Disabilita i pulsanti export/import mentre l'operazione è in corso
  // (file picker + scritture DB, non istantanee): un doppio tap non deve
  // avviare due import in parallelo.
  bool _ioBusy = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleExport() async {
    if (widget.onExport == null || _ioBusy) return;
    setState(() => _ioBusy = true);
    try {
      await widget.onExport!();
    } finally {
      if (mounted) setState(() => _ioBusy = false);
    }
  }

  Future<void> _handleImport() async {
    if (widget.onImport == null || _ioBusy) return;
    setState(() => _ioBusy = true);
    try {
      await widget.onImport!();
    } finally {
      if (mounted) setState(() => _ioBusy = false);
    }
  }

  /// Filtra la lista per il testo corrente cercando in label e sublabel.
  List<T> get _filtered {
    if (_query.isEmpty) return widget.items;
    final q = _query.toLowerCase();
    return widget.items.where((item) {
      return widget.labelOf(item).toLowerCase().contains(q) ||
          (widget.sublabelOf(item)?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  /// Chiede conferma prima di eliminare (un tap accidentale non deve perdere
  /// dati per sempre) e gestisce il rifiuto del DB per vincolo FK: senza il
  /// catch, eliminare una voce ancora referenziata (es. persona in un turno)
  /// fallirebbe senza alcun feedback per l'utente.
  Future<void> _confermaEdElimina(T item) async {
    final label = widget.labelOf(item);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina'),
        content: Text('Eliminare "$label"? L\'operazione non è reversibile.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina', style: TextStyle(color: kPrimary)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.onDelete!(item);
    } catch (e) {
      if (!mounted) return;
      // Le eccezioni FK di sqflite (nativo e FFI) contengono sempre
      // "FOREIGN KEY constraint failed": basta il match sulla stringa,
      // senza importare i tipi di sqflite in una schermata UI.
      final vincoloFk = e.toString().contains('FOREIGN KEY');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(vincoloFk
            ? 'Impossibile eliminare "$label": ${widget.messaggioVincolo ?? 'è ancora usata da altri dati.'}'
            : 'Errore durante l\'eliminazione: $e'),
      ));
    }
  }

  /// Resetta la ricerca quando si chiude la sezione così riaprendo è pulita.
  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      if (!_expanded) {
        _query = '';
        _searchCtrl.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header: tutta la riga collassa/espande tranne il tasto +
        InkWell(
          onTap: _toggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                Icon(widget.icon, size: 18, color: kPrimary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.titolo,
                    style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                // Badge col numero di elementi totali (visibile anche da collassato)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: kPrimary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${widget.items.length}',
                    style: const TextStyle(color: kPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
                // Export/import dell'intera anagrafica (solo Ospedali per ora):
                // sempre visibili come l'aggiunta, non richiedono di espandere prima.
                if (widget.onExport != null || widget.onImport != null)
                  if (_ioBusy)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else ...[
                    if (widget.onExport != null)
                      IconButton(
                        icon: const Icon(Icons.upload_file, size: 18, color: Colors.white70),
                        onPressed: _handleExport,
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Esporta',
                      ),
                    if (widget.onImport != null)
                      IconButton(
                        icon: const Icon(Icons.download, size: 18, color: Colors.white70),
                        onPressed: _handleImport,
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Importa',
                      ),
                  ],
                // Pulsante aggiunta sempre visibile (non richiede di espandere prima)
                IconButton(
                  icon: const Icon(Icons.add, size: 20, color: Colors.white70),
                  onPressed: widget.onAdd,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Aggiungi',
                ),
                Icon(
                  _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  color: Colors.white38,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        // Contenuto (solo quando espanso)
        if (_expanded) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Cerca in ${widget.titolo.toLowerCase()}...',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () => setState(() {
                          _query = '';
                          _searchCtrl.clear();
                        }),
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                _query.isEmpty ? 'Nessun elemento' : 'Nessun risultato per "$_query"',
                style: const TextStyle(color: Colors.white38, fontSize: 13),
              ),
            )
          else
            ...filtered.asMap().entries.map((entry) {
              final i = entry.key;
              final item = entry.value;
              final canUp = widget.onMoveUp != null && _query.isEmpty && i > 0;
              final canDown = widget.onMoveDown != null && _query.isEmpty && i < filtered.length - 1;
              final dot = widget.colorOf != null ? widget.colorOf!(item) : null;
              return ListTile(
                dense: true,
                leading: dot != null
                    ? Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                      )
                    : (widget.colorOf != null ? const SizedBox(width: 14, height: 14) : null),
                title: Text(widget.labelOf(item)),
                subtitle: widget.sublabelOf(item) != null
                    ? Text(widget.sublabelOf(item)!, style: const TextStyle(color: Colors.white54))
                    : null,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (widget.onMoveUp != null && _query.isEmpty) ...[
                    IconButton(
                      icon: Icon(Icons.arrow_upward, size: 16, color: canUp ? Colors.white54 : Colors.white12),
                      onPressed: canUp ? () => widget.onMoveUp!(item) : null,
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      icon: Icon(Icons.arrow_downward, size: 16, color: canDown ? Colors.white54 : Colors.white12),
                      onPressed: canDown ? () => widget.onMoveDown!(item) : null,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                  if (widget.onView != null)
                    IconButton(
                      icon: const Icon(Icons.event_note, size: 18, color: Colors.white54),
                      onPressed: () => widget.onView!(item),
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Vedi turni',
                    ),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 18, color: Colors.white54),
                    onPressed: () => widget.onEdit(item),
                    visualDensity: VisualDensity.compact,
                  ),
                  if (widget.onDelete != null)
                    IconButton(
                      icon: const Icon(Icons.delete, size: 18, color: kPrimary),
                      onPressed: () => _confermaEdElimina(item),
                      visualDensity: VisualDensity.compact,
                    ),
                ]),
              );
            }),
          const SizedBox(height: 4),
        ],
      ],
    );
  }
}

/// Dialog con campo nome e palette colori per associazioni e tipologie.
Future<void> _dialogNomeEColore(
  BuildContext context,
  String titolo,
  Future<void> Function(String nome, String? colore) onSalva, {
  String iniziale = '',
  String? coloreIniziale,
}) async {
  final ctrl = TextEditingController(text: iniziale);
  String? coloreSelezionato = coloreIniziale;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocalState) => AlertDialog(
        title: Text(titolo),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(labelText: 'Nome'),
              textCapitalization: TextCapitalization.words,
              autofocus: true,
            ),
            const SizedBox(height: 16),
            const Text('Colore', style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: kColorPalette.map((hex) {
                final c = colorFromHex(hex)!;
                final sel = coloreSelezionato == hex;
                return GestureDetector(
                  onTap: () => setLocalState(() => coloreSelezionato = sel ? null : hex),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: sel ? Border.all(color: Colors.white, width: 3) : null,
                    ),
                    child: sel ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
                  ),
                );
              }).toList(),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salva')),
        ],
      ),
    ),
  );
  if (ok == true && ctrl.text.trim().isNotEmpty) {
    await onSalva(ctrl.text.trim(), coloreSelezionato);
  }
}
