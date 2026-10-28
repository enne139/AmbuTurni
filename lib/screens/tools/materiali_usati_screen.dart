import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../db/helpers.dart';
import '../../db/models.dart';
import '../../providers/app_provider.dart';
import '../../utils/backend_api.dart';
import '../../utils/materiali_condivisi.dart';
import '../../utils/prefs_keys.dart';
import '../../utils/theme.dart';
import '../../widgets/accesso_richiesto.dart';
import 'materiale_usato_form.dart';
import 'materiali_screen.dart';

// Valore del selettore mezzo per "tutti i mezzi": stringa vuota invece di
// null, così il DropdownButton ha sempre un valore non nullo che
// corrisponde a esattamente una voce. Non collide con un mezzo vero (i
// nomi sono sempre due cifre).
const _kTuttiIMezzi = '';

/// Lista dei materiali usati non ancora ripristinati. Il tocco sul check
/// segna la riga come ripristinata (la elimina: nessuno storico); lo swipe
/// la elimina del tutto (es. inserimento per errore).
///
/// UNA sola lista con i materiali locali (solo su questo device) e quelli
/// condivisi da tutti sul backend condiviso, mescolati per data: chi
/// ricarica il mezzo vede in un posto solo tutto ciò che manca. Sotto
/// l'AppBar due controlli sempre visibili, richiesta esplicita dell'utente:
/// il selettore del MEZZO (filtra la lista e precompila i materiali nuovi)
/// e l'interruttore CONDIVIDI, che decide solo dove finisce il prossimo
/// materiale aggiunto — non cambia ciò che si vede (una prima versione lo
/// usava per passare tra due liste separate, scartata dall'utente: due
/// posti da guardare per sapere cosa manca). I condivisi richiedono il
/// login utente-app: senza, si vedono solo i locali e un avviso per
/// accedere; chiunque abbia l'accesso può modificarli o ripristinarli
/// (chi ricarica il mezzo di solito non è chi ha usato il materiale).
///
/// Catalogo materiali e mezzi si scaricano da soli all'apertura (e col
/// trascinamento verso il basso), senza più il pulsante manuale: prima un
/// materiale nuovo aggiunto sul backend compariva nel picker solo se
/// qualcuno si ricordava di premerlo.
class MaterialiUsatiScreen extends StatefulWidget {
  const MaterialiUsatiScreen({super.key});

  @override
  State<MaterialiUsatiScreen> createState() => _MaterialiUsatiScreenState();
}

/// Una riga della lista mista: esattamente uno dei due campi è valorizzato
/// (MaterialeUsato e MaterialeUsatoCondiviso sono classi diverse, con id
/// del materiale e campi diversi).
class _Voce {
  final MaterialeUsato? locale;
  final MaterialeUsatoCondiviso? condiviso;
  const _Voce.locale(MaterialeUsato this.locale) : condiviso = null;
  const _Voce.condivisa(MaterialeUsatoCondiviso this.condiviso) : locale = null;

  // updatedAt come ripiego per le righe locali salvate prima della
  // correzione di saveMaterialeUsato, rimaste con created_at NULL.
  DateTime? get data =>
      condiviso?.createdAt ?? DateTime.tryParse(locale?.createdAt ?? locale?.updatedAt ?? '');
}

class _MaterialiUsatiScreenState extends State<MaterialiUsatiScreen> {
  List<MaterialeUsato> _locali = [];
  bool _loadingLocali = true;

  List<String> _mezzi = [];
  String? _mezzo; // null = tutti i mezzi
  // Preferenza dell'interruttore: i nuovi materiali vanno condivisi. Vale
  // solo con il login fatto (vedi _condividiAttivo in build): dopo un
  // logout l'interruttore appare spento, e torna acceso al login successivo.
  bool _condividi = false;

  List<MaterialeUsatoCondiviso> _listaCondivisi = [];
  bool _loadingCondivisi = false;
  String? _erroreCondivisi;
  // Token con cui è stata caricata _listaCondivisi: un login (o un cambio
  // di account) lo rende diverso da quello attuale e fa ricaricare la
  // lista da build(), senza dover intercettare ogni punto in cui
  // AccountProvider cambia stato.
  String? _tokenCaricato;
  // Contatore per riga delle variazioni +/- inviate: con più tocchi rapidi
  // le risposte possono arrivare in ordine diverso, e solo l'ultima
  // inviata deve aggiornare il numero mostrato.
  final Map<String, int> _seqQuantita = {};

