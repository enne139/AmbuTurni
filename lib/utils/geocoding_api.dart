// Geocoding dell'indirizzo di un ospedale (tool Lista ospedali): risolve un
// indirizzo testuale in lat/lng con Nominatim (OpenStreetMap), l'unico
// servizio di geocoding gratuito senza API key — stessa scelta "no key" del
// tile server della mappa. Dart puro (niente import Flutter), come
// magazzino_api.dart e piano_mensile.dart, per essere unit-testabile con
// un http.Client finto (MockClient).
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Coppia di coordinate risolte da un indirizzo.
class Coordinate {
  final double lat;
  final double lng;

  const Coordinate(this.lat, this.lng);
}

/// Client minimale dell'endpoint di ricerca di Nominatim.
class GeocodingApi {
  final http.Client _client;

  // Chiamata solo alla creazione/modifica di un ospedale (azione manuale
  // sporadica): non serve un rate-limiter per rispettare il limite di
  // Nominatim (max 1 richiesta/secondo).
  static const _timeout = Duration(seconds: 15);

  // La policy di Nominatim richiede uno User-Agent identificativo: senza,
  // le richieste vengono limitate o rifiutate.
  static const _userAgent = 'AmbuTurni (app gestione turni ambulanza)';

  GeocodingApi({http.Client? client}) : _client = client ?? http.Client();

  /// Risolve [indirizzo] in coordinate. Restituisce null (mai un'eccezione)
  /// se l'indirizzo è vuoto, il servizio non trova risultati, risponde con
  /// un errore o il device è offline: il geocoding è un arricchimento
  /// best-effort, non deve mai bloccare il salvataggio di un ospedale.
  Future<Coordinate?> geocodifica(String indirizzo) async {
    if (indirizzo.trim().isEmpty) return null;
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': indirizzo,
        'format': 'json',
        'limit': '1',
      });
      final resp = await _client.get(uri, headers: {
        'User-Agent': _userAgent,
        'Accept-Language': 'it',
      }).timeout(_timeout);
      if (resp.statusCode != 200) return null;
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      if (decoded is! List || decoded.isEmpty) return null;
      final primo = decoded.first;
      if (primo is! Map) return null;
      final lat = double.tryParse('${primo['lat']}');
      final lng = double.tryParse('${primo['lon']}');
      if (lat == null || lng == null) return null;
      return Coordinate(lat, lng);
    } catch (_) {
      return null;
    }
  }
}
