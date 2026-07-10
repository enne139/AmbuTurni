import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/magazzino_api.dart';
import '../../utils/platform_check.dart';
import '../../utils/prefs_keys.dart';
import '../../utils/theme.dart';
import 'conta_screen.dart';
import 'scanner_barcode_screen.dart';

// Colori dei movimenti: verde per il carico, rosso per lo scarico — stessi
// toni dei codici verde/rosso già usati nel resto dell'app.
const _coloreCarico = Color(0xFF4CAF50);
const _coloreScarico = Color(0xFFF44336);

/// Tool "Magazzino Verde": si collega al gestionale di magazzino esterno
/// (via la sua API JSON, header X-API-Key) e mostra le giacenze; dal tap su
/// un materiale si registra un carico o uno scarico. La configurazione
/// (URL del server + chiave API) vive in SharedPreferences ed è inclusa nel
/// backup, come le preferenze del Piano turni.
class MagazzinoScreen extends StatefulWidget {
  const MagazzinoScreen({super.key});

  @override
  State<MagazzinoScreen> createState() => _MagazzinoScreenState();
}

class _MagazzinoScreenState extends State<MagazzinoScreen> {
  MagazzinoApi? _api; // null = server non ancora configurato
  List<MaterialeMagazzino> _materiali = [];
  bool _loading = false;
  String? _errore;
  final _ricercaCtrl = TextEditingController();
  bool _soloSottoScorta = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _ricercaCtrl.dispose();
    super.dispose();
  }

  /// Se URL e chiave sono già salvati parte subito il caricamento: il caso
  /// tipico è riaprire il magazzino per controllare le scorte, non
  /// configurarlo (che si fa una volta sola).
  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final url = prefs.getString(kPrefMagazzinoUrl) ?? '';
    final key = prefs.getString(kPrefMagazzinoApiKey) ?? '';
    if (url.isEmpty || key.isEmpty || !mounted) return;
    setState(() => _api = MagazzinoApi(baseUrl: url, apiKey: key));
    await _carica();
  }

  /// Scarica la lista materiali. [silenzioso] (pull-to-refresh) non mostra lo
  /// spinner a tutto schermo e in caso d'errore segnala con uno snackbar
  /// invece di sostituire la lista già visibile — stesso pattern del refresh
  /// in sottofondo del Piano turni.
  Future<void> _carica({bool silenzioso = false}) async {
    final api = _api;
    if (api == null) return;
    if (!silenzioso) {
      setState(() {
        _loading = true;
        _errore = null;
      });
    }
    try {
      final lista = await api.getMateriali();
      if (!mounted) return;
      setState(() {
        _materiali = lista;
        _loading = false;
        _errore = null;
      });
    } catch (e) {
      if (!mounted) return;
      final messaggio = messaggioErroreMagazzino(e);
      if (silenzioso && _materiali.isNotEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(messaggio)));
      } else {
        setState(() {
          _errore = messaggio;
          _loading = false;
        });
      }
    }
  }

  /// Dialog di configurazione (URL + chiave API). Salvare con entrambi i
  /// campi vuoti scollega il tool; con la configurazione valida ricarica.
  Future<void> _configura() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final risultato = await showDialog<({String url, String apiKey})>(
      context: context,
      builder: (_) => _ConfigDialog(
        url: prefs.getString(kPrefMagazzinoUrl) ?? '',
        apiKey: prefs.getString(kPrefMagazzinoApiKey) ?? '',
      ),
    );
    if (risultato == null) return;
    await prefs.setString(kPrefMagazzinoUrl, risultato.url);
    await prefs.setString(kPrefMagazzinoApiKey, risultato.apiKey);
    if (!mounted) return;
    if (risultato.url.isEmpty || risultato.apiKey.isEmpty) {
      setState(() {
        _api = null;
        _materiali = [];
        _errore = null;
      });
      return;
    }
    setState(() {
      _api = MagazzinoApi(baseUrl: risultato.url, apiKey: risultato.apiKey);
      _materiali = [];
    });
    await _carica();
  }

  /// Bottom sheet carico/scarico: la chiamata API avviene dentro lo sheet
  /// (così un errore resta visibile lì, accanto ai pulsanti); qui si riceve
  /// il materiale aggiornato dal server e si aggiorna la sola riga toccata.
  Future<void> _movimento(MaterialeMagazzino m) async {
    final api = _api;
    if (api == null) return;
    final aggiornato = await showModalBottomSheet<MaterialeMagazzino>(
      context: context,
      isScrollControlled: true, // lo sheet deve alzarsi sopra la tastiera
      builder: (_) => _MovimentoSheet(api: api, materiale: m),
    );
    if (aggiornato == null || !mounted) return;
    setState(() {
      final idx = _materiali.indexWhere((x) => x.id == aggiornato.id);
      if (idx != -1) {
        _materiali[idx] = aggiornato;
      } else {
        // Materiale arrivato dal fallback per codice scansionato (non era
        // nella lista, es. creato dopo l'ultimo refresh): si inserisce
        // mantenendo lo stesso ordine per nome della lista scaricata.
        _materiali.add(aggiornato);
        _materiali.sort(
            (a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
      }
    });
    // Il verso del movimento si deduce dalla giacenza prima/dopo: è il dato
    // confermato dal server, non quello che l'utente credeva di inviare.
    final delta = aggiornato.giacenza - m.giacenza;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${delta >= 0 ? 'Carico' : 'Scarico'} registrato: '
          '«${aggiornato.nome}» ora ha ${aggiornato.giacenza} pezzi.'),
    ));
  }

  /// Scansione barcode/QR (solo mobile, il FAB non esiste altrove): il
  /// codice letto si cerca prima nella lista già scaricata (immediato), poi
  /// sull'endpoint per codice come fallback — copre un materiale o un codice
  /// associato dopo l'ultimo refresh. Trovato il materiale, si apre
  /// direttamente lo sheet carico/scarico: è il flusso "da magazzino"
  /// (scansiona → registra), lo stesso previsto per lo scanner del Raspberry.
  Future<void> _scansiona() async {
    final api = _api;
    if (api == null) return;
    final codice = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScannerBarcodeScreen()),
    );
    if (codice == null || codice.isEmpty || !mounted) return;
    var materiale =
        _materiali.where((m) => m.codici.contains(codice)).firstOrNull;
    if (materiale == null) {
      try {
        materiale = await api.getMaterialePerCodice(codice);
      } catch (e) {
        if (!mounted) return;
        // Il 404 qui non è un guasto: il codice esiste ma nessun materiale
        // lo ha ancora tra i suoi (si associa dall'interfaccia web).
        final nonAssociato =
            e is MagazzinoApiException && e.statusCode == 404;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(nonAssociato
              ? 'Nessun materiale ha il codice "$codice": associalo dalla '
                  'scheda del materiale nell\'interfaccia web.'
              : messaggioErroreMagazzino(e)),
        ));
        return;
      }
    }
    if (!mounted) return;
    await _movimento(materiale);
  }

  /// Lista filtrata da ricerca testuale (nome, descrizione o codice a barre:
  /// utile per digitare le ultime cifre di un codice) e dal filtro scorte.
  List<MaterialeMagazzino> get _filtrati {
    final q = _ricercaCtrl.text.trim().toLowerCase();
    return _materiali.where((m) {
      if (_soloSottoScorta && !m.sottoScorta) return false;
      if (q.isEmpty) return true;
      return m.nome.toLowerCase().contains(q) ||
          m.descrizione.toLowerCase().contains(q) ||
          m.codici.any((c) => c.contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Magazzino Verde'),
        actions: [
          // Contatore indipendente dall'API (nessun materiale selezionato,
          // nessuna giacenza toccata): sempre disponibile, anche a server
          // non configurato.
          IconButton(
            icon: const Icon(Icons.numbers),
            tooltip: 'Conta',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ContaScreen()),
            ),
          ),
          if (_api != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Ricarica',
              onPressed: _loading ? null : () => _carica(),
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Configura server',
            onPressed: _configura,
          ),
        ],
      ),
      body: _buildBody(),
      // Scansione su Android/iOS e web (mobile_scanner ha un'implementazione
      // per entrambi, via ZXing caricato a runtime sul web); non su desktop
      // nativo, dove il plugin non ha canale — a differenza di add_2_calendar
      // nel Piano turni, che sul web resta solo mobile/nessuna alternativa web.
      floatingActionButton: _api != null && !isDesktop
          ? FloatingActionButton.extended(
              onPressed: _scansiona,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scansiona'),
            )
          : null,
    );
  }

  Widget _buildBody() {
    if (_api == null) {
      return _messaggioCentrale(
          icona: Icons.warehouse_outlined,
          testo: 'Per collegarti al magazzino servono l\'indirizzo del server '
              'e una chiave API\n(si crea da Amministrazione → Chiavi API).',
          azione: 'Configura server',
          onAzione: _configura);
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_errore != null) {
      return _messaggioCentrale(
          icona: Icons.cloud_off_outlined,
          testo: _errore!,
          azione: 'Riprova',
          onAzione: () => _carica());
    }

    final filtrati = _filtrati;
    final sottoScorta = _materiali.where((m) => m.sottoScorta).length;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _ricercaCtrl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Cerca per nome, descrizione o codice...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _ricercaCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _ricercaCtrl.clear();
                        setState(() {});
                      },
                    ),
            ),
          ),
        ),
        // Il chip riprende la home del gestionale ("materiali sotto scorta"):
        // mostra il conteggio anche quando il filtro è spento.
        if (sottoScorta > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                label: Text('Sotto scorta ($sottoScorta)'),
                selected: _soloSottoScorta,
                selectedColor: _coloreScarico.withValues(alpha: 0.3),
                checkmarkColor: _coloreScarico,
                onSelected: (v) => setState(() => _soloSottoScorta = v),
              ),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _carica(silenzioso: true),
            child: filtrati.isEmpty
                // ListView anche da vuota: il pull-to-refresh deve funzionare
                // pure quando non c'è niente da mostrare.
                ? ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          _materiali.isEmpty
                              ? 'Nessun materiale nel magazzino.'
                              : 'Nessun materiale trovato coi filtri attivi.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white54),
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filtrati.length,
                    itemBuilder: (_, i) => _MaterialeCard(
                      materiale: filtrati[i],
                      onTap: () => _movimento(filtrati[i]),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  /// Stato a tutto schermo (non configurato / errore) con azione principale.
  Widget _messaggioCentrale({
    required IconData icona,
    required String testo,
    required String azione,
    required VoidCallback onAzione,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icona, size: 56, color: Colors.white38),
            const SizedBox(height: 16),
            Text(testo,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: onAzione, child: Text(azione)),
          ],
        ),
      ),
    );
  }
}