  @override
  void initState() {
    super.initState();
    _avvia();
  }

  Future<void> _avvia() async {
    final prefs = await SharedPreferences.getInstance();
    final mezzo = prefs.getString(kPrefMaterialiMezzo);
    if (mounted) {
      setState(() {
        _mezzi = nomiMezzi(prefs.getStringList(kPrefMezziCache) ?? const []);
        _mezzo = (mezzo != null && nomeMezzoValido(mezzo)) ? mezzo : null;
        _condividi = prefs.getBool(kPrefMaterialiCondivisi) ?? false;
      });
    }
    await _caricaLocali();
    // Silenziosa: offline o con un backend vecchio senza /api/mezzi il tool
    // deve restare usabile coi dati locali, senza errori all'apertura
    // (stesso criterio della sincronizzazione fogli del Piano turni).
    try {
      await _sincronizzaDalBackend();
    } catch (_) {}
  }

  Future<BackendApi> _api() async {
    final prefs = await SharedPreferences.getInstance();
    return BackendApi(baseUrl: prefs.getString(kPrefBackendUrl) ?? kBackendUrlDefault);
  }

  Future<void> _caricaLocali() async {
    final lista = await getMaterialiUsati();
    if (mounted) setState(() { _locali = lista; _loadingLocali = false; });
  }

  /// Scarica catalogo materiali (upsert per nome nel catalogo locale, come
  /// faceva il vecchio pulsante) e mezzi (cache in SharedPreferences, per
  /// avere il selettore pieno anche offline). Lancia il primo errore dopo
  /// aver comunque tentato entrambe: un catalogo irraggiungibile non deve
  /// impedire di aggiornare i mezzi, e viceversa.
  Future<void> _sincronizzaDalBackend() async {
    final api = await _api();
    Object? errore;
    try {
      await upsertMateriali(await api.getMateriali());
    } catch (e) {
      errore = e;
    }
    try {
      final mezzi = await api.getMezzi();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(kPrefMezziCache, mezzi);
      if (mounted) {
        setState(() => _mezzi = mezzi);
        // Mezzo scelto tolto dal backend nel frattempo: si torna a "tutti"
        // invece di filtrare per un mezzo che non esiste più. Solo con un
        // elenco non vuoto: un backend senza mezzi configurati non deve
        // azzerare la scelta fatta.
        if (_mezzo != null && mezzi.isNotEmpty && !mezzi.contains(_mezzo)) {
          await _setMezzo(_kTuttiIMezzi);
        }
      }
    } catch (e) {
      errore ??= e;
    }
    if (errore != null) throw errore;
  }

