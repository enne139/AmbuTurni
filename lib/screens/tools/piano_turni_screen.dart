import 'dart:convert';
import 'package:add_2_calendar/add_2_calendar.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../db/backup_file.dart';
import '../../utils/backend_api.dart';
import '../../utils/format.dart';
import '../../utils/piano_cache.dart';
import '../../utils/piano_mensile.dart';
import '../../utils/platform_check.dart';
import '../../utils/prefs_keys.dart';
import '../../utils/theme.dart';

const _uuid = Uuid();

// Preferenze persistenti (chiavi in utils/prefs_keys.dart, condivise col
// backup): link dell'ultimo foglio (ricaricato all'apertura), archivio dei
// fogli per mese (come lo "storico" del tool HTML: ogni mese ha un suo
// foglio Google, senza archivio si dovrebbe re-incollare il link a ogni
// cambio mese), ruoli esclusi dal conteggio buchi (es. il Quarto, spesso
// scoperto per scelta: senza filtro ogni giorno avrebbe un pallino e i
// pallini non direbbero nulla) e ultima ricerca volontario (segnalini).

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
// Segnalino "nome cercato" sul calendario: ciano, l'unico colore che non
// collide né coi pallini delle fasce né col kPrimary di selezione/oggi.
const _coloreNomeCercato = Color(0xFF26C6DA);

Color _colorePerSlot(SlotPiano s) =>
    s.assistenza ? _coloreAssistenza : _coloriFascia[s.fascia]!;

