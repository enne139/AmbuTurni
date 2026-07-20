import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../db/backup.dart';
import '../../providers/app_provider.dart';
import '../../utils/backend_api.dart';
import '../../utils/prefs_keys.dart';
import '../../utils/theme.dart';
import '../../utils/tools_config.dart';

/// Schermata Impostazioni: backup/ripristino, navigazione, tool attivi e
/// backend condiviso. Le anagrafiche (Associazioni/Persone/Ospedali/
/// Tipologie turno) si sono spostate nella schermata Anagrafiche,
/// raggiungibile dall'icona nell'AppBar della tab Attività (v.
/// screens/anagrafiche/anagrafiche_screen.dart e app_navigator.dart).
class ImpostazioniScreen extends StatelessWidget {
  const ImpostazioniScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Impostazioni')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: const [
          _SezioneBackup(),
          Divider(height: 24),
          _SezioneNavigazione(),
          Divider(height: 24),
          _SezioneToolsAttivi(),
          Divider(height: 24),
          _SezioneBackendCondiviso(),
          Divider(height: 24),
          _VersioneApp(),
          SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Backup / Ripristino
// ---------------------------------------------------------------------------

class _SezioneBackup extends StatefulWidget {
  const _SezioneBackup();
  @override
  State<_SezioneBackup> createState() => _SezioneBackupState();
}

class _SezioneBackupState extends State<_SezioneBackup> {
  bool _busy = false;

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final path = await exportBackup();
      if (mounted) {
        final msg = path != null ? 'Backup salvato.' : 'Export annullato.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore export: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportSemplificato() async {
    setState(() => _busy = true);
    try {
      final path = await exportSemplificato();
      if (mounted) {
        final msg = path != null ? 'Export leggibile salvato.' : 'Export annullato.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore export: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    // Chiede conferma prima di sovrascrivere tutti i dati.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Importa backup'),
        content: const Text(
          'L\'import sovrascrive TUTTI i dati locali con quelli del file scelto. '
          'Questa operazione non è reversibile.\n\nContinuare?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Importa', style: TextStyle(color: kPrimary)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    final msg = await importBackup();
    if (!mounted) return;
    setState(() => _busy = false);

    // Ricarica tutti i provider dopo l'import.
    if (mounted) {
      context.read<AnagraficheProvider>().carica();
      context.read<TurniProvider>().ricarica();
      context.read<AssistenzeProvider>().ricarica();
      context.read<StatisticheProvider>().ricarica();
      context.read<ToolsProvider>().carica();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            const Icon(Icons.backup, size: 18, color: kPrimary),
            const SizedBox(width: 8),
            const Text('Backup / Ripristino', style: TextStyle(color: kPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
          ]),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: LinearProgressIndicator(),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.upload_file, size: 18),
                    label: const Text('Esporta JSON'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kPrimary,
                      side: const BorderSide(color: kPrimary),
                    ),
                    onPressed: _export,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.download, size: 18),
                    label: const Text('Importa JSON'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                    ),
                    onPressed: _import,
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.table_rows_outlined, size: 18),
                  label: const Text('Esporta JSON leggibile (turni e assistenze)'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white54,
                    side: const BorderSide(color: Colors.white12),
                  ),
                  onPressed: _exportSemplificato,
                ),
              ),
            ]),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Navigazione (pagina principale, tab Attività+Statistiche, Piano turni)
// ---------------------------------------------------------------------------

/// Pagina principale mostrata all'avvio (Attività, Tools o Piano turni),
/// interruttore per disattivare del tutto le tab Attività (turni +
/// assistenze) e Statistiche insieme (per chi usa l'app solo per gli altri
/// tool, es. solo Magazzino Verde/Lista ospedali) e interruttore per
/// spostare il tool Piano turni dalla tab Tools a una voce propria in
/// navbar (imposta anche Piano turni come pagina principale). Collassata di
/// default come le altre sezioni di configurazione, stesso pattern di
/// _SezioneToolsAttivi/_SezioneBackendCondiviso.
class _SezioneNavigazione extends StatefulWidget {
  const _SezioneNavigazione();

  @override
  State<_SezioneNavigazione> createState() => _SezioneNavigazioneState();
}

