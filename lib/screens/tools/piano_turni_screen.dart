import 'dart:convert';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/format.dart';
import '../../utils/piano_mensile.dart';
import '../../utils/theme.dart';

// Preferenze persistenti: link dell'ultimo foglio (ricaricato all'apertura),
// archivio dei fogli per mese (come lo "storico" del tool HTML: ogni mese ha
// un suo foglio Google, senza archivio si dovrebbe re-incollare il link a
// ogni cambio mese) e ruoli esclusi dal conteggio buchi (es. il Quarto,
// spesso scoperto per scelta: senza filtro ogni giorno avrebbe un pallino e
// i pallini non direbbero nulla).
const _kUrlKey = 'piano_turni_url';
const _kFogliKey = 'piano_turni_fogli'; // JSON: {"aaaa-mm": url}
const _kRuoliEsclusiKey = 'piano_turni_ruoli_esclusi';

// Colori delle fasce, ripresi dalla legenda del tool HTML originale
// (mattina giallo, pomeriggio arancio, sera verde, notte blu) ma saturati
// per il tema scuro; violetto per assistenze/gettoni come nell'originale.
const _coloriFascia = {
  FasciaPiano.mattina: Color(0xFFFFEB3B),
  FasciaPiano.pomeriggio: Color(0xFFFF9800),
  FasciaPiano.sera: Color(0xFF4CAF50),
  FasciaPiano.notte: Color(0xFF2196F3),
};
const _coloreAssistenza = Color(0xFFBA68C8);

Color _colorePerSlot(SlotPiano s) =>
    s.assistenza ? _coloreAssistenza : _coloriFascia[s.fascia]!;

/// Tool "Piano turni": carica il foglio Google mensile dei turni
/// dell'associazione (stesso foglio del tool HTML preesistente) e lo mostra
/// come calendario: pallini colorati per fascia sui giorni con buchi, tap su
/// un giorno per vedere gli equipaggi blocco per blocco coi ruoli scoperti.
class PianoTurniScreen extends StatefulWidget {
  const PianoTurniScreen({super.key});

  @override
  State<PianoTurniScreen> createState() => _PianoTurniScreenState();
}

class _PianoTurniScreenState extends State<PianoTurniScreen> {
  final _urlCtrl = TextEditingController();
  PianoMensile? _piano;
  bool _loading = false;
  String? _errore;
  int _giornoSelezionato = 1;
  Set<RuoloPiano> _ruoliEsclusi = {};
  // Archivio dei fogli salvati: chiave "aaaa-mm" (ordinabile), valore URL.
  Map<String, String> _fogliSalvati = {};

  @override
  void initState() {
    super.initState();
    _ripristinaPreferenze();
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    super.dispose();
  }

