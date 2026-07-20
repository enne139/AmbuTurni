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
          (o.via ?? '').toLowerCase().contains(q) ||
          (o.regione ?? '').toLowerCase().contains(q);
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

  /// Fa scegliere un luogo (città o regione, tramite `_SceltaLuogoDialog`)
  /// tra quelli che hanno ospedali sul backend, scarica gli ospedali
  /// corrispondenti e li fa confluire in anagrafica con lo stesso upsert per
  /// nome dell'import di backup (aggiorna chi esiste già, aggiunge i nuovi).
  /// L'indirizzo del server si configura ora in Impostazioni → Backend
  /// condiviso (spostato da qui, non è specifico di questo tool).
  Future<void> _scaricaOspedali() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final baseUrl = prefs.getString(kPrefBackendUrl) ?? kBackendUrlDefault;
    final scelta = await showDialog<(TipoLuogo, String)>(
      context: context,
      builder: (_) => _SceltaLuogoDialog(baseUrl: baseUrl),
    );
    if (scelta == null || scelta.$2.isEmpty || !mounted) return;
    final (tipo, luogo) = scelta;

    setState(() => _scaricando = true);
    try {
      final righe = await BackendApi(baseUrl: baseUrl).getOspedali(
        citta: tipo == TipoLuogo.citta ? luogo : null,
        regione: tipo == TipoLuogo.regione ? luogo : null,
      );
      final esito = await upsertOspedali(righe);
      if (!mounted) return;
      context.read<AnagraficheProvider>().carica();
      final avviso = esito.scartati == 0 ? '' : ' (${esito.scartati} scartati)';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${esito.creati} nuovi, ${esito.aggiornati} aggiornati per "$luogo".$avviso'),
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
              tooltip: 'Scarica ospedali per città o regione',
              onPressed: _scaricaOspedali,
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
                hintText: 'Cerca per nome, via, città o regione...',
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

  /// Etichetta di raggruppamento: la regione se presente, altrimenti un
  /// bucket dedicato in fondo — un ospedale senza regione non deve sparire,
  /// solo restare fuori dai gruppi con un nome.
  static const _senzaRegione = 'Senza regione';
  String _regioneDi(Ospedale o) => (o.regione == null || o.regione!.isEmpty) ? _senzaRegione : o.regione!;

  /// Raggruppa [ospedali] (già ordinati per nome) per regione, alfabetica
  /// con "Senza regione" sempre in fondo: nessun package, stessa filosofia
  /// "niente dipendenza per una griglia semplice" del calendario mensile —
  /// qui basta una ListView con intestazioni di sezione inline.
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
    final gruppi = <String, List<Ospedale>>{};
    for (final o in ospedali) {
      gruppi.putIfAbsent(_regioneDi(o), () => []).add(o);
    }
    final regioni = gruppi.keys.toList()
      ..sort((a, b) {
        if (a == _senzaRegione) return b == _senzaRegione ? 0 : 1;
        if (b == _senzaRegione) return -1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: regioni.length,
      itemBuilder: (_, i) {
        final regione = regioni[i];
        final ospedaliRegione = gruppi[regione]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
              child: Text(
                '$regione (${ospedaliRegione.length})',
                style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
            ...ospedaliRegione.map((o) => _OspedaleCard(
                  ospedale: o,
                  onNaviga: (app) => _naviga(o, app),
                )),
          ],
        );
      },
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

/// Filtro per "Scarica ospedali": per città (comportamento originale) o per
/// intera regione (aggiunto insieme al raggruppamento della lista).
enum TipoLuogo { citta, regione }

/// Dialog di scelta città/regione per "Scarica ospedali": un
/// `SegmentedButton` in cima sceglie quale elenco scaricare dal backend (GET
/// /api/citta o /api/regioni) e lo mostra come lista filtrabile, invece di
/// far digitare alla cieca un nome che magari non ha corrispondenze. Se il
/// download dell'elenco fallisce (server giù, endpoint assente su un
/// backend vecchio...) resta comunque possibile digitare un nome a mano: il
/// vero download degli ospedali (GET /api/ospedali?citta=|regione=)
/// potrebbe funzionare anche senza questo elenco.
class _SceltaLuogoDialog extends StatefulWidget {
  final String baseUrl;
  const _SceltaLuogoDialog({required this.baseUrl});

  @override
  State<_SceltaLuogoDialog> createState() => _SceltaLuogoDialogState();
}

class _SceltaLuogoDialogState extends State<_SceltaLuogoDialog> {
  final _ricercaCtrl = TextEditingController();
  TipoLuogo _tipo = TipoLuogo.citta;
  bool _caricando = true;
  List<String>? _luoghi; // null = caricamento fallito (vedi _errore)
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

  Future<void> _cambiaTipo(TipoLuogo tipo) async {
    if (tipo == _tipo) return;
    setState(() {
      _tipo = tipo;
      _ricercaCtrl.clear();
    });
    await _carica();
  }

  Future<void> _carica() async {
    setState(() {
      _caricando = true;
      _errore = null;
    });
    try {
      final api = BackendApi(baseUrl: widget.baseUrl);
      final lista = _tipo == TipoLuogo.citta ? await api.getCitta() : await api.getRegioni();
      if (!mounted) return;
      setState(() {
        _luoghi = lista;
        _caricando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _luoghi = null;
        _errore = messaggioErroreBackend(e);
        _caricando = false;
      });
    }
  }

  List<String> get _filtrati {
    final luoghi = _luoghi ?? const [];
    final q = _ricercaCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return luoghi;
    return luoghi.where((c) => c.toLowerCase().contains(q)).toList();
  }

  String get _etichetta => _tipo == TipoLuogo.citta ? 'città' : 'regione';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Scarica ospedali'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<TipoLuogo>(
              segments: const [
                ButtonSegment(value: TipoLuogo.citta, label: Text('Per città')),
                ButtonSegment(value: TipoLuogo.regione, label: Text('Per regione')),
              ],
              selected: {_tipo},
              onSelectionChanged: (s) => _cambiaTipo(s.first),
            ),
            const SizedBox(height: 12),
            _buildContenuto(),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annulla')),
        // Con l'elenco caricato si sceglie toccando la voce in lista: qui
        // serve solo il pulsante di conferma per il fallback manuale.
        if (_luoghi == null && !_caricando)
          TextButton(
            onPressed: _ricercaCtrl.text.trim().isEmpty
                ? null
                : () => Navigator.pop(context, (_tipo, _ricercaCtrl.text.trim())),
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
    if (_luoghi == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Elenco non disponibile (${_errore ?? 'errore sconosciuto'}). '
            'Puoi comunque digitare una $_etichetta.',
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ricercaCtrl,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: _tipo == TipoLuogo.citta ? 'Città' : 'Regione'),
            onChanged: (_) => setState(() {}),
          ),
        ],
      );
    }
    if (_luoghi!.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text('Il server non ha ancora nessun ospedale.', style: TextStyle(color: Colors.white54)),
      );
    }
    final filtrati = _filtrati;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _ricercaCtrl,
          autofocus: true,
          decoration: InputDecoration(hintText: 'Cerca $_etichetta...', prefixIcon: const Icon(Icons.search)),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 280,
          child: filtrati.isEmpty
              ? const Center(child: Text('Nessun risultato.', style: TextStyle(color: Colors.white38)))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: filtrati.length,
                  itemBuilder: (_, i) => ListTile(
                    title: Text(filtrati[i]),
                    onTap: () => Navigator.pop(context, (_tipo, filtrati[i])),
                  ),
                ),
        ),
      ],
    );
  }
}