  Future<void> _caricaCondivisi(String token) async {
    setState(() {
      _loadingCondivisi = true;
      _erroreCondivisi = null;
    });
    try {
      final lista = await (await _api()).getMaterialiCondivisi(token: token);
      if (mounted) setState(() { _listaCondivisi = lista; _loadingCondivisi = false; });
    } on BackendApiUnauthorized {
      if (mounted) await context.read<AccountProvider>().logout();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingCondivisi = false;
          _erroreCondivisi = messaggioErroreBackend(e);
        });
      }
    }
  }

  /// Trascinamento verso il basso: ri-sincronizza catalogo e mezzi e
  /// ricarica entrambe le sorgenti della lista. L'errore del catalogo si
  /// mostra (a differenza dell'apertura: è un'azione esplicita) solo senza
  /// login — con il login, una rete assente compare già nell'avviso dei
  /// condivisi, due messaggi per la stessa causa sarebbero ridondanti.
  Future<void> _aggiorna(String? token) async {
    try {
      await _sincronizzaDalBackend();
    } catch (e) {
      if (mounted && token == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Catalogo non aggiornato: ${messaggioErroreBackend(e)}')),
        );
      }
    }
    await _caricaLocali();
    if (token != null && mounted) await _caricaCondivisi(token);
  }

  Future<void> _setMezzo(String valore) async {
    final mezzo = valore == _kTuttiIMezzi ? null : valore;
    setState(() => _mezzo = mezzo);
    final prefs = await SharedPreferences.getInstance();
    if (mezzo == null) {
      await prefs.remove(kPrefMaterialiMezzo);
    } else {
      await prefs.setString(kPrefMaterialiMezzo, mezzo);
    }
  }

  /// Accendere l'interruttore senza login apre prima l'accesso: condividere
  /// senza un account non è possibile, e lasciarlo acceso "a vuoto"
  /// farebbe credere di condividere ciò che finisce invece solo in locale.
  Future<void> _setCondividi(bool valore, {required bool loggato}) async {
    if (valore && !loggato && !await _apriAccesso()) return;
    setState(() => _condividi = valore);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kPrefMaterialiCondivisi, valore);
  }

  /// Apre la pagina di login; true se al ritorno l'accesso è completo
  /// (anche l'eventuale cambio password obbligatorio).
  Future<bool> _apriAccesso() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const _AccessoCondivisiScreen()));
    if (!mounted) return false;
    final account = context.read<AccountProvider>();
    return account.loggedIn && !account.deveCambiarePassword;
  }

  // ---------------------------------------------------------------------
  // Azioni sui materiali LOCALI
  // ---------------------------------------------------------------------

  Future<void> _ripristinaLocale(MaterialeUsato mu) async {
    if (!await _confermaRipristino(mu.materialeNome ?? '—', mu.quantitaLabel)) return;
    await segnaMaterialeRipristinato(mu.id);
    if (mounted) _caricaLocali();
  }

  /// Variazione rapida della quantità (+/- in lista): aggiorna prima lo stato
  /// locale per una risposta immediata, poi persiste sul DB in background.
  /// Se la scrittura fallisce, la riga torna al valore precedente invece di
  /// restare con una quantità mai davvero salvata.
  Future<void> _variaQuantitaLocale(MaterialeUsato mu, int delta) async {
    final nuova = mu.quantita + delta;
    if (nuova < 1) return;
    final idx = _locali.indexWhere((m) => m.id == mu.id);
    if (idx == -1) return;
    setState(() => _locali[idx] = mu.copyWith(quantita: nuova));
    try {
      await aggiornaQuantitaMaterialeUsato(mu.id, nuova);
    } catch (e) {
      if (mounted) {
        setState(() => _locali[idx] = mu);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore durante il salvataggio: $e')),
        );
      }
    }
  }

  // ---------------------------------------------------------------------
  // Azioni sui materiali CONDIVISI
  // ---------------------------------------------------------------------

  /// Gestione comune degli errori delle chiamate sui condivisi: 401 →
  /// logout (restano i locali e l'avviso per accedere), 404 → qualcun altro
  /// l'aveva già ripristinato (si ricarica, niente errore), il resto in
  /// snackbar.
  Future<void> _gestisciErroreCondivisi(Object e, String token) async {
    if (!mounted) return;
    if (e is BackendApiUnauthorized) {
      await context.read<AccountProvider>().logout();
      return;
    }
    final messaggio = e is BackendApiNotFound
        ? 'Già ripristinato da qualcun altro.'
        : messaggioErroreBackend(e);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(messaggio)));
    await _caricaCondivisi(token);
  }

  Future<void> _ripristinaCondiviso(MaterialeUsatoCondiviso mu, String token, {bool chiediConferma = true}) async {
    if (chiediConferma && !await _confermaRipristino(mu.materiale, mu.quantitaLabel)) return;
    try {
      final eliminati = await (await _api()).ripristinaMaterialiCondivisi(token: token, ids: [mu.id]);
      if (!mounted) return;
      if (eliminati == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Era già stato ripristinato da qualcun altro.')),
        );
      }
      await _caricaCondivisi(token);
    } catch (e) {
      await _gestisciErroreCondivisi(e, token);
    }
  }

  /// Come _variaQuantitaLocale (aggiornamento ottimistico), ma la richiesta
  /// porta il DELTA: il valore vero lo calcola il server sommando anche i
  /// tocchi di altri volontari, e la riga restituita sostituisce quella
  /// ottimistica — se è la risposta all'ultimo tocco inviato su quella riga.
  Future<void> _variaQuantitaCondiviso(MaterialeUsatoCondiviso mu, int delta, String token) async {
    final nuova = mu.quantita + delta;
    if (nuova < 1) return;
    final idx = _listaCondivisi.indexWhere((m) => m.id == mu.id);
    if (idx == -1) return;
    setState(() => _listaCondivisi[idx] = mu.copyWith(quantita: nuova));
    final seq = (_seqQuantita[mu.id] ?? 0) + 1;
    _seqQuantita[mu.id] = seq;
    try {
      final aggiornato = await (await _api())
          .variaQuantitaMaterialeCondiviso(token: token, id: mu.id, delta: delta);
      if (!mounted || _seqQuantita[mu.id] != seq) return;
      final i = _listaCondivisi.indexWhere((m) => m.id == mu.id);
      if (i != -1) setState(() => _listaCondivisi[i] = aggiornato);
    } catch (e) {
      // Il valore ottimistico non è più affidabile: si rilegge dal server.
      await _gestisciErroreCondivisi(e, token);
    }
  }

  // ---------------------------------------------------------------------
  // Comuni
  // ---------------------------------------------------------------------

  Future<bool> _confermaRipristino(String nome, String quantita) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Segna come ripristinato'),
        content: Text('"$nome" ($quantita) è stato ripristinato?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sì, ripristinato')),
        ],
      ),
    );
    return ok == true && mounted;
  }

  /// "Ripristina tutto": solo ciò che la lista mostra (mezzo scelto), mai
  /// i materiali degli altri mezzi; per i condivisi l'elenco di id va al
  /// server così una riga aggiunta da altri nel frattempo, mai vista, resta.
  Future<void> _ripristinaTutto(List<_Voce> voci, String? token) async {
    final locali = [for (final v in voci) if (v.locale != null) v.locale!.id];
    final condivisi = [for (final v in voci) if (v.condiviso != null) v.condiviso!.id];
    final suMezzo = _mezzo == null ? '' : ' del mezzo $_mezzo';
    final perTutti = condivisi.isEmpty
        ? ''
        : condivisi.length == 1
            ? ' Quello condiviso sparisce per tutti.'
            : ' I ${condivisi.length} condivisi spariscono per tutti.';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ripristina tutto'),
        content: Text('Segnare come ripristinati tutti i ${voci.length} materiali in lista$suMezzo?$perTutti'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sì, ripristina tutto')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await segnaMaterialiRipristinati(locali);
    if (mounted) await _caricaLocali();
    if (condivisi.isNotEmpty && token != null) {
      try {
        await (await _api()).ripristinaMaterialiCondivisi(token: token, ids: condivisi);
        if (mounted) await _caricaCondivisi(token);
      } catch (e) {
        await _gestisciErroreCondivisi(e, token);
      }
    }
  }

  /// Un materiale esistente si modifica dove vive (locale o condiviso),
  /// indipendentemente dall'interruttore; uno nuovo va dove dice
  /// l'interruttore ([token] non nullo = condiviso).
  Future<void> _apriForm({MaterialeUsato? locale, MaterialeUsatoCondiviso? condiviso, String? token}) async {
    final accesso = token == null ? null : (api: await _api(), token: token);
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => MaterialeUsatoForm(
      esistente: locale,
      esistenteCondiviso: condiviso,
      condiviso: accesso,
      mezzi: _mezzi,
      mezzoIniziale: _mezzo,
    )));
    if (!mounted) return;
    if (token == null) {
      _caricaLocali();
    } else if (context.read<AccountProvider>().token == token) {
      _caricaCondivisi(token);
    }
  }

  /// Locali + condivisi (solo con il login) del mezzo scelto, dal più
  /// recente: la stessa lista qualunque sia la posizione dell'interruttore.
  List<_Voce> _vociVisibili(String? token) {
    final voci = [
      for (final m in filtraPerMezzo(_locali, _mezzo, (m) => m.mezzo)) _Voce.locale(m),
      if (token != null)
        for (final m in filtraPerMezzo(_listaCondivisi, _mezzo, (m) => m.mezzo)) _Voce.condivisa(m),
    ];
    final senzaData = DateTime.fromMillisecondsSinceEpoch(0);
    voci.sort((a, b) => (b.data ?? senzaData).compareTo(a.data ?? senzaData));
    return voci;
  }

  @override
  Widget build(BuildContext context) {
    final account = context.watch<AccountProvider>();
    final accessoOk = account.caricato && account.loggedIn && !account.deveCambiarePassword;
    final token = accessoOk ? account.token : null;
    if (token == null) {
      // Logout: i condivisi dell'account precedente non vanno più mostrati.
      _tokenCaricato = null;
      _listaCondivisi = [];
      _erroreCondivisi = null;
      _loadingCondivisi = false;
    } else if (token != _tokenCaricato) {
      _tokenCaricato = token;
      // Già in caricamento da questo frame (senza setState: siamo in build).
      _loadingCondivisi = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _caricaCondivisi(token);
      });
    }
    final condividiAttivo = _condividi && token != null;
    final voci = _vociVisibili(token);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Materiali usati'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_note),
            tooltip: 'Gestisci materiali',
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const MaterialiScreen()));
              if (mounted) _caricaLocali();
            },
          ),
          if (voci.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.done_all),
              tooltip: 'Ripristina tutto',
              onPressed: () => _ripristinaTutto(voci, token),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: _barraSelettori(context, condividiAttivo: condividiAttivo, loggato: token != null),
        ),
      ),
      body: _loadingLocali
          ? const Center(child: CircularProgressIndicator())
          : _corpo(context, voci, token: token, accountCaricato: account.caricato),
      floatingActionButton: FloatingActionButton(
        tooltip: condividiAttivo ? 'Condividi un materiale usato' : 'Segna un materiale usato',
        onPressed: () => _apriForm(token: condividiAttivo ? token : null),
        child: const Icon(Icons.add),
      ),
    );
  }

  /// Riga sotto l'AppBar: selettore del mezzo a sinistra, interruttore
  /// "Condividi" a destra.
  Widget _barraSelettori(BuildContext context, {required bool condividiAttivo, required bool loggato}) {
    final voci = {..._mezzi, if (_mezzo != null) _mezzo!}.toList()..sort();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
      child: Row(children: [
        Icon(Icons.airport_shuttle_outlined, size: 20, color: coloreTesto(context, 0.7)),
        const SizedBox(width: 8),
        DropdownButton<String>(
          value: _mezzo ?? _kTuttiIMezzi,
          underline: const SizedBox.shrink(),
          borderRadius: BorderRadius.circular(8),
          items: [
            const DropdownMenuItem(value: _kTuttiIMezzi, child: Text('Tutti i mezzi')),
            for (final m in voci) DropdownMenuItem(value: m, child: Text('Mezzo $m')),
          ],
          onChanged: (v) {
            if (v != null) _setMezzo(v);
          },
        ),
        const Spacer(),
        Icon(Icons.groups_outlined, size: 20, color: condividiAttivo ? kPrimary : coloreTesto(context, 0.54)),
        const SizedBox(width: 6),
        Text('Condividi', style: TextStyle(color: coloreTesto(context, condividiAttivo ? 1 : 0.7))),
        Switch(value: condividiAttivo, onChanged: (v) => _setCondividi(v, loggato: loggato)),
      ]),
    );
  }

  Widget _corpo(BuildContext context, List<_Voce> voci, {required String? token, required bool accountCaricato}) {
    final formatoData = DateFormat('dd/MM HH:mm');
    final intestazioni = <Widget>[
      if (token == null && accountCaricato)
        _Avviso(
          icona: Icons.lock_outline,
          testo: 'Accedi per vedere anche i materiali condivisi da tutti e condividere i tuoi.',
          azione: 'Accedi',
          // Solo l'accesso: l'interruttore resta com'era, condividere i
          // prossimi materiali è una scelta a parte.
          onAzione: _apriAccesso,
        ),
      if (_erroreCondivisi != null && token != null)
        _Avviso(
          icona: Icons.cloud_off_outlined,
          testo: 'Materiali condivisi non disponibili: $_erroreCondivisi',
          azione: 'Riprova',
          onAzione: () => _caricaCondivisi(token),
        ),
    ];

    return Column(children: [
      // Caricamento dei condivisi in corso: i locali sono già in lista,
      // basta un indicatore sottile invece di bloccare tutto con uno spinner.
      if (_loadingCondivisi) const LinearProgressIndicator(minHeight: 2),
      Expanded(
        child: RefreshIndicator(
          onRefresh: () => _aggiorna(token),
          // ListView anche a lista vuota: senza, il trascinamento verso il
          // basso per aggiornare non funzionerebbe.
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
            children: [
              ...intestazioni,
              if (voci.isEmpty && !_loadingCondivisi) _vuoto(context),
              for (final v in voci)
                if (v.locale != null) _cardLocale(v.locale!) else _cardCondivisa(v.condiviso!, token!, formatoData),
            ],
          ),
        ),
      ),
    ]);
  }

  Widget _cardLocale(MaterialeUsato mu) => _MaterialeCard(
        key: ValueKey('l-${mu.id}'),
        id: mu.id,
        nome: mu.materialeNome ?? '—',
        quantitaLabel: mu.quantitaLabel,
        dettagli: _dettagli(mu.posizione, mu.mezzo, mu.note),
        puoDiminuire: mu.quantita > 1,
        onMeno: () => _variaQuantitaLocale(mu, -1),
        onPiu: () => _variaQuantitaLocale(mu, 1),
        onModifica: () => _apriForm(locale: mu),
        onRipristina: () => _ripristinaLocale(mu),
        onElimina: () async {
          // Tolta subito dalla lista: una card già "swipata" che resta
          // nell'albero fino al ricaricamento manda in errore il
          // Dismissible al primo rebuild.
          setState(() => _locali.removeWhere((m) => m.id == mu.id));
          await deleteMaterialeUsato(mu.id);
          if (mounted) _caricaLocali();
        },
      );

  Widget _cardCondivisa(MaterialeUsatoCondiviso mu, String token, DateFormat formatoData) {
    final quando = mu.createdAt == null ? '' : ' · ${formatoData.format(mu.createdAt!)}';
    return _MaterialeCard(
      key: ValueKey('c-${mu.id}'),
      id: mu.id,
      nome: mu.materiale,
      quantitaLabel: mu.quantitaLabel,
      dettagli: _dettagli(mu.posizione, mu.mezzo, mu.note),
      condiviso: true,
      autore: mu.creatoDa.isEmpty ? 'Condiviso$quando' : 'Condiviso da ${mu.creatoDa}$quando',
      puoDiminuire: mu.quantita > 1,
      onMeno: () => _variaQuantitaCondiviso(mu, -1, token),
      onPiu: () => _variaQuantitaCondiviso(mu, 1, token),
      onModifica: () => _apriForm(condiviso: mu, token: token),
      onRipristina: () => _ripristinaCondiviso(mu, token),
      // Lo swipe ha già la sua conferma ("Elimina riga"); riga tolta subito
      // come in locale (qui c'è la rete in mezzo, a maggior ragione), un
      // errore la fa ricomparire col ricaricamento.
      onElimina: () {
        setState(() => _listaCondivisi.removeWhere((m) => m.id == mu.id));
        _ripristinaCondiviso(mu, token, chiediConferma: false);
      },
    );
  }

  /// Riga secondaria della card: posizione, mezzo (solo con "Tutti i
  /// mezzi": col filtro attivo sarebbe uguale su ogni riga) e note.
  String? _dettagli(String? posizione, String? mezzo, String? note) {
    final parti = [
      if (posizione != null) posizione,
      if (_mezzo == null && mezzo != null) 'Mezzo $mezzo',
      if (note != null) note,
    ];
    return parti.isEmpty ? null : parti.join(' · ');
  }

  Widget _vuoto(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: MediaQuery.of(context).size.height * 0.15),
      child: Column(children: [
        Icon(Icons.inventory_2_outlined, size: 64, color: coloreTesto(context, 0.24)),
        const SizedBox(height: 16),
        Text(
          _mezzo == null ? 'Nessun materiale da ripristinare' : 'Nessun materiale da ripristinare sul mezzo $_mezzo',
          textAlign: TextAlign.center,
          style: TextStyle(color: coloreTesto(context, 0.54)),
        ),
        const SizedBox(height: 8),
        Text('Tocca + per segnarne uno usato',
            textAlign: TextAlign.center, style: TextStyle(color: coloreTesto(context, 0.38), fontSize: 13)),
      ]),
    );
  }
}