/// Descrizione compatta di uno slot (usata nei risultati di ricerca):
/// stessa forma dei titoli delle card del dettaglio giorno.
String _titoloSlot(SlotPiano s) {
  if (s.ruolo == RuoloPiano.centralino) return 'Centralino · ${s.fascia.etichetta}';
  if (s.macro == 'ASSISTENZA') return 'Assistenza';
  if (s.macro == 'GETTONE') return 'Gettone';
  return '${s.macro} · ${s.fascia.etichetta}';
}

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
  // Nome dell'ultima ricerca volontario: i giorni in cui compare hanno un
  // segnalino sul calendario. Persiste tra i riavvii (tipicamente si cerca
  // sempre il proprio nome: i segnalini mostrano i propri turni a colpo
  // d'occhio senza rifare la ricerca).
  String _nomeCercato = '';

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
    final url = prefs.getString(kPrefPianoTurniUrl);
    final esclusi = prefs.getStringList(kPrefPianoTurniRuoliEsclusi) ?? const [];
    final fogli = <String, String>{};
    // Archivio corrotto/assente: si riparte vuoto, non è un errore.
    try {
      final decoded = jsonDecode(prefs.getString(kPrefPianoTurniFogli) ?? '{}');
      if (decoded is Map) {
        decoded.forEach((k, v) {
          if (k is String && v is String) fogli[k] = v;
        });
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _fogliSalvati = fogli;
      _nomeCercato = prefs.getString(kPrefPianoTurniUltimaRicerca) ?? '';
      _ruoliEsclusi = esclusi
          .map((n) => RuoloPiano.values.where((r) => r.name == n).firstOrNull)
          .whereType<RuoloPiano>()
          .toSet();
      if (url != null) _urlCtrl.text = url;
    });
    if (url != null && url.isNotEmpty) {
      // Cache-first: l'ultimo piano decodificato compare subito (anche
      // offline), il download da Google lo aggiorna poi in sottofondo.
      final ultimoMese = prefs.getString(kPrefPianoTurniUltimoMese);
      final inCache =
          ultimoMese == null ? null : await leggiPianoDaCache(ultimoMese);
      if (inCache != null && mounted) {
        setState(() {
          _piano = inCache;
          _giornoSelezionato = _giornoIniziale(inCache);
        });
        await _carica(silenzioso: true);
      } else {
        await _carica();
      }
    }
    _sincronizzaFogliDalBackend(prefs);
  }

  /// Scarica in sottofondo i fogli salvati sul backend condiviso (pagina
  /// admin) e li aggiunge all'archivio locale, se l'impostazione
  /// "Sincronizza fogli turni" è attiva (default sì, vedi CLAUDE.md e
  /// Impostazioni → Backend condiviso). Best-effort come il geocoding degli
  /// ospedali: nessun errore in UI, un server irraggiungibile o
  /// l'endpoint assente su un backend vecchio non deve disturbare l'apertura
  /// dello strumento. Merge additivo: aggiunge solo le chiavi ("aaaa-mm")
  /// non ancora presenti localmente, senza toccare un link che l'utente ha
  /// già incollato/verificato per quel mese — evita che il backend sovrascriva
  /// silenziosamente un URL già in uso.
  Future<void> _sincronizzaFogliDalBackend(SharedPreferences prefs) async {
    if (!(prefs.getBool(kPrefSyncFogliAttivo) ?? true)) return;
    final baseUrl = prefs.getString(kPrefBackendUrl) ?? kBackendUrlDefault;
    try {
      final remoti = await BackendApi(baseUrl: baseUrl).getFogli();
      if (!mounted || remoti.isEmpty) return;
      final nuovi = {
        for (final entry in remoti.entries)
          if (!_fogliSalvati.containsKey(entry.key)) entry.key: entry.value
      };
      if (nuovi.isEmpty) return;
      setState(() => _fogliSalvati = {..._fogliSalvati, ...nuovi});
      await _salvaFogli();
    } catch (_) {
      // Silenzioso: sincronizzazione best-effort, non un'azione richiesta
      // esplicitamente dall'utente in questo momento.
    }
  }

  /// Giorno selezionato all'apertura di un piano: oggi se è il mese
  /// corrente, altrimenti il 1°.
  static int _giornoIniziale(PianoMensile piano) {
    final oggi = DateTime.now();
    return (oggi.year == piano.anno && oggi.month == piano.mese) ? oggi.day : 1;
  }

  Future<void> _salvaFogli() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPrefPianoTurniFogli, jsonEncode(_fogliSalvati));
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

  /// Scarica e decodifica il foglio. Con [silenzioso] niente spinner: il
  /// piano già a schermo (dalla cache) resta visibile finché non arrivano i
  /// dati freschi, e un errore accende solo l'icona di avviso accanto al
  /// mese invece di svuotare la schermata.
  Future<void> _carica({bool silenzioso = false}) async {
    final input = _urlCtrl.text.trim();
    final sheetId = _estraiSheetId(input);
    if (sheetId == null) {
      setState(() => _errore = 'Link non valido: incolla il link del foglio Google Sheets.');
      return;
    }
    setState(() {
      if (!silenzioso) _loading = true;
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
      final chiave = _chiaveMese(piano);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kPrefPianoTurniUrl, input);
      await prefs.setString(kPrefPianoTurniUltimoMese, chiave);
      // Cache su file: alla prossima apertura questo piano compare subito.
      await salvaPianoInCache(chiave, piano);
      if (!mounted) return;
      setState(() {
        // Aggiornamento in sottofondo dello stesso mese: il giorno che
        // l'utente sta guardando non va resettato sotto le sue dita.
        final stessoMese = _piano != null &&
            _piano!.anno == piano.anno &&
            _piano!.mese == piano.mese;
        _piano = piano;
        // Il foglio viene archiviato sotto il suo mese (letto da B2, non
        // dall'input dell'utente): ricaricare lo stesso mese aggiorna la
        // voce invece di duplicarla, come lo storico del tool HTML.
        _fogliSalvati[chiave] = input;
        if (!(silenzioso && stessoMese)) {
          _giornoSelezionato = _giornoIniziale(piano);
        }
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

  /// Apre un foglio salvato: se il suo piano è già in cache compare subito
  /// e il download aggiorna in sottofondo, altrimenti caricamento normale.
  Future<void> _apriFoglioSalvato(String chiave) async {
    _urlCtrl.text = _fogliSalvati[chiave]!;
    final inCache = await leggiPianoDaCache(chiave);
    if (inCache != null && mounted) {
      setState(() {
        _piano = inCache;
        _errore = null;
        _giornoSelezionato = _giornoIniziale(inCache);
      });
      await _carica(silenzioso: true);
    } else {
      await _carica();
    }
  }

  /// Apre la ricerca per nome; se l'utente tocca un risultato, il calendario
  /// salta a quel giorno (la ricerca restituisce il giorno via pop). Al
  /// ritorno si rilegge comunque l'ultima ricerca persistita, così i
  /// segnalini sul calendario seguono il nome appena cercato (o spariscono
  /// se il campo è stato svuotato di proposito).
  Future<void> _cercaVolontario() async {
    final giorno = await Navigator.push<int>(
      context,
      MaterialPageRoute(builder: (_) => _RicercaVolontarioScreen(piano: _piano!)),
    );
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _nomeCercato = prefs.getString(kPrefPianoTurniUltimaRicerca) ?? '';
      if (giorno != null) _giornoSelezionato = giorno;
    });
  }

  void _toggleRuolo(RuoloPiano ruolo) {
    setState(() {
      if (!_ruoliEsclusi.remove(ruolo)) _ruoliEsclusi.add(ruolo);
    });
    SharedPreferences.getInstance().then((prefs) => prefs.setStringList(
        kPrefPianoTurniRuoliEsclusi, _ruoliEsclusi.map((r) => r.name).toList()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Piano turni'),
        actions: [
          if (_piano != null && !_loading) ...[
            IconButton(
              icon: const Icon(Icons.person_search),
              tooltip: 'Cerca volontario',
              onPressed: _cercaVolontario,
            ),
            if (_fogliSalvati.length > 1)
              IconButton(
                icon: const Icon(Icons.history),
                tooltip: 'Fogli salvati',
                onPressed: _apriFogliSalvati,
              ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Cambia foglio',
              // Campo URL svuotato: qui si arriva per incollare il foglio di
              // un mese nuovo, e il link vecchio andrebbe comunque cancellato
              // a mano (i mesi già caricati restano nei Fogli salvati).
              onPressed: () => setState(() {
                _urlCtrl.clear();
                _piano = null;
              }),
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

  /// Copia il link di un foglio negli appunti: serve per condividerlo o
  /// riaprirlo nel browser senza doverlo recuperare dal foglio Google.
  Future<void> _copiaLink(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link copiato negli appunti')));
    }
  }

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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.copy_outlined, color: Colors.white38, size: 20),
              tooltip: 'Copia link',
              onPressed: () => _copiaLink(_fogliSalvati[chiave]!),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.white38, size: 20),
              tooltip: 'Rimuovi dai salvati',
              onPressed: () => _eliminaFoglio(chiave),
            ),
          ],
        ),
        onTap: () => _apriFoglioSalvato(chiave),
      ),
    );
  }

  void _eliminaFoglio(String chiave) {
    // Si elimina solo il link salvato, non il foglio Google: niente conferma.
    setState(() => _fogliSalvati.remove(chiave));
    _salvaFogli();
    // Senza il link il piano non è più raggiungibile: la sua cache è inutile.
    eliminaPianoDaCache(chiave);
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
                  _apriFoglioSalvato(chiave);
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
    // Giorni in cui il nome dell'ultima ricerca è in servizio: segnalino in
    // cella. giorniInServizio (non cercaNome): un titolare sostituito quel
    // giorno non lavora e non va segnato. Ricalcolato a ogni build: scandisce
    // una lista già in memoria, non vale una cache.
    final giorniConNome = piano.giorniInServizio(_nomeCercato);

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
        _griglia(piano, giorniConNome),
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
          // Voce col nome cercato: dice a colpo d'occhio di chi sono i
          // segnalini persona (che possono restare da una sessione passata).
          if (_nomeCercato.trim().isNotEmpty)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.person, size: 10, color: _coloreNomeCercato),
                const SizedBox(width: 2),
                Text(_nomeCercato.trim(),
                    style: const TextStyle(color: _coloreNomeCercato, fontSize: 10)),
              ],
            ),
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

  Widget _griglia(PianoMensile piano, Set<int> giorniConNome) {
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
                  _cella(piano, s * 7 + g - offset + 1, giorniConNome),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cella(PianoMensile piano, int giorno, Set<int> giorniConNome) {
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
          child: Stack(
            children: [
              Positioned.fill(
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
              // Segnalino persona nell'angolo: il nome cercato è di turno
              // questo giorno. Nell'angolo e non tra i pallini dei buchi,
              // che hanno un altro significato (ruoli scoperti).
              if (giorniConNome.contains(giorno))
                const Positioned(
                  top: 2,
                  right: 3,
                  child: Icon(Icons.person, size: 9, color: _coloreNomeCercato),
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

  /// Etichetta tra parentesi nel titolo dell'evento: la fascia per i turni
  /// ordinari (H12/H24), "centralino"/"gettone"/"assistenza" per i rispettivi
  /// blocchi, "altro" come fallback — formato richiesto dall'utente:
  /// "CVS (sera)". Il centralino va controllato prima della macro: il parser
  /// gli assegna macro H24, e senza il check finirebbe etichettato per fascia.
  static String _etichettaEvento(SlotPiano primo) {
    if (primo.ruolo == RuoloPiano.centralino) return 'centralino';
    if (primo.macro == 'GETTONE') return 'gettone';
    if (primo.macro == 'ASSISTENZA') return 'assistenza';
    if (primo.macro == 'H12' || primo.macro == 'H24') {
      return primo.fascia.etichetta.toLowerCase();
    }
    return 'altro';
  }

  /// Su Android/iOS apre l'editor eventi del calendario di sistema
  /// precompilato col blocco: titolo "CVS (fascia)" e data/orario letti dal
  /// foglio (notte a cavallo di mezzanotte inclusa); niente descrizione, per
  /// scelta dell'utente. Si passa dall'intent di inserimento, non dalla
  /// scrittura diretta: nessun permesso runtime e l'utente conferma/ritocca
  /// l'evento nella sua app calendario. Per lo stesso motivo il colore
  /// dell'evento non è impostabile da qui: l'intent Android non lo prevede,
  /// l'evento prende il colore del calendario su cui viene salvato.
  /// Su desktop/web (add_2_calendar non ha né canale nativo né
  /// implementazione browser) si genera invece un file .ics standard: vedi
  /// `_eventoIcs`.
  Future<void> _aggiungiAlCalendario(List<SlotPiano> gruppo) async {
    final intervallo = _piano!.intervalloEvento(gruppo.first);
    if (intervallo == null) return; // il pulsante non compare senza orario
    final (inizio, fine) = intervallo;
    final titolo = 'CVS (${_etichettaEvento(gruppo.first)})';

    if (isMobile) {
      final ok = await Add2Calendar.addEvent2Cal(Event(
        title: titolo,
        startDate: inizio,
        endDate: fine,
      ));
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Nessuna app calendario trovata sul dispositivo')));
      }
      return;
    }

    // Desktop/web: si salva un file .ics con lo stesso percorso usato per il
    // backup (dialog "Salva come" su desktop, download/share sul web) — la
    // funzione è già generica (testo + nome file), riusata invece di
    // duplicare la logica io/web per un secondo tipo di file.
    try {
      final ics = _eventoIcs(titolo, inizio, fine);
      final nomeFile = 'cvs_${dateToIso(inizio)}_${_etichettaEvento(gruppo.first)}.ics';
      final path = await salvaFilePiattaforma(ics, nomeFile, 'Evento calendario AmbuTurni');
      if (mounted) {
        final msg = path != null ? 'File calendario salvato.' : 'Salvataggio annullato.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Errore: $e')));
      }
    }
  }

  /// Contenuto testuale di un file .ics (RFC 5545) con un singolo evento.
  /// Orari "floating" (senza Z/TZID): stesso orario locale passato finora
  /// all'intent Android, nessuna conversione fuso orario altrove nel codice.
  static String _eventoIcs(String titolo, DateTime inizio, DateTime fine) {
    String fmt(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}'
        '${d.month.toString().padLeft(2, '0')}'
        '${d.day.toString().padLeft(2, '0')}T'
        '${d.hour.toString().padLeft(2, '0')}'
        '${d.minute.toString().padLeft(2, '0')}'
        '${d.second.toString().padLeft(2, '0')}';
    String esc(String s) => s
        .replaceAll('\\', '\\\\')
        .replaceAll(';', '\\;')
        .replaceAll(',', '\\,')
        .replaceAll('\n', '\\n');
    final dtstamp = '${fmt(DateTime.now().toUtc())}Z';
    final uid = '${_uuid.v4()}@ambuturni';
    return [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//AmbuTurni//IT',
      'BEGIN:VEVENT',
      'UID:$uid',
      'DTSTAMP:$dtstamp',
      'DTSTART:${fmt(inizio)}',
      'DTEND:${fmt(fine)}',
      'SUMMARY:${esc(titolo)}',
      'END:VEVENT',
      'END:VCALENDAR',
    ].join('\r\n');
  }

  Widget _cardBlocco(List<SlotPiano> gruppo) {
    final primo = gruppo.first;
    final colore = _colorePerSlot(primo);
    // Slot con orari diversi (centralino diurno: mattina e pomeriggio hanno
    // ciascuno il proprio intervallo): orario e pulsante calendario vanno
    // sulla riga di ogni slot, non nell'intestazione — un solo pulsante non
    // saprebbe quale dei due eventi creare.
    final orariDiversi = gruppo.map((s) => s.orario).toSet().length > 1;
    final orario = orariDiversi ? null : primo.orarioParsed;

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
                Expanded(
                  child: Text(
                    _titoloBlocco(gruppo),
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                ),
                // Orario e pulsante calendario solo se il foglio ha l'orario
                // del blocco: senza, l'evento non avrebbe inizio/fine.
                if (orario != null) ...[
                  Text(
                    primo.orario,
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit_calendar_outlined,
                        size: 20, color: Colors.white70),
                    tooltip: 'Aggiungi al calendario',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    onPressed: () => _aggiungiAlCalendario(gruppo),
                  ),
                ],
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
            for (final slot in gruppo)
              _rigaSlot(slot, calendarioInRiga: orariDiversi),
          ],
        ),
      ),
    );
  }

  /// True se [testo] contiene il nome dell'ultima ricerca (stesso match
  /// parziale case-insensitive di cercaNome).
  bool _matchNomeCercato(String testo) {
    final q = _nomeCercato.trim().toLowerCase();
    return q.isNotEmpty && testo.toLowerCase().contains(q);
  }

  /// Nome con l'eventuale icona persona accanto (lo stesso segnalino del
  /// calendario): individua a colpo d'occhio il nome cercato dentro le card
  /// del giorno.
  Widget _nomeConSegnalino(String testo, TextStyle stile, bool segnalino) {
    if (!segnalino) return Text(testo, style: stile);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(testo, style: stile)),
        const SizedBox(width: 3),
        const Icon(Icons.person, size: 11, color: _coloreNomeCercato),
      ],
    );
  }

  Widget _rigaSlot(SlotPiano slot, {bool calendarioInRiga = false}) {
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
            // L'icona persona segue la regola del calendario: il titolare
            // sostituito quel giorno non lavora, quindi niente icona.
            Expanded(
              child: _nomeConSegnalino(
                slot.titolare.isEmpty ? '—' : slot.titolare,
                TextStyle(
                  color: slot.titolare.isEmpty ? Colors.white30 : Colors.white,
                  fontSize: 13,
                ),
                _matchNomeCercato(slot.titolare) && slot.sostituti.isEmpty,
              ),
            ),
            Expanded(
              child: _nomeConSegnalino(
                slot.sostituti.isEmpty ? '—' : slot.sostituti,
                TextStyle(
                  color: slot.sostituti.isEmpty ? Colors.white30 : Colors.white70,
                  fontSize: 13,
                  fontStyle: slot.sostituti.isEmpty ? FontStyle.normal : FontStyle.italic,
                ),
                _matchNomeCercato(slot.sostituti),
              ),
            ),
          ],
          // Pulsante calendario per slot (centralino diurno): compatto per
          // non alzare la riga, l'orario dello slot è nel tooltip.
          if (calendarioInRiga && slot.orarioParsed != null)
            SizedBox(
              width: 26,
              height: 20,
              child: IconButton(
                icon: const Icon(Icons.edit_calendar_outlined,
                    size: 16, color: Colors.white70),
                tooltip: 'Aggiungi al calendario (${slot.orario})',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => _aggiungiAlCalendario([slot]),
              ),
            ),
        ],
      ),
    );
  }
}

