import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../db/backup_file.dart';
import '../../providers/app_provider.dart';
import '../../utils/backend_api.dart';
import '../../utils/comunicati.dart';
import '../../utils/format.dart';
import '../../utils/prefs_keys.dart';
import '../../utils/theme.dart';
import '../../widgets/accesso_richiesto.dart';

/// Tool "Archivio comunicati": elenco degli avvisi (PDF) caricati
/// dall'admin sulla pagina admin del backend condiviso. CONTENUTO
/// RISERVATO (vedi CLAUDE.md), come Repository formazione: il body è
/// avvolto in AccessoRichiesto, che mostra login/cambio password finché
/// l'utente non è autenticato.
class ArchivioComunicatiScreen extends StatelessWidget {
  const ArchivioComunicatiScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Archivio comunicati')),
      body: AccessoRichiesto(
        builder: (context, token) => _ArchivioComunicatiContenuto(token: token),
      ),
    );
  }
}

/// Contenuto vero del tool, mostrato solo a login effettuato. Nessuna
/// cache locale (come Repository formazione): sempre online, niente bump di
/// versione DB per questa funzionalità.
class _ArchivioComunicatiContenuto extends StatefulWidget {
  final String token;
  const _ArchivioComunicatiContenuto({required this.token});

  @override
  State<_ArchivioComunicatiContenuto> createState() => _ArchivioComunicatiContenutoState();
}

class _ArchivioComunicatiContenutoState extends State<_ArchivioComunicatiContenuto> {
  bool _loading = true;
  List<Map<String, dynamic>> _comunicati = [];
  String? _errore;
  // id del comunicato in apertura: disabilita solo quella riga, non
  // l'intera lista.
  String? _aprendoId;
  // Ricerca e filtro tag: puro stato di visualizzazione della sessione, non
  // persistito (a differenza di Piano turni la lista è già tutta in memoria
  // e cambia raramente, non serve ricordare l'ultimo filtro tra i riavvii).
  final _ricercaCtrl = TextEditingController();
  final Set<String> _tagSelezionati = {};

  @override
  void dispose() {
    _ricercaCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _carica();
  }