/// Avviso in testa alla lista (login mancante, condivisi non raggiungibili)
/// con un'azione: dentro la lista e non a schermo intero, perché i
/// materiali locali restano comunque consultabili sotto.
class _Avviso extends StatelessWidget {
  final IconData icona;
  final String testo;
  final String azione;
  final VoidCallback onAzione;

  const _Avviso({required this.icona, required this.testo, required this.azione, required this.onAzione});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        child: Row(children: [
          Icon(icona, size: 20, color: coloreTesto(context, 0.54)),
          const SizedBox(width: 12),
          Expanded(child: Text(testo, style: TextStyle(color: coloreTesto(context, 0.7), fontSize: 13))),
          TextButton(onPressed: onAzione, child: Text(azione)),
        ]),
      ),
    );
  }
}

/// Pagina di login aperta dall'interruttore "Condividi" (o dall'avviso in
/// lista) senza un accesso attivo: stesso AccessoRichiesto dei contenuti
/// riservati (login + eventuale cambio password obbligatorio), che si
/// chiude da sola appena l'accesso è completo.
class _AccessoCondivisiScreen extends StatefulWidget {
  const _AccessoCondivisiScreen();

  @override
  State<_AccessoCondivisiScreen> createState() => _AccessoCondivisiScreenState();
}