/// Ricerca di un volontario nei turni del mese (equivalente della "Ricerca
/// Volontario" del tool HTML): cerca in titolari e sostituti, risultati in
/// ordine cronologico. Il tap su un risultato torna al calendario facendolo
/// saltare a quel giorno (pop col giorno come risultato della route).
class _RicercaVolontarioScreen extends StatefulWidget {
  final PianoMensile piano;
  const _RicercaVolontarioScreen({required this.piano});

  @override
  State<_RicercaVolontarioScreen> createState() => _RicercaVolontarioScreenState();
}

class _RicercaVolontarioScreenState extends State<_RicercaVolontarioScreen> {
  final _ctrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Ripropone l'ultima ricerca (tipicamente si cerca sempre il proprio
    // nome), preselezionata: digitare un nome nuovo la sostituisce senza
    // doverla cancellare. Il check su text.isEmpty evita di sovrascrivere
    // quello che l'utente ha già digitato mentre le prefs caricavano.
    SharedPreferences.getInstance().then((prefs) {
      final ultima = prefs.getString(kPrefPianoTurniUltimaRicerca);
      if (ultima != null && ultima.isNotEmpty && mounted && _ctrl.text.isEmpty) {
        _ctrl.text = ultima;
        _ctrl.selection =
            TextSelection(baseOffset: 0, extentOffset: ultima.length);
        setState(() => _query = ultima);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Persiste la ricerca a ogni modifica, NON in dispose: il chiamante la
  /// rilegge subito dopo il pop per i segnalini sul calendario, e il dispose
  /// della route arriva solo a transizione finita — troppo tardi. Svuotare
  /// il campo di proposito dimentica anche la memoria.
  void _salvaUltimaRicerca(String testo) {
    final q = testo.trim();
    SharedPreferences.getInstance().then((prefs) =>
        q.isEmpty ? prefs.remove(kPrefPianoTurniUltimaRicerca) : prefs.setString(kPrefPianoTurniUltimaRicerca, q));
  }

  @override
  Widget build(BuildContext context) {
    final risultati = widget.piano.cercaNome(_query);

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Cerca nome o cognome...',
            hintStyle: TextStyle(color: Colors.white38),
            border: InputBorder.none,
          ),
          // Niente debounce: la ricerca è su una lista già in memoria.
          onChanged: (v) {
            setState(() => _query = v);
            _salvaUltimaRicerca(v);
          },
        ),
      ),
      body: _query.trim().isEmpty
          ? const Center(
              child: Text(
                'Scrivi parte del nome per cercarlo nei turni del mese',
                style: TextStyle(color: Colors.white38, fontSize: 13),
              ),
            )
          : risultati.isEmpty
              ? Center(
                  child: Text(
                    'Nessun turno trovato per "${_query.trim()}"',
                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: risultati.length + 1,
                  itemBuilder: (ctx, i) {
                    if (i == 0) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          risultati.length == 1
                              ? '1 turno trovato'
                              : '${risultati.length} turni trovati',
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      );
                    }
                    return _rigaRisultato(risultati[i - 1]);
                  },
                ),
    );
  }

  Widget _rigaRisultato(SlotPiano slot) {
    final piano = widget.piano;
    final settimana =
        kGiorniSettimanaIt[DateTime(piano.anno, piano.mese, slot.giorno).weekday - 1];
    final colore = _colorePerSlot(slot);
    // Nel titolo del centralino la fascia c'è già; per gli altri il ruolo.
    final ruolo =
        slot.ruolo == RuoloPiano.centralino ? '' : ' · ${slot.ruolo.etichetta}';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colore.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colore.withValues(alpha: 0.4)),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(settimana,
                  style: TextStyle(color: colore, fontSize: 9, fontWeight: FontWeight.w600)),
              Text('${slot.giorno}',
                  style: TextStyle(color: colore, fontSize: 13, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        title: Text('${_titoloSlot(slot)}$ruolo',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text(
          [
            if (slot.titolare.isNotEmpty) 'Di turno: ${slot.titolare}',
            if (slot.sostituti.isNotEmpty) 'Sost.: ${slot.sostituti}',
          ].join(' · '),
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        onTap: () => Navigator.pop(context, slot.giorno),
      ),
    );
  }
}