  Future<String> _backendUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(kPrefBackendUrl) ?? kBackendUrlDefault;
  }

  Future<void> _carica() async {
    setState(() {
      _loading = true;
      _errore = null;
    });
    try {
      final lista = await BackendApi(baseUrl: await _backendUrl()).getComunicati(token: widget.token);
      if (!mounted) return;
      setState(() {
        _comunicati = lista;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // Token scaduto/revocato: logout automatico, stesso motivo di
      // Repository formazione — AccessoRichiesto rimonta il login al posto
      // di questo widget, nessun setState locale da fare.
      if (e is BackendApiUnauthorized) {
        context.read<AccountProvider>().logout();
        return;
      }
      setState(() {
        _loading = false;
        _errore = messaggioErroreBackend(e);
      });
    }
  }

  /// Apre il PDF (visualizzazione) invece di forzarne il download — vedi
  /// apriFileBinarioPiattaforma in db/backup_file.dart per il comportamento
  /// per piattaforma (nuova scheda del browser su web, app predefinita su
  /// desktop, share sheet come ripiego su mobile). Il download vero e
  /// proprio (getComunicatoFile) è dentro la callback passata a quella
  /// funzione, MAI atteso qui prima di chiamarla: su web la finestra va
  /// aperta come primissima cosa, ancora sincrona rispetto al tap
  /// dell'utente, altrimenti il browser la blocca come popup non richiesto
  /// (vedi i commenti in backup_file_web.dart).
  Future<void> _apri(Map<String, dynamic> comunicato) async {
    final id = comunicato['id'] as String?;
    if (id == null) return;
    final nomeFile = (comunicato['fileName'] as String?) ?? '$id.pdf';
    setState(() => _aprendoId = id);
    try {
      await apriFileBinarioPiattaforma(
        () async => BackendApi(baseUrl: await _backendUrl()).getComunicatoFile(token: widget.token, id: id),
        nomeFile,
        'application/pdf',
      );
    } catch (e) {
      if (!mounted) return;
      if (e is BackendApiUnauthorized) {
        context.read<AccountProvider>().logout();
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Errore: ${messaggioErroreBackend(e)}')));
    } finally {
      if (mounted) setState(() => _aprendoId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_errore != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wifi_off, size: 48, color: coloreTesto(context, 0.38)),
              const SizedBox(height: 16),
              Text('Impossibile contattare il server condiviso.\n$_errore',
                  textAlign: TextAlign.center, style: TextStyle(color: coloreTesto(context, 0.7))),
              const SizedBox(height: 20),
              OutlinedButton(onPressed: _carica, child: const Text('Riprova')),
            ],
          ),
        ),
      );
    }
    // Tag disponibili calcolati sull'intero elenco scaricato (non su quello
    // già filtrato): altrimenti selezionare un tag farebbe sparire gli
    // altri chip che non co-occorrono con quello scelto, impedendo di
    // allargare di nuovo la selezione senza prima deselezionare tutto.
    final tagDisponibili = tuttiTag(_comunicati);
    final filtrati = filtraComunicati(_comunicati, ricerca: _ricercaCtrl.text, tag: _tagSelezionati);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _ricercaCtrl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Cerca per nome file o titolo...',
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
        // I chip tag compaiono solo se esiste almeno un comunicato taggato:
        // niente riga vuota finché l'admin non ne ha ancora usati. Una sola
        // riga, scorrevole in orizzontale (richiesta esplicita, dopo che il
        // tentativo a due righe non si comportava in modo affidabile sui
        // device reali) — nessuna altezza da calcolare, la riga si
        // dimensiona da sola sull'altezza naturale del chip.
        if (tagDisponibili.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < tagDisponibili.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    _chipTag(tagDisponibili[i]),
                  ],
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        // RefreshIndicator su entrambi i rami (vuoto/pieno): serve comunque
        // una ListView scrollabile perché il pull-to-refresh funzioni anche
        // a lista vuota (un Center da solo non è "trascinabile").
        Expanded(
          child: RefreshIndicator(
            onRefresh: _carica,
            child: filtrati.isEmpty
                ? ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 80),
                        child: Center(
                          child: Text(
                            _comunicati.isEmpty
                                ? 'Nessun comunicato disponibile al momento.'
                                : 'Nessun comunicato corrisponde alla ricerca.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: coloreTesto(context, 0.54)),
                          ),
                        ),
                      ),
                    ],
                  )
                : _buildListaRaggruppata(filtrati),
          ),
        ),
      ],
    );
  }

  /// Un'unica archivio cronologico, raggruppato per mese (vedi
  /// _raggruppaPerMese sopra) invece di una lista piatta: i comunicati si
  /// accumulano nel tempo, senza intestazioni diventerebbe presto una lista
  /// lunga senza punti di riferimento. [comunicati] è già il risultato di
  /// filtraComunicati, non _comunicati direttamente.
  Widget _buildListaRaggruppata(List<Map<String, dynamic>> comunicati) {
    final gruppi = raggruppaPerMese(comunicati);
    final mesi = gruppi.keys.toList();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: mesi.length,
      itemBuilder: (context, i) {
        final mese = mesi[i];
        final comunicatiMese = gruppi[mese]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
              child: Text(
                '$mese (${comunicatiMese.length})',
                style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
            ...comunicatiMese.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ComunicatoCard(
                    comunicato: c,
                    aprendo: _aprendoId == c['id'],
                    onApri: () => _apri(c),
                  ),
                )),
          ],
        );
      },
    );
  }

  /// Un chip di filtro tag, estratto per tenere separato il costruttore
  /// dal resto della riga scorrevole sopra.
  Widget _chipTag(String t) {
    final sel = _tagSelezionati.contains(t);
    return FilterChip(
      label: Text(t),
      selected: sel,
      onSelected: (v) => setState(() {
        if (v) {
          _tagSelezionati.add(t);
        } else {
          _tagSelezionati.remove(t);
        }
      }),
      selectedColor: kPrimary.withValues(alpha: 0.25),
      checkmarkColor: kPrimary,
      labelStyle: TextStyle(color: sel ? kPrimary : coloreTesto(context, 0.7)),
    );
  }
}

