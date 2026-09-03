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
              const Icon(Icons.wifi_off, size: 48, color: Colors.white38),
              const SizedBox(height: 16),
              Text('Impossibile contattare il server condiviso.\n$_errore',
                  textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 20),
              OutlinedButton(onPressed: _carica, child: const Text('Riprova')),
            ],
          ),
        ),
      );
    }
    // RefreshIndicator su entrambi i rami (vuoto/pieno): serve comunque una
    // ListView scrollabile perché il pull-to-refresh funzioni anche a lista
    // vuota (un Center da solo non è "trascinabile").
    return RefreshIndicator(
      onRefresh: _carica,
      child: _comunicati.isEmpty
          ? ListView(
              children: const [
                Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(
                    child: Text(
                      'Nessun comunicato disponibile al momento.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                ),
              ],
            )
          : _buildListaRaggruppata(),
    );
  }

  /// Un'unica archivio cronologico, raggruppato per mese (vedi
  /// _raggruppaPerMese sopra) invece di una lista piatta: i comunicati si
  /// accumulano nel tempo, senza intestazioni diventerebbe presto una lista
  /// lunga senza punti di riferimento.
  Widget _buildListaRaggruppata() {
    final gruppi = raggruppaPerMese(_comunicati);
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
}

class _ComunicatoCard extends StatelessWidget {
  final Map<String, dynamic> comunicato;
  final bool aprendo;
  final VoidCallback onApri;

  const _ComunicatoCard({required this.comunicato, required this.aprendo, required this.onApri});

  @override
  Widget build(BuildContext context) {
    // Nessun titolo/descrizione (richiesta esplicita dell'utente): il nome
    // del file è ciò che si mostra, coerente con la convenzione di nome già
    // in uso dall'associazione (AAAAMMGG_NUMERO_...) e con lo stesso nome
    // usato per il raggruppamento per mese (utils/comunicati.dart).
    final fileName = comunicato['fileName'] as String? ?? '';
    final sottotitolo = [
      formatDate(comunicato['createdAt'] as String?),
      _dimensioneLeggibile(comunicato['fileSize']),
    ].join(' · ');
    return Card(
      child: ListTile(
        leading: const Icon(Icons.picture_as_pdf_outlined, color: kPrimary),
        title: Text(fileName),
        subtitle: Text(sottotitolo, style: const TextStyle(color: Colors.white54)),
        trailing: aprendo
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.visibility_outlined),
        onTap: aprendo ? null : onApri,
      ),
    );
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