class _SezioneNavigazioneState extends State<_SezioneNavigazione> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigazioneProvider>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                const Icon(Icons.home_outlined, size: 18, color: kPrimary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Navigazione',
                      style: TextStyle(color: kPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
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
        if (_expanded)
          if (!nav.caricato)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: LinearProgressIndicator(),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Pagina principale', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 8),
                  SegmentedButton<PaginaPrincipale>(
                    segments: [
                      ButtonSegment(
                        value: PaginaPrincipale.attivita,
                        label: const Text('Turni/Assistenze'),
                        enabled: nav.attivitaStatisticheAttive,
                      ),
                      const ButtonSegment(value: PaginaPrincipale.tools, label: Text('Tools')),
                      ButtonSegment(
                        value: PaginaPrincipale.pianoTurni,
                        label: const Text('Piano turni'),
                        enabled: nav.pianoTurniInNavbar,
                      ),
                    ],
                    selected: {nav.paginaPrincipale},
                    showSelectedIcon: false,
                    onSelectionChanged: (s) =>
                        context.read<NavigazioneProvider>().setPaginaPrincipale(s.first),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Attività e Statistiche'),
                    subtitle: const Text(
                      'Disattiva se non usi la gestione turni/assistenze di questa app: '
                      'nasconde anche le Statistiche, che le riguardano.',
                      style: TextStyle(color: Colors.white54),
                    ),
                    value: nav.attivitaStatisticheAttive,
                    activeTrackColor: kPrimary,
                    onChanged: (v) => context.read<NavigazioneProvider>().setAttivitaStatisticheAttive(v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Piano turni nella barra di navigazione'),
                    subtitle: const Text(
                      'Sposta il tool Piano turni dalla tab Tools a una voce propria in basso, '
                      'e lo imposta come pagina principale.',
                      style: TextStyle(color: Colors.white54),
                    ),
                    value: nav.pianoTurniInNavbar,
                    activeTrackColor: kPrimary,
                    onChanged: (v) => context.read<NavigazioneProvider>().setPianoTurniInNavbar(v),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tools attivi
// ---------------------------------------------------------------------------

/// Switch per attivare/disattivare i tool mostrati nella tab Tools
/// (ToolsProvider): il Magazzino Verde parte disattivato di default (si
/// collega a un server esterno da configurare), gli altri sono attivi.
/// Collassata di default come le sezioni anagrafiche: non è
/// qualcosa che si tocca spesso, non deve occupare spazio in cima alla
/// schermata a ogni apertura.
class _SezioneToolsAttivi extends StatefulWidget {
  const _SezioneToolsAttivi();

  @override
  State<_SezioneToolsAttivi> createState() => _SezioneToolsAttiviState();
}

class _SezioneToolsAttiviState extends State<_SezioneToolsAttivi> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tools = context.watch<ToolsProvider>();
    final numAttivi = kToolsDisponibili.where((t) => tools.attivo(t.id)).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                const Icon(Icons.handyman_outlined, size: 18, color: kPrimary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Tools attivi',
                      style: TextStyle(color: kPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: kPrimary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$numAttivi/${kToolsDisponibili.length}',
                    style: const TextStyle(color: kPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  color: Colors.white38,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          if (!tools.caricato)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: LinearProgressIndicator(),
            )
          else
            ...kToolsDisponibili.map((t) => SwitchListTile(
                  dense: true,
                  secondary: Icon(t.icon, color: Colors.white70),
                  title: Text(t.titolo),
                  subtitle: Text(t.sottotitolo, style: const TextStyle(color: Colors.white54)),
                  value: tools.attivo(t.id),
                  activeTrackColor: kPrimary,
                  onChanged: (v) => context.read<ToolsProvider>().setAttivo(t.id, v),
                )),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Backend condiviso (ospedali, fogli turni, materiali)
// ---------------------------------------------------------------------------

/// Configurazione del backend condiviso (`backend/`, Go): indirizzo del
/// server e sincronizzazione automatica dei fogli turni. Spostata qui da
/// Lista ospedali (dove restava solo l'icona ingranaggio) perché non è
/// specifica di quel tool: il download per città/regione resta lì
/// (contestuale alla schermata), ma la configurazione del server è
/// un'impostazione trasversale, coerente con Tools attivi. Collassata di
/// default come le altre sezioni non toccate spesso.
class _SezioneBackendCondiviso extends StatefulWidget {
  const _SezioneBackendCondiviso();

  @override
  State<_SezioneBackendCondiviso> createState() => _SezioneBackendCondivisoState();
}

class _SezioneBackendCondivisoState extends State<_SezioneBackendCondiviso> {
  bool _expanded = false;
  bool _caricato = false;
  String _url = kBackendUrlDefault;
  bool _syncFogli = true;

  @override
  void initState() {
    super.initState();
    _carica();
  }

  Future<void> _carica() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _url = prefs.getString(kPrefBackendUrl) ?? kBackendUrlDefault;
      _syncFogli = prefs.getBool(kPrefSyncFogliAttivo) ?? true;
      _caricato = true;
    });
  }

  Future<void> _configuraServer() async {
    final nuovo = await showDialog<String>(
      context: context,
      builder: (_) => _ConfigServerDialog(urlIniziale: _url),
    );
    if (nuovo == null) return;
    final prefs = await SharedPreferences.getInstance();
    final url = nuovo.isEmpty ? kBackendUrlDefault : nuovo;
    await prefs.setString(kPrefBackendUrl, url);
    if (mounted) setState(() => _url = url);
  }

  Future<void> _setSyncFogli(bool v) async {
    setState(() => _syncFogli = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kPrefSyncFogliAttivo, v);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                const Icon(Icons.cloud_outlined, size: 18, color: kPrimary),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Backend condiviso',
                      style: TextStyle(color: kPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
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
        if (_expanded)
          if (!_caricato)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: LinearProgressIndicator(),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Indirizzo del server'),
                    subtitle: Text(_url, style: const TextStyle(color: Colors.white54)),
                    trailing: OutlinedButton(
                      onPressed: _configuraServer,
                      child: const Text('Cambia'),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Sincronizza fogli turni'),
                    subtitle: const Text(
                      'Scarica automaticamente i nuovi mesi salvati sul backend nel tool Piano turni.',
                      style: TextStyle(color: Colors.white54),
                    ),
                    value: _syncFogli,
                    activeTrackColor: kPrimary,
                    onChanged: _setSyncFogli,
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

/// Dialog di configurazione dell'indirizzo backend: il pulsante principale
/// verifica la connessione (GET /api/health) prima di salvare, così un URL
/// sbagliato o un server irraggiungibile non passano inosservati. Se la
/// verifica fallisce il pulsante diventa "Salva comunque" (il server
/// potrebbe essere solo temporaneamente giù, non deve bloccare per forza il
/// salvataggio); modificare di nuovo il testo dopo un fallimento fa
/// ripartire da capo la verifica sul nuovo indirizzo. Spostato qui da Lista
/// ospedali insieme alla sua configurazione (vedi _SezioneBackendCondiviso).
class _ConfigServerDialog extends StatefulWidget {
  final String urlIniziale;
  const _ConfigServerDialog({required this.urlIniziale});

  @override
  State<_ConfigServerDialog> createState() => _ConfigServerDialogState();
}

class _ConfigServerDialogState extends State<_ConfigServerDialog> {
  late final _ctrl = TextEditingController(text: widget.urlIniziale);
  bool _verificando = false;
  String? _errore;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _onSalvaPressato() async {
    final url = BackendApi.normalizzaUrl(_ctrl.text);
    // Campo vuoto (torna al default) o verifica già fallita in precedenza
    // ("Salva comunque"): nessun nuovo test, si salva subito.
    if (url.isEmpty || _errore != null) {
      Navigator.pop(context, url);
      return;
    }
    setState(() {
      _verificando = true;
      _errore = null;
    });
    final ok = await BackendApi(baseUrl: url).verificaConnessione();
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, url);
    } else {
      setState(() {
        _verificando = false;
        _errore = 'Il server non risponde a questo indirizzo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Server ospedali'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _ctrl,
            enabled: !_verificando,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(labelText: 'Indirizzo del server'),
            // Un indirizzo diverso da quello già bocciato merita una verifica
            // vera, non l'override "Salva comunque" del tentativo precedente.
            onChanged: (_) {
              if (_errore != null) setState(() => _errore = null);
            },
          ),
          if (_errore != null) ...[
            const SizedBox(height: 8),
            Text(_errore!, style: const TextStyle(color: kPrimary, fontSize: 13)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _verificando ? null : () => Navigator.pop(context),
          child: const Text('Annulla'),
        ),
        if (_verificando)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else
          TextButton(
            onPressed: _onSalvaPressato,
            child: Text(_errore != null ? 'Salva comunque' : 'Verifica e salva'),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Versione app
// ---------------------------------------------------------------------------

/// Numero di versione (X.Y.Z+N) in fondo a Impostazioni, letto dalla
/// piattaforma con package_info_plus invece che duplicato a mano: riflette
/// sempre quello che è stato davvero compilato in pubspec.yaml.
class _VersioneApp extends StatelessWidget {
  const _VersioneApp();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: Text(
              info == null ? '' : 'AmbuTurni v${info.version}+${info.buildNumber}',
              style: const TextStyle(color: Colors.white24, fontSize: 12),
            ),
          ),
        );
      },
    );
  }
}