class _ComunicatoCard extends StatelessWidget {
  final Map<String, dynamic> comunicato;
  final bool aprendo;
  final VoidCallback onApri;

  const _ComunicatoCard({required this.comunicato, required this.aprendo, required this.onApri});

  @override
  Widget build(BuildContext context) {
    // Il nome del file resta il fallback: coerente con la convenzione già in
    // uso dall'associazione (AAAAMMGG_NUMERO_...) e con lo stesso nome usato
    // per il raggruppamento per mese (utils/comunicati.dart). Titolo/
    // descrizione sono opzionali (compilabili SOLO dalla pagina admin, mai
    // da qui — vedi CLAUDE.md sul confine di gestione), quindi qui è pura
    // visualizzazione: quando assenti la card torna al comportamento
    // originale (nome file come titolo, nessuna riga in più).
    final fileName = comunicato['fileName'] as String? ?? '';
    final titolo = _testoONull(comunicato['titolo']);
    final descrizione = _testoONull(comunicato['descrizione']);
    final tags = tagsDi(comunicato);
    final dettagli = [
      formatDate(comunicato['createdAt'] as String?),
      _dimensioneLeggibile(comunicato['fileSize']),
    ].join(' · ');
    // ListTile con subtitle ha un'altezza pensata per 1-2 righe fisse: con
    // un numero di righe variabile (nome file in più se c'è un titolo,
    // descrizione in più se compilata) uso invece un layout Row/Column
    // libero, stesso Card/icona/indicatore di prima.
    return Card(
      child: InkWell(
        onTap: aprendo ? null : onApri,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.picture_as_pdf_outlined, color: kPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titolo ?? fileName),
                    if (titolo != null)
                      Text(fileName, style: TextStyle(color: coloreTesto(context, 0.54), fontSize: 12)),
                    Text(dettagli, style: TextStyle(color: coloreTesto(context, 0.54), fontSize: 12)),
                    if (descrizione != null) ...[
                      const SizedBox(height: 4),
                      Text(descrizione, style: TextStyle(color: coloreTesto(context, 0.7))),
                    ],
                    if (tags.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: tags
                            .map((t) => Chip(
                                  label: Text(t, style: const TextStyle(fontSize: 11)),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  backgroundColor: kPrimary.withValues(alpha: 0.15),
                                  side: BorderSide.none,
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                ))
                            .toList(),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              aprendo
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.visibility_outlined),
            ],
          ),
        ),
      ),
    );
  }

  /// Stringa non vuota o null (tratta anche "" come assente): titolo/
  /// descrizione arrivano dal backend come JSON, o mai valorizzati (null) o
  /// eventualmente stringa vuota se svuotati dalla pagina admin.
  String? _testoONull(dynamic v) {
    final s = (v as String?)?.trim();
    return (s == null || s.isEmpty) ? null : s;
  }

  /// Formattazione dimensione file (B/KB/MB/GB): nessun helper condiviso già
  /// esistente nel progetto per una grandezza in byte (formatOre/formatDate
  /// in utils/format.dart coprono altri domini), aggiunta qui, locale a
  /// questa card — è l'unico punto dell'app che mostra una dimensione file.
  String _dimensioneLeggibile(dynamic valore) {
    final bytes = valore is int ? valore : int.tryParse('$valore') ?? 0;
    if (bytes <= 0) return '—';
    const unita = ['B', 'KB', 'MB', 'GB'];
    var v = bytes.toDouble();
    var i = 0;
    while (v >= 1024 && i < unita.length - 1) {
      v /= 1024;
      i++;
    }
    return '${v.toStringAsFixed(i == 0 ? 0 : 1)} ${unita[i]}';
  }
}