/// Card di un materiale: giacenza in evidenza a destra, rossa con etichetta
/// quando il materiale è sotto scorta (giacenza <= soglia di allerta).
class _MaterialeCard extends StatelessWidget {
  final MaterialeMagazzino materiale;
  final VoidCallback onTap;

  const _MaterialeCard({required this.materiale, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final m = materiale;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        title: Text(m.nome,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: m.descrizione.isEmpty
            ? null
            : Text(m.descrizione,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54)),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${m.giacenza}',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: m.sottoScorta ? _coloreScarico : Colors.white,
              ),
            ),
            if (m.sottoScorta)
              const Text('sotto scorta',
                  style: TextStyle(fontSize: 11, color: _coloreScarico)),
          ],
        ),
      ),
    );
  }
}

/// Dialog URL + chiave API. StatefulWidget separato (non controller creati
/// al volo nel chiamante) così i TextEditingController vengono smaltiti nel
/// dispose della route, non mentre il dialog sta ancora animando la chiusura.
class _ConfigDialog extends StatefulWidget {
  final String url;
  final String apiKey;

  const _ConfigDialog({required this.url, required this.apiKey});

  @override
  State<_ConfigDialog> createState() => _ConfigDialogState();
}

class _ConfigDialogState extends State<_ConfigDialog> {
  late final _urlCtrl = TextEditingController(text: widget.url);
  late final _keyCtrl = TextEditingController(text: widget.apiKey);