class _AccessoCondivisiScreenState extends State<_AccessoCondivisiScreen> {
  // Il builder di AccessoRichiesto può essere richiamato più volte prima
  // che la pagina sparisca: senza questa guardia ogni build farebbe un pop.
  bool _chiusa = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Accedi per condividere')),
      body: AccessoRichiesto(builder: (ctx, token) {
        if (!_chiusa) {
          _chiusa = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.pop(context);
          });
        }
        return const SizedBox.shrink();
      }),
    );
  }
}

/// Card di un materiale usato, condivisa tra materiali locali e condivisi
/// (MaterialeUsato e MaterialeUsatoCondiviso sono classi diverse: qui
/// arrivano solo i testi già pronti e le azioni). Swipe = elimina, con
/// conferma. I condivisi hanno l'icona del gruppo accanto al nome, per
/// distinguerli a colpo d'occhio nella lista mista.
class _MaterialeCard extends StatelessWidget {
  final String id;
  final String nome;
  final String quantitaLabel;
  final String? dettagli;
  final bool condiviso;
  final String? autore;
  final bool puoDiminuire;
  final VoidCallback onMeno;
  final VoidCallback onPiu;
  final VoidCallback onModifica;
  final VoidCallback onRipristina;
  final VoidCallback onElimina;

