import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../db/helpers.dart';
import '../../db/models.dart';
import '../../providers/app_provider.dart';
import '../../utils/backend_api.dart';
import '../../utils/prefs_keys.dart';
import '../../utils/theme.dart';

// Preferenza locale (non nel backup, come la vista lista/calendario di
// turni/assistenze: è solo l'ultima vista scelta su questo device).
const _kVistaMappaKey = 'lista_ospedali_vista_mappa';

/// App di navigazione esterna apribili dal pulsante Naviga.
enum _AppNavigazione { googleMaps, waze }

/// Tool "Lista ospedali": cerca per nome negli ospedali già in anagrafica,
/// mostra l'indirizzo e apre il navigatore esterno, oppure una mappa con la
/// posizione di tutti gli ospedali geocodificati. Sola consultazione: la
/// modifica di nome/via/città resta in Impostazioni → Ospedali.
class ListaOspedaliScreen extends StatefulWidget {
  const ListaOspedaliScreen({super.key});

  @override
  State<ListaOspedaliScreen> createState() => _ListaOspedaliScreenState();
}

class _ListaOspedaliScreenState extends State<ListaOspedaliScreen> {
  final _ricercaCtrl = TextEditingController();
  bool _vistaMappa = false;
  bool _scaricando = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      setState(() => _vistaMappa = prefs.getBool(_kVistaMappaKey) ?? false);
    });
  }

  @override
  void dispose() {
    _ricercaCtrl.dispose();
    super.dispose();
  }

  void _toggleVista() {
    setState(() => _vistaMappa = !_vistaMappa);
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setBool(_kVistaMappaKey, _vistaMappa));
  }

  List<Ospedale> _filtrati(List<Ospedale> ospedali) {
    final q = _ricercaCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return ospedali;
    return ospedali.where((o) {
      return o.nome.toLowerCase().contains(q) ||
          (o.citta ?? '').toLowerCase().contains(q) ||
          (o.via ?? '').toLowerCase().contains(q);
    }).toList();
  }

  /// Apre Google Maps o Waze (l'app se installata, altrimenti il sito) su
  /// [o]. Entrambi via link universale https, come già per Google Maps: apre
  /// l'app se il device la riconosce come gestore, nessun permesso né voce
  /// `<queries>` nel manifest (a differenza di uno scheme nativo `waze://`,
  /// che fallirebbe silenziosamente senza l'app installata). Se l'ospedale ha
  /// coordinate geocodificate le usa (più precise, per entrambi i servizi),
  /// altrimenti passa nome+via+città come ricerca testuale: entrambi i
  /// servizi la risolvono da sé.
  Future<void> _naviga(Ospedale o, _AppNavigazione app) async {
    final query = [o.nome, o.via, o.citta]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(', ');
    final coordinate = o.haCoordinate ? '${o.lat},${o.lng}' : null;
    final Uri uri;
    switch (app) {
      case _AppNavigazione.googleMaps:
        uri = Uri.https('www.google.com', '/maps/search/', {
          'api': '1',
          'query': coordinate ?? query,
        });
        break;
      case _AppNavigazione.waze:
        uri = coordinate != null
            ? Uri.https('waze.com', '/ul', {
                'll': coordinate,
                'navigate': 'yes',
              })
            : Uri.https('waze.com', '/ul', {
                'q': query,
                'navigate': 'yes',
              });
        break;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossibile aprire il navigatore.')),
      );
    }
  }

  /// Dialog di configurazione dell'indirizzo del backend condiviso ospedali:
  /// precompilato con quanto salvato o, se mai toccato, col default
  /// centralizzato (kBackendUrlDefault) — a differenza del Magazzino Verde
  /// qui c'è sempre un valore sensato, non serve un "non configurato".
  Future<void> _configuraServer() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final nuovo = await showDialog<String>(
      context: context,
      builder: (_) => _ConfigServerDialog(
        urlIniziale: prefs.getString(kPrefBackendUrl) ?? kBackendUrlDefault,
      ),
    );
    if (nuovo == null) return;
    await prefs.setString(kPrefBackendUrl, nuovo.isEmpty ? kBackendUrlDefault : nuovo);
  }

  /// Fa scegliere una città tra quelle che hanno ospedali sul backend
  /// (`_SceltaCittaDialog`), scarica gli ospedali di quella città e li fa
  /// confluire in anagrafica con lo stesso upsert per nome dell'import di
  /// backup (aggiorna chi esiste già, aggiunge i nuovi).
  Future<void> _scaricaPerCitta() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final baseUrl = prefs.getString(kPrefBackendUrl) ?? kBackendUrlDefault;
    final citta = await showDialog<String>(
      context: context,
      builder: (_) => _SceltaCittaDialog(baseUrl: baseUrl),
    );
    if (citta == null || citta.isEmpty || !mounted) return;

    setState(() => _scaricando = true);
    try {
      final righe = await BackendApi(baseUrl: baseUrl).getOspedali(citta: citta);
      final esito = await upsertOspedali(righe);
      if (!mounted) return;
      context.read<AnagraficheProvider>().carica();
      final avviso = esito.scartati == 0 ? '' : ' (${esito.scartati} scartati)';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${esito.creati} nuovi, ${esito.aggiornati} aggiornati per "$citta".$avviso'),
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(messaggioErroreBackend(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _scaricando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ospedali = context.watch<AnagraficheProvider>().ospedali;
    final filtrati = _filtrati(ospedali)..sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lista ospedali'),
        actions: [
          if (_scaricando)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.cloud_download_outlined),
              tooltip: 'Scarica ospedali per città',
              onPressed: _scaricaPerCitta,
            ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Configura server',
            onPressed: _configuraServer,
          ),
          IconButton(
            icon: Icon(_vistaMappa ? Icons.view_list : Icons.map_outlined),
            tooltip: _vistaMappa ? 'Vista elenco' : 'Vista mappa',
            onPressed: _toggleVista,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _ricercaCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Cerca per nome, via o città...',
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
          const SizedBox(height: 8),
          Expanded(
            child: _vistaMappa ? _buildMappa(filtrati) : _buildLista(filtrati),
          ),
        ],
      ),
    );
  }

  Widget _buildLista(List<Ospedale> ospedali) {
    if (ospedali.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _ricercaCtrl.text.isEmpty
                ? 'Nessun ospedale in anagrafica.\nSi aggiungono da Impostazioni → Ospedali.'
                : 'Nessun ospedale trovato.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: ospedali.length,
      itemBuilder: (_, i) => _OspedaleCard(
        ospedale: ospedali[i],
        onNaviga: (app) => _naviga(ospedali[i], app),
      ),
    );
  }

  Widget _buildMappa(List<Ospedale> ospedali) {
    final conCoordinate = ospedali.where((o) => o.haCoordinate).toList();
    if (conCoordinate.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Nessun ospedale ha ancora una posizione sulla mappa.\n'
            'Le coordinate si calcolano da sole quando salvi un indirizzo '
            'in Impostazioni → Ospedali.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54),
          ),
        ),
      );
    }
    final punti = conCoordinate.map((o) => ll.LatLng(o.lat!, o.lng!)).toList();
    final centro = ll.LatLng(
      punti.map((p) => p.latitude).reduce((a, b) => a + b) / punti.length,
      punti.map((p) => p.longitude).reduce((a, b) => a + b) / punti.length,
    );
    return FlutterMap(
      options: MapOptions(initialCenter: centro, initialZoom: 12),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.maratuck.ambu_turni',
        ),
        MarkerLayer(
          markers: conCoordinate
              .map((o) => Marker(
                    point: ll.LatLng(o.lat!, o.lng!),
                    width: 42,
                    height: 42,
                    child: GestureDetector(
                      onTap: () => _apriDettaglioMarker(o),
                      child: const Icon(Icons.location_on, color: kPrimary, size: 38),
                    ),
                  ))
              .toList(),
        ),
        const RichAttributionWidget(
          attributions: [TextSourceAttribution('© OpenStreetMap contributors')],
        ),
      ],
    );
  }

  Future<void> _apriDettaglioMarker(Ospedale o) async {
    await showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(o.nome, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              if ((o.via ?? '').isNotEmpty || (o.citta ?? '').isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  [o.via, o.citta].whereType<String>().where((s) => s.isNotEmpty).join(', '),
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.directions),
                    label: const Text('Google Maps'),
                    onPressed: () {
                      Navigator.pop(context);
                      _naviga(o, _AppNavigazione.googleMaps);
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.navigation_outlined),
                    label: const Text('Waze'),
                    onPressed: () {
                      Navigator.pop(context);
                      _naviga(o, _AppNavigazione.waze);
                    },
                  ),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Card di un ospedale nella vista elenco: indirizzo e pulsante Naviga.
/// Nessuna azione per gli ospedali senza coordinate: il geocoding riparte da
/// solo salvando di nuovo l'indirizzo in Impostazioni → Ospedali.
class _OspedaleCard extends StatelessWidget {
  final Ospedale ospedale;
  final void Function(_AppNavigazione app) onNaviga;

  const _OspedaleCard({
    required this.ospedale,
    required this.onNaviga,
  });

  @override
  Widget build(BuildContext context) {
    final o = ospedale;
    final indirizzo = [o.via, o.citta].whereType<String>().where((s) => s.isNotEmpty).join(', ');
    final haIndirizzo = indirizzo.isNotEmpty;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(o.nome, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: haIndirizzo
            ? Text(indirizzo, style: const TextStyle(color: Colors.white54))
            : const Text('Nessun indirizzo salvato', style: TextStyle(color: Colors.white38)),
        trailing: PopupMenuButton<_AppNavigazione>(
          icon: const Icon(Icons.directions, color: kPrimary),
          tooltip: 'Naviga',
          onSelected: onNaviga,
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: _AppNavigazione.googleMaps,
              child: Text('Google Maps'),
            ),
            PopupMenuItem(
              value: _AppNavigazione.waze,
              child: Text('Waze'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog di configurazione dell'indirizzo backend: il pulsante principale
/// verifica la connessione (GET /api/health) prima di salvare, così un URL
/// sbagliato o un server irraggiungibile non passano inosservati. Se la
/// verifica fallisce il pulsante diventa "Salva comunque" (il server
/// potrebbe essere solo temporaneamente giù, non deve bloccare per forza il
/// salvataggio); modificare di nuovo il testo dopo un fallimento fa
/// ripartire da capo la verifica sul nuovo indirizzo.
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

/// Dialog di scelta città per "Scarica ospedali per città": scarica
/// l'elenco delle città che hanno almeno un ospedale sul backend (GET
/// /api/citta) e le mostra come lista filtrabile, invece di far digitare
/// alla cieca un nome che magari non ha corrispondenze. Se il download
/// dell'elenco fallisce (server giù, endpoint assente su un backend
/// vecchio...) resta comunque possibile digitare una città a mano: il vero
/// download degli ospedali (GET /api/ospedali?citta=) potrebbe funzionare
/// anche senza questo elenco.
class _SceltaCittaDialog extends StatefulWidget {
  final String baseUrl;
  const _SceltaCittaDialog({required this.baseUrl});

  @override
  State<_SceltaCittaDialog> createState() => _SceltaCittaDialogState();
}

class _SceltaCittaDialogState extends State<_SceltaCittaDialog> {
  final _ricercaCtrl = TextEditingController();
  bool _caricando = true;
  List<String>? _citta; // null = caricamento fallito (vedi _errore)
  String? _errore;

  @override
  void initState() {
    super.initState();
    _carica();
  }

  @override
  void dispose() {
    _ricercaCtrl.dispose();
    super.dispose();
  }

  Future<void> _carica() async {
    try {
      final lista = await BackendApi(baseUrl: widget.baseUrl).getCitta();
      if (!mounted) return;
      setState(() {
        _citta = lista;
        _caricando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errore = messaggioErroreBackend(e);
        _caricando = false;
      });
    }
  }

  List<String> get _filtrate {
    final citta = _citta ?? const [];
    final q = _ricercaCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return citta;
    return citta.where((c) => c.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Scarica ospedali'),
      content: SizedBox(width: double.maxFinite, child: _buildContenuto()),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla')),
        // Con l'elenco caricato si sceglie una città toccandola in lista:
        // qui serve solo il pulsante di conferma per il fallback manuale.
        if (_citta == null && !_caricando)
          TextButton(
            onPressed: _ricercaCtrl.text.trim().isEmpty
                ? null
                : () => Navigator.pop(context, _ricercaCtrl.text.trim()),
            child: const Text('Scarica'),
          ),
      ],
    );
  }

  Widget _buildContenuto() {
    if (_caricando) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_citta == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Elenco città non disponibile (${_errore ?? 'errore sconosciuto'}). '
            'Puoi comunque digitare una città.',
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ricercaCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Città'),
            onChanged: (_) => setState(() {}),
          ),
        ],
      );
    }
    if (_citta!.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text('Il server non ha ancora nessun ospedale.', style: TextStyle(color: Colors.white54)),
      );
    }
    final filtrate = _filtrate;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _ricercaCtrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Cerca città...', prefixIcon: Icon(Icons.search)),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 280,
          child: filtrate.isEmpty
              ? const Center(child: Text('Nessuna città trovata.', style: TextStyle(color: Colors.white38)))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: filtrate.length,
                  itemBuilder: (_, i) => ListTile(
                    title: Text(filtrate[i]),
                    onTap: () => Navigator.pop(context, filtrate[i]),
                  ),
                ),
        ),
      ],
    );
  }
}