  @override
  void dispose() {
    _urlCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Server Magazzino Verde'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _urlCtrl,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'URL del server',
              hintText: 'https://magazzino.esempio.it',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _keyCtrl,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Chiave API',
              helperText: 'Si crea da Amministrazione → Chiavi API',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annulla'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, (
            url: MagazzinoApi.normalizzaUrl(_urlCtrl.text),
            apiKey: _keyCtrl.text.trim(),
          )),
          child: const Text('Salva'),
        ),
      ],
    );
  }
}

/// Bottom sheet di registrazione movimento: quantità con stepper +/- (o
/// digitata) e due pulsanti Carico/Scarico. La POST parte da qui e lo sheet
/// si chiude solo a successo, restituendo il materiale aggiornato dal
/// server: un errore (rete, chiave revocata...) resta visibile sul posto.
class _MovimentoSheet extends StatefulWidget {
  final MagazzinoApi api;
  final MaterialeMagazzino materiale;

  const _MovimentoSheet({required this.api, required this.materiale});

  @override
  State<_MovimentoSheet> createState() => _MovimentoSheetState();
}

class _MovimentoSheetState extends State<_MovimentoSheet> {
  final _qtaCtrl = TextEditingController(text: '1');
  bool _invio = false;
  String? _errore;

  @override
  void dispose() {
    _qtaCtrl.dispose();
    super.dispose();
  }