  const _MaterialeCard({
    super.key,
    required this.id,
    required this.nome,
    required this.quantitaLabel,
    this.dettagli,
    this.condiviso = false,
    this.autore,
    required this.puoDiminuire,
    required this.onMeno,
    required this.onPiu,
    required this.onModifica,
    required this.onRipristina,
    required this.onElimina,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => showDialog<bool>(
        context: context,
        builder: (dctx) => AlertDialog(
          title: const Text('Elimina riga'),
          content: Text('Eliminare "$nome" ($quantitaLabel)?${condiviso ? ' Sparisce per tutti.' : ''}'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Annulla')),
            TextButton(
              onPressed: () => Navigator.pop(dctx, true),
              child: const Text('Elimina', style: TextStyle(color: kPrimary)),
            ),
          ],
        ),
      ),
      onDismissed: (_) => onElimina(),
      background: Container(
        margin: const EdgeInsets.only(bottom: 10),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: kPrimary.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.delete, color: coloreTesto(context)),
      ),
      child: Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(children: [
            // Stepper +/- con la quantità in evidenza al centro: stesso
            // stile del badge "#numero" usato nelle card di turni/assistenze,
            // ma qui interattivo per un ritocco rapido durante il turno.
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, size: 20),
              color: coloreTesto(context, 0.38),
              visualDensity: VisualDensity.compact,
              onPressed: puoDiminuire ? onMeno : null,
            ),
            Container(
              constraints: const BoxConstraints(minWidth: 48),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kPrimary.withValues(alpha: 0.4)),
              ),
              alignment: Alignment.center,
              child: Text(quantitaLabel,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: kPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline, size: 20),
              color: coloreTesto(context, 0.38),
              visualDensity: VisualDensity.compact,
              onPressed: onPiu,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  if (condiviso) ...[
                    const Icon(Icons.groups_outlined, size: 16, color: kPrimary),
                    const SizedBox(width: 4),
                  ],
                  Flexible(child: Text(nome, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
                ]),
                if (dettagli != null)
                  Text(dettagli!, style: TextStyle(color: coloreTesto(context, 0.54), fontSize: 12)),
                if (autore != null)
                  Text(autore!, style: TextStyle(color: coloreTesto(context, 0.38), fontSize: 11)),
              ]),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              color: coloreTesto(context, 0.38),
              visualDensity: VisualDensity.compact,
              tooltip: 'Modifica',
              onPressed: onModifica,
            ),
            IconButton(
              icon: const Icon(Icons.check_circle_outline),
              color: coloreTesto(context, 0.38),
              tooltip: 'Segna come ripristinato',
              onPressed: onRipristina,
            ),
          ]),
        ),
      ),
    );
  }
}