  /// Ricarica URL e filtri salvati; se c'è un URL memorizzato parte subito
  /// il caricamento (il caso d'uso tipico è riaprire il piano del mese
  /// corrente, non incollare un link nuovo).
  Future<void> _ripristinaPreferenze() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(_kUrlKey);
    final esclusi = prefs.getStringList(_kRuoliEsclusiKey) ?? const [];
    final fogli = <String, String>{};
    // Archivio corrotto/assente: si riparte vuoto, non è un errore.
    try {
      final decoded = jsonDecode(prefs.getString(_kFogliKey) ?? '{}');
      if (decoded is Map) {
        decoded.forEach((k, v) {
          if (k is String && v is String) fogli[k] = v;
        });
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _fogliSalvati = fogli;
      _ruoliEsclusi = esclusi
          .map((n) => RuoloPiano.values.where((r) => r.name == n).firstOrNull)
          .whereType<RuoloPiano>()
          .toSet();
      if (url != null) _urlCtrl.text = url;
    });
    if (url != null && url.isNotEmpty) await _carica();
  }

  Future<void> _salvaFogli() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kFogliKey, jsonEncode(_fogliSalvati));
  }

  /// Chiave archivio del piano caricato: "2026-07" (ordinabile come testo).
  static String _chiaveMese(PianoMensile piano) =>
      '${piano.anno}-${piano.mese.toString().padLeft(2, '0')}';

  /// Etichetta leggibile di una chiave archivio: "2026-07" → "Luglio 2026".
  String _etichettaMese(String chiave) {
    final parti = chiave.split('-');
    final mese = int.tryParse(parti.length == 2 ? parti[1] : '');
    if (parti.length != 2 || mese == null || mese < 1 || mese > 12) return chiave;
    return '${kMesiItaliani[mese - 1]} ${parti[0]}';
  }

  /// Id del foglio da un link Google Sheets, o dal solo id incollato nudo.
  String? _estraiSheetId(String input) {
    final match = RegExp(r'/d/([a-zA-Z0-9_-]+)').firstMatch(input);
    if (match != null) return match.group(1);
    if (RegExp(r'^[a-zA-Z0-9_-]{25,}$').hasMatch(input)) return input;
    return null;
  }

  Future<void> _carica() async {
    final input = _urlCtrl.text.trim();
    final sheetId = _estraiSheetId(input);
    if (sheetId == null) {
      setState(() => _errore = 'Link non valido: incolla il link del foglio Google Sheets.');
      return;
    }
    setState(() {
      _loading = true;
      _errore = null;
    });
    try {
      // Stesso trucco del tool HTML: l'endpoint export del foglio restituisce
      // l'XLSX completo senza bisogno di API key (foglio condiviso con link).
      final resp = await http.get(Uri.parse(
          'https://docs.google.com/spreadsheets/d/$sheetId/export?format=xlsx'));
      if (resp.statusCode != 200) {
        throw FormatException(
            'Il server ha risposto ${resp.statusCode}: verifica che il foglio '
            'sia condiviso ("chiunque abbia il link").');
      }
      // compute(): il decode dell'XLSX (~30 schede) bloccherebbe la UI.
      final piano = await compute(parsePianoMensile, resp.bodyBytes);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kUrlKey, input);
      if (!mounted) return;
      final oggi = DateTime.now();
      setState(() {
        _piano = piano;
        // Il foglio viene archiviato sotto il suo mese (letto da B2, non
        // dall'input dell'utente): ricaricare lo stesso mese aggiorna la
        // voce invece di duplicarla, come lo storico del tool HTML.
        _fogliSalvati[_chiaveMese(piano)] = input;
        // Parte da oggi se il piano è del mese corrente, altrimenti dal 1°.
        _giornoSelezionato =
            (oggi.year == piano.anno && oggi.month == piano.mese) ? oggi.day : 1;
      });
      await _salvaFogli();
    } on FormatException catch (e) {
      if (mounted) setState(() => _errore = e.message);
    } catch (e) {
      if (mounted) setState(() => _errore = 'Caricamento fallito: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggleRuolo(RuoloPiano ruolo) {
    setState(() {
      if (!_ruoliEsclusi.remove(ruolo)) _ruoliEsclusi.add(ruolo);
    });
    SharedPreferences.getInstance().then((prefs) => prefs.setStringList(
        _kRuoliEsclusiKey, _ruoliEsclusi.map((r) => r.name).toList()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Piano turni'),
        actions: [
          if (_piano != null && !_loading) ...[
            if (_fogliSalvati.length > 1)
              IconButton(
                icon: const Icon(Icons.history),
                tooltip: 'Fogli salvati',
                onPressed: _apriFogliSalvati,
              ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Cambia foglio',
              // Torna al form col link corrente ancora nel campo.
              onPressed: () => setState(() => _piano = null),
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Ricarica dal foglio',
              onPressed: _carica,
            ),
          ],
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _piano == null
              ? _form()
              : _calendario(_piano!),
    );
  }

  // ---------------------------------------------------------------------
  // Form iniziale (nessun piano caricato)
  // ---------------------------------------------------------------------

  Widget _form() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Incolla il link del foglio Google dei turni del mese '
          '(condiviso con "chiunque abbia il link").',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _urlCtrl,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Link foglio Google Sheets',
            hintText: 'https://docs.google.com/spreadsheets/d/...',
          ),
          onSubmitted: (_) => _carica(),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _carica,
            icon: const Icon(Icons.download, size: 18),
            label: const Text('Carica piano'),
            style: FilledButton.styleFrom(backgroundColor: kPrimary),
          ),
        ),
        if (_errore != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_errore!, style: const TextStyle(color: kPrimary, fontSize: 13)),
          ),
        // Fogli già usati: un tap ricarica il mese senza re-incollare il link.
        if (_fogliSalvati.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(top: 20, bottom: 4),
            child: Text('Fogli salvati',
                style: TextStyle(color: kPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
          ),
          for (final chiave in _chiaviOrdinate()) _tileFoglioSalvato(chiave),
        ],
      ],
    );
  }

  /// Chiavi archivio dal mese più recente: "2026-07" ordina come testo.
  List<String> _chiaviOrdinate() =>
      _fogliSalvati.keys.toList()..sort((a, b) => b.compareTo(a));

  Widget _tileFoglioSalvato(String chiave) {
    final caricato =
        _piano != null && chiave == _chiaveMese(_piano!);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        leading: Icon(Icons.table_chart_outlined,
            color: caricato ? kPrimary : Colors.white54, size: 20),
        title: Text(_etichettaMese(chiave)),
        subtitle: caricato
            ? const Text('Caricato', style: TextStyle(color: kPrimary, fontSize: 11))
            : null,
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.white38, size: 20),
          tooltip: 'Rimuovi dai salvati',
          onPressed: () => _eliminaFoglio(chiave),
        ),
        onTap: () {
          _urlCtrl.text = _fogliSalvati[chiave]!;
          _carica();
        },
      ),
    );
  }

  void _eliminaFoglio(String chiave) {
    // Si elimina solo il link salvato, non il foglio Google: niente conferma.
    setState(() => _fogliSalvati.remove(chiave));
    _salvaFogli();
  }

  /// Bottom sheet coi mesi salvati, per cambiare foglio senza passare dal form.
  void _apriFogliSalvati() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Fogli salvati',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            ),
            for (final chiave in _chiaviOrdinate())
              ListTile(
                dense: true,
                leading: Icon(Icons.table_chart_outlined,
                    color: _piano != null && chiave == _chiaveMese(_piano!)
                        ? kPrimary
                        : Colors.white54,
                    size: 20),
                title: Text(_etichettaMese(chiave)),
                onTap: () {
                  Navigator.pop(ctx);
                  _urlCtrl.text = _fogliSalvati[chiave]!;
                  _carica();
                },
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Calendario
  // ---------------------------------------------------------------------

  Widget _calendario(PianoMensile piano) {
    final slotsGiorno = piano.delGiorno(_giornoSelezionato);
    final buchiGiorno =
        piano.buchiDelGiorno(_giornoSelezionato, ruoliEsclusi: _ruoliEsclusi);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${kMesiItaliani[piano.mese - 1]} ${piano.anno}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
              ),
              if (_errore != null)
                const Icon(Icons.warning_amber, size: 16, color: kPrimary),
            ],
          ),
        ),
        _filtriRuoli(),
        _legenda(),
        _rigaGiorniSettimana(),
        _griglia(piano),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(
            children: [
              Text(
                '$_giornoSelezionato ${kMesiItaliani[piano.mese - 1]}',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(width: 8),
              Text(
                buchiGiorno.isEmpty
                    ? 'nessun buco'
                    : (buchiGiorno.length == 1 ? '1 buco' : '${buchiGiorno.length} buchi'),
                style: TextStyle(
                  color: buchiGiorno.isEmpty ? Colors.white54 : kPrimary,
                  fontSize: 13,
                  fontWeight: buchiGiorno.isEmpty ? FontWeight.normal : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: slotsGiorno.isEmpty
              ? const Center(
                  child: Text(
                    'Nessun dato per questo giorno',
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                )
              : _dettaglioGiorno(slotsGiorno),
        ),
      ],
    );
  }

  /// FilterChip per ruolo: deselezionare un ruolo lo esclude dal conteggio
  /// buchi (pallini e contatore), non dal dettaglio equipaggio.
  Widget _filtriRuoli() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Wrap(
        spacing: 6,
        children: [
          for (final ruolo in RuoloPiano.values)
            FilterChip(
              label: Text(ruolo.sigla, style: const TextStyle(fontSize: 11)),
              visualDensity: VisualDensity.compact,
              selected: !_ruoliEsclusi.contains(ruolo),
              onSelected: (_) => _toggleRuolo(ruolo),
              selectedColor: kPrimary.withValues(alpha: 0.25),
              checkmarkColor: kPrimary,
            ),
        ],
      ),
    );
  }

  Widget _legenda() {
    Widget voce(Color colore, String testo) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(shape: BoxShape.circle, color: colore),
            ),
            const SizedBox(width: 3),
            Text(testo, style: const TextStyle(color: Colors.white54, fontSize: 10)),
          ],
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: Wrap(
        spacing: 10,
        children: [
          voce(_coloriFascia[FasciaPiano.mattina]!, 'Mattina'),
          voce(_coloriFascia[FasciaPiano.pomeriggio]!, 'Pomeriggio'),
          voce(_coloriFascia[FasciaPiano.sera]!, 'Sera'),
          voce(_coloriFascia[FasciaPiano.notte]!, 'Notte'),
          voce(_coloreAssistenza, 'Assist./Gettone'),
        ],
      ),
    );
  }

  Widget _rigaGiorniSettimana() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          for (final g in kGiorniSettimanaIt)
            Expanded(
              child: Center(
                child: Text(
                  g,
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _griglia(PianoMensile piano) {
    // Stessa geometria di CalendarioTurni: settimana dal lunedì, offset =
    // celle vuote prima del giorno 1.
    final offset = DateTime(piano.anno, piano.mese, 1).weekday - 1;
    final giorni = piano.giorniNelMese;
    final settimane = ((offset + giorni) / 7).ceil();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          for (int s = 0; s < settimane; s++)
            Row(
              children: [
                for (int g = 0; g < 7; g++)
                  _cella(piano, s * 7 + g - offset + 1),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cella(PianoMensile piano, int giorno) {
    if (giorno < 1 || giorno > piano.giorniNelMese) {
      // Fuori mese: cella vuota (qui non esistono dati dei mesi adiacenti).
      return const Expanded(child: SizedBox(height: 44));
    }
    final slots = piano.delGiorno(giorno);
    final buchi = piano.buchiDelGiorno(giorno, ruoliEsclusi: _ruoliEsclusi);
    final selezionato = giorno == _giornoSelezionato;
    final oggi = DateTime.now();
    final isOggi =
        oggi.year == piano.anno && oggi.month == piano.mese && oggi.day == giorno;

    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _giornoSelezionato = giorno),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 44,
          margin: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            color: selezionato ? kPrimary.withValues(alpha: 0.18) : null,
            borderRadius: BorderRadius.circular(8),
            border: selezionato
                ? Border.all(color: kPrimary)
                : (isOggi ? Border.all(color: Colors.white24) : null),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '$giorno',
                style: TextStyle(
                  fontSize: 13,
                  // Giorno senza scheda nel foglio: numero attenuato, così i
                  // giorni "senza dati" non sembrano giorni senza buchi.
                  color: slots.isEmpty
                      ? Colors.white24
                      : (isOggi ? kPrimary : Colors.white),
                  fontWeight:
                      selezionato || isOggi ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              SizedBox(
                height: 8,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final b in buchi.take(4))
                      Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _colorePerSlot(b),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Dettaglio del giorno: equipaggi blocco per blocco
  // ---------------------------------------------------------------------

  Widget _dettaglioGiorno(List<SlotPiano> slots) {
    // Una card per blocco: H24 e H12 separati e ogni fascia con la propria
    // card, nella sequenza richiesta esplicitamente dall'utente:
    // H24 mattina, H24 pomeriggio, centralino di giorno, H12 mattina,
    // H12 pomeriggio, H24 sera, H24 notte, centralino di sera, assistenze,
    // gettoni, altro. A parità resta l'ordine del foglio (sort decorato con
    // l'indice: List.sort non è stabile).
    final blocchi = <int, List<SlotPiano>>{};
    for (final s in slots) {
      blocchi.putIfAbsent(s.blocco, () => []).add(s);
    }
    final ordinati = List.of(blocchi.values.indexed)
      ..sort((a, b) {
        final perPriorita =
            _prioritaBlocco(a.$2).compareTo(_prioritaBlocco(b.$2));
        if (perPriorita != 0) return perPriorita;
        final perFascia = a.$2.first.fascia.index.compareTo(b.$2.first.fascia.index);
        return perFascia != 0 ? perFascia : a.$1.compareTo(b.$1);
      });

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [for (final (_, gruppo) in ordinati) _cardBlocco(gruppo)],
    );
  }

  /// Posizione della card nella sequenza voluta dall'utente; 11 = "altro",
  /// che poi si ordina per fascia.
  int _prioritaBlocco(List<SlotPiano> gruppo) {
    final primo = gruppo.first;
    if (primo.ruolo == RuoloPiano.centralino) {
      // Il blocco diurno del centralino ha gli slot mattina/pomeriggio,
      // quello notturno solo la sera.
      final diGiorno = gruppo.any((s) =>
          s.fascia == FasciaPiano.mattina || s.fascia == FasciaPiano.pomeriggio);
      return diGiorno ? 2 : 7;
    }
    switch (primo.macro) {
      case 'H24':
        return switch (primo.fascia) {
          FasciaPiano.mattina => 0,
          FasciaPiano.pomeriggio => 1,
          FasciaPiano.sera => 5,
          FasciaPiano.notte => 6,
        };
      case 'H12':
        return switch (primo.fascia) {
          FasciaPiano.mattina => 3,
          FasciaPiano.pomeriggio => 4,
          // Non nell'elenco richiesto: un H12 serale/notturno resta comunque
          // un equipaggio di emergenza, quindi subito dopo il centralino
          // serale e prima di assistenze/gettoni.
          FasciaPiano.sera || FasciaPiano.notte => 8,
        };
      case 'ASSISTENZA':
        return 9;
      case 'GETTONE':
        return 10;
    }
    return 11;
  }

  String _titoloBlocco(List<SlotPiano> gruppo) {
    final primo = gruppo.first;
    if (primo.ruolo == RuoloPiano.centralino) return 'Centralino';
    if (primo.macro == 'ASSISTENZA') return 'Assistenza';
    if (primo.macro == 'GETTONE') return 'Gettone';
    return '${primo.macro} · ${primo.fascia.etichetta}';
  }

  Widget _cardBlocco(List<SlotPiano> gruppo) {
    final primo = gruppo.first;
    final colore = _colorePerSlot(primo);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: colore),
                ),
                const SizedBox(width: 8),
                Text(
                  _titoloBlocco(gruppo),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Intestazione delle due colonne del foglio (C = chi è di turno,
            // D = possibili sostituti): senza, i nomi della seconda colonna
            // sembrerebbero un secondo membro dell'equipaggio.
            const Padding(
              padding: EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  SizedBox(width: 90),
                  Expanded(
                    child: Text('DI TURNO',
                        style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w600)),
                  ),
                  Expanded(
                    child: Text('SOSTITUTI',
                        style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
            for (final slot in gruppo) _rigaSlot(slot),
          ],
        ),
      ),
    );
  }

  Widget _rigaSlot(SlotPiano slot) {
    // Etichetta: per il centralino la fascia distingue gli slot del blocco
    // (mattina/pomeriggio), per gli altri blocchi la fascia è nel titolo.
    final etichetta = slot.ruolo == RuoloPiano.centralino
        ? slot.fascia.etichetta
        : slot.ruolo.etichetta;
    final escluso = _ruoliEsclusi.contains(slot.ruolo);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(etichetta,
                style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ),
          if (slot.buco)
            Expanded(
              flex: 2,
              // Buco di un ruolo escluso dai filtri: trattino neutro invece
              // del rosso, coerente col fatto che non conta come buco.
              child: Text(
                escluso ? '—' : 'MANCANTE',
                style: TextStyle(
                  color: escluso ? Colors.white30 : kPrimary,
                  fontSize: 13,
                  fontWeight: escluso ? FontWeight.normal : FontWeight.bold,
                ),
              ),
            )
          else ...[
            // Le due colonne del foglio affiancate: titolare e sostituti.
            Expanded(
              child: Text(
                slot.titolare.isEmpty ? '—' : slot.titolare,
                style: TextStyle(
                  color: slot.titolare.isEmpty ? Colors.white30 : Colors.white,
                  fontSize: 13,
                ),
              ),
            ),
            Expanded(
              child: Text(
                slot.sostituti.isEmpty ? '—' : slot.sostituti,
                style: TextStyle(
                  color: slot.sostituti.isEmpty ? Colors.white30 : Colors.white70,
                  fontSize: 13,
                  fontStyle: slot.sostituti.isEmpty ? FontStyle.normal : FontStyle.italic,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