  int? get _qta => int.tryParse(_qtaCtrl.text.trim());

  void _varia(int delta) {
    final nuova = (_qta ?? 1) + delta;
    if (nuova < 1) return;
    setState(() => _qtaCtrl.text = '$nuova');
  }

  /// Invia il movimento: [segno] +1 = carico, -1 = scarico.
  Future<void> _registra(int segno) async {
    final qta = _qta;
    if (qta == null || qta < 1) {
      setState(() => _errore = 'Inserisci una quantità valida (almeno 1).');
      return;
    }
    setState(() {
      _invio = true;
      _errore = null;
    });
    try {
      final aggiornato =
          await widget.api.registraMovimento(widget.materiale.id, segno * qta);
      if (mounted) Navigator.pop(context, aggiornato);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _invio = false;
        _errore = messaggioErroreMagazzino(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.materiale;
    return Padding(
      // Il padding sul viewInsets alza lo sheet sopra la tastiera quando si
      // digita la quantità (altrimenti i pulsanti resterebbero coperti).
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(m.nome,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                'Giacenza attuale: ${m.giacenza}'
                '${m.sottoScorta ? ' (sotto scorta, soglia ${m.allerta})' : ''}',
                style: TextStyle(
                    color: m.sottoScorta ? _coloreScarico : Colors.white54),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, size: 32),
                    onPressed: _invio ? null : () => _varia(-1),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _qtaCtrl,
                      enabled: !_invio,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.bold),
                      decoration:
                          const InputDecoration(labelText: 'Quantità'),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, size: 32),
                    onPressed: _invio ? null : () => _varia(1),
                  ),
                ],
              ),
              if (_errore != null) ...[
                const SizedBox(height: 12),
                Text(_errore!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: kPrimary)),
              ],
              const SizedBox(height: 20),
              if (_invio)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _coloreScarico),
                        icon: const Icon(Icons.remove),
                        label: const Text('Scarico'),
                        onPressed: () => _registra(-1),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: _coloreCarico),
                        icon: const Icon(Icons.add),
                        label: const Text('Carico'),
                        onPressed: () => _registra(1),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
