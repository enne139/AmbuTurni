// Test del client di geocoding (lib/utils/geocoding_api.dart). Il server
// Nominatim viene simulato con MockClient (package:http/testing): si
// verifica la richiesta (URL, header) e il parsing, senza contattare un
// servizio vero.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ambu_turni/utils/geocoding_api.dart';

http.Response _json(Object body, int status) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status,
        headers: {'content-type': 'application/json; charset=utf-8'});

GeocodingApi _api(http.Response risposta, List<http.Request> richieste) =>
    GeocodingApi(
      client: MockClient((req) async {
        richieste.add(req);
        return risposta;
      }),
    );

void main() {
  group('geocodifica', () {
    test('indirizzo vuoto non chiama il server e restituisce null', () async {
      final richieste = <http.Request>[];
      final api = _api(_json([], 200), richieste);
      final coord = await api.geocodifica('   ');
      expect(coord, isNull);
      expect(richieste, isEmpty);
    });

    test('chiama GET su nominatim con query, format e User-Agent', () async {
      final richieste = <http.Request>[];
      final api = _api(_json([], 200), richieste);
      await api.geocodifica('Via Roma 1, Milano');
      expect(richieste, hasLength(1));
      final uri = richieste.single.url;
      expect(uri.host, 'nominatim.openstreetmap.org');
      expect(uri.path, '/search');
      expect(uri.queryParameters['q'], 'Via Roma 1, Milano');
      expect(uri.queryParameters['format'], 'json');
      expect(richieste.single.headers['User-Agent'], isNotEmpty);
    });

    test('parsa lat/lon dal primo risultato', () async {
      final api = _api(
        _json([
          {'lat': '45.4642', 'lon': '9.1900'},
          {'lat': '0', 'lon': '0'},
        ], 200),
        [],
      );
      final coord = await api.geocodifica('Duomo, Milano');
      expect(coord, isNotNull);
      expect(coord!.lat, 45.4642);
      expect(coord.lng, 9.19);
    });

    test('passa addressdetails=1 nella richiesta', () async {
      final richieste = <http.Request>[];
      final api = _api(_json([], 200), richieste);
      await api.geocodifica('Via Roma 1, Milano');
      expect(richieste.single.url.queryParameters['addressdetails'], '1');
    });

    test('parsa address.state come regione', () async {
      final api = _api(
        _json([
          {
            'lat': '45.4642',
            'lon': '9.1900',
            'address': {'state': 'Lombardia'},
          }
        ], 200),
        [],
      );
      final coord = await api.geocodifica('Duomo, Milano');
      expect(coord!.regione, 'Lombardia');
    });

    test('address assente o senza state → regione null', () async {
      final api = _api(
        _json([
          {'lat': '45.4642', 'lon': '9.1900'},
        ], 200),
        [],
      );
      final coord = await api.geocodifica('Duomo, Milano');
      expect(coord!.regione, isNull);
    });

    test('nessun risultato → null', () async {
      final api = _api(_json([], 200), []);
      final coord = await api.geocodifica('indirizzo inesistente');
      expect(coord, isNull);
    });

    test('risposta di errore HTTP → null (nessuna eccezione)', () async {
      final api = _api(_json({'error': 'boom'}, 503), []);
      final coord = await api.geocodifica('Via Roma 1');
      expect(coord, isNull);
    });

    test('body non JSON (es. pagina di errore) → null (nessuna eccezione)',
        () async {
      final api = _api(http.Response('<html>Bad Gateway</html>', 200), []);
      final coord = await api.geocodifica('Via Roma 1');
      expect(coord, isNull);
    });

    test('lat/lon mancanti o non numerici nel risultato → null', () async {
      final api = _api(
        _json([
          {'lat': 'non-un-numero', 'lon': '9.19'}
        ], 200),
        [],
      );
      final coord = await api.geocodifica('Via Roma 1');
      expect(coord, isNull);
    });
  });
}
