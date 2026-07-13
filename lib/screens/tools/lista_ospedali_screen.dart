import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../db/helpers.dart';
import '../../db/models.dart';
import '../../providers/app_provider.dart';
import '../../utils/geocoding_api.dart';
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
  // Id degli ospedali per cui è in corso un retry di geocoding manuale.
  final Set<String> _geocodificando = {};

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
  /// coordinate geocodificate le usa (più precise), altrimenti passa nome+
  /// via+città come ricerca testuale: entrambi i servizi la risolvono da sé.
  Future<void> _naviga(Ospedale o, _AppNavigazione app) async {
    final query = [o.nome, o.via, o.citta]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(', ');
    final Uri uri;
    switch (app) {
      case _AppNavigazione.googleMaps:
        uri = Uri.https('www.google.com', '/maps/search/', {
          'api': '1',
          'query': query,
        });
        break;
      case _AppNavigazione.waze:
        uri = o.haCoordinate
            ? Uri.https('waze.com', '/ul', {
                'll': '${o.lat},${o.lng}',
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

  /// Ritenta il geocoding di un ospedale (es. dopo un primo tentativo fallito
  /// per assenza di rete): stesso servizio del salvataggio in Impostazioni,
  /// richiamabile qui senza dover riaprire il form.
  Future<void> _riprovaGeocoding(Ospedale o) async {
    final indirizzo = [o.via, o.citta]
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .join(', ');
    setState(() => _geocodificando.add(o.id));
    final coord = await GeocodingApi().geocodifica(indirizzo);
    if (coord != null) {
      await aggiornaCoordinateOspedale(o.id, coord.lat, coord.lng);
      if (mounted) context.read<AnagraficheProvider>().carica();
    }
    if (!mounted) return;
    setState(() => _geocodificando.remove(o.id));
    if (coord == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Posizione non trovata per questo indirizzo.')),
      );
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
        geocodificando: _geocodificando.contains(ospedali[i].id),
        onNaviga: (app) => _naviga(ospedali[i], app),
        onRiprovaGeocoding: () => _riprovaGeocoding(ospedali[i]),
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

/// Card di un ospedale nella vista elenco: indirizzo e pulsante Naviga
/// sempre disponibile; se l'indirizzo non ha ancora coordinate (mappa) mostra
/// anche un pulsante per ritentare il geocoding sul posto.
class _OspedaleCard extends StatelessWidget {
  final Ospedale ospedale;
  final bool geocodificando;
  final void Function(_AppNavigazione app) onNaviga;
  final VoidCallback onRiprovaGeocoding;

  const _OspedaleCard({
    required this.ospedale,
    required this.geocodificando,
    required this.onNaviga,
    required this.onRiprovaGeocoding,
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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (haIndirizzo && !o.haCoordinate)
              geocodificando
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.location_searching, color: Colors.white38),
                      tooltip: 'Cerca posizione per la mappa',
                      onPressed: onRiprovaGeocoding,
                    ),
            PopupMenuButton<_AppNavigazione>(
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
          ],
        ),
      ),
    );
  }
}
