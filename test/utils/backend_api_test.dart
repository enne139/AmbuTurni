// Test del client del backend condiviso ospedali (lib/utils/backend_api.dart).
// Il server viene simulato con MockClient (package:http/testing): si
// verifica la richiesta (URL, query) e il parsing.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ambu_turni/utils/backend_api.dart';

http.Response _json(Object body, int status) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status,
        headers: {'content-type': 'application/json; charset=utf-8'});

BackendApi _api(http.Response risposta, List<http.Request> richieste) => BackendApi(
      baseUrl: 'https://backend.test',
      client: MockClient((req) async {
        richieste.add(req);
        return risposta;
      }),
    );

void main() {
  group('normalizzaUrl', () {
    test('aggiunge https:// se manca lo schema', () {
      expect(BackendApi.normalizzaUrl('backend.esempio.it'), 'https://backend.esempio.it');
    });

    test('rimuove gli slash finali', () {
      expect(BackendApi.normalizzaUrl('https://backend.test///'), 'https://backend.test');
    });
  });

  group('getOspedali', () {
    test('chiama GET /api/ospedali senza query se citta è assente', () async {
      final richieste = <http.Request>[];
      final api = _api(_json([], 200), richieste);
      await api.getOspedali();
      expect(richieste, hasLength(1));
      expect(richieste.first.method, 'GET');
      expect(richieste.first.url.toString(), 'https://backend.test/api/ospedali');
    });

    test('passa citta come query param', () async {
      final richieste = <http.Request>[];
      final api = _api(_json([], 200), richieste);
      await api.getOspedali(citta: 'Milano');
      expect(richieste.single.url.queryParameters['citta'], 'Milano');
    });

    test('citta vuota o solo spazi non viene passata come query', () async {
      final richieste = <http.Request>[];
      final api = _api(_json([], 200), richieste);
      await api.getOspedali(citta: '   ');
      expect(richieste.single.url.queryParameters.containsKey('citta'), isFalse);
    });

    test('passa regione come query param', () async {
      final richieste = <http.Request>[];
      final api = _api(_json([], 200), richieste);
      await api.getOspedali(regione: 'Lombardia');
      expect(richieste.single.url.queryParameters['regione'], 'Lombardia');
    });

    test('regione vuota o solo spazi non viene passata come query', () async {
      final richieste = <http.Request>[];
      final api = _api(_json([], 200), richieste);
      await api.getOspedali(regione: '   ');
      expect(richieste.single.url.queryParameters.containsKey('regione'), isFalse);
    });

    test('parsa l\'elenco ospedali', () async {
      final api = _api(
        _json([
          {'id': '1', 'nome': 'Ospedale A', 'via': 'Via Roma 1', 'citta': 'Milano', 'lat': 45.46, 'lng': 9.19},
          {'id': '2', 'nome': 'Ospedale B', 'citta': 'Milano'},
        ], 200),
        [],
      );
      final lista = await api.getOspedali(citta: 'Milano');
      expect(lista, hasLength(2));
      expect(lista.first['nome'], 'Ospedale A');
      expect(lista.last['via'], isNull);
    });

    test('risposta non-lista lancia BackendApiException', () async {
      final api = _api(_json({'error': 'boom'}, 200), []);
      expect(() => api.getOspedali(), throwsA(isA<BackendApiException>()));
    });

    test('errore HTTP con {"error": ...} riporta il messaggio del server', () async {
      final api = _api(_json({'error': 'fuori servizio'}, 503), []);
      expect(
        () => api.getOspedali(),
        throwsA(isA<BackendApiException>()
            .having((e) => e.message, 'message', contains('503'))
            .having((e) => e.message, 'message', contains('fuori servizio'))),
      );
    });

    test('body d\'errore non JSON non fa crashare', () async {
      final api = _api(http.Response('<html>Bad Gateway</html>', 502), []);
      expect(
        () => api.getOspedali(),
        throwsA(isA<BackendApiException>().having((e) => e.message, 'message', contains('502'))),
      );
    });
  });

  group('verificaConnessione', () {
    test('chiama GET /api/health e restituisce true su 200', () async {
      final richieste = <http.Request>[];
      final api = _api(_json({'status': 'ok'}, 200), richieste);
      expect(await api.verificaConnessione(), isTrue);
      expect(richieste.single.url.toString(), 'https://backend.test/api/health');
    });

    test('restituisce false su un codice diverso da 200 (nessuna eccezione)', () async {
      final api = _api(_json({'error': 'giù'}, 503), []);
      expect(await api.verificaConnessione(), isFalse);
    });

    test('restituisce false se la connessione fallisce (nessuna eccezione propagata)', () async {
      final api = BackendApi(
        baseUrl: 'https://backend.test',
        client: MockClient((req) async => throw Exception('connessione rifiutata')),
      );
      expect(await api.verificaConnessione(), isFalse);
    });
  });

  group('getCitta', () {
    test('chiama GET /api/citta e parsa l\'elenco', () async {
      final richieste = <http.Request>[];
      final api = _api(_json(['Milano', 'Roma'], 200), richieste);
      final citta = await api.getCitta();
      expect(citta, ['Milano', 'Roma']);
      expect(richieste.single.url.toString(), 'https://backend.test/api/citta');
    });

    test('elenco vuoto', () async {
      final api = _api(_json([], 200), []);
      expect(await api.getCitta(), isEmpty);
    });

    test('risposta non-lista lancia BackendApiException', () async {
      final api = _api(_json({'error': 'boom'}, 200), []);
      expect(() => api.getCitta(), throwsA(isA<BackendApiException>()));
    });

    test('errore HTTP riporta il messaggio del server', () async {
      final api = _api(_json({'error': 'fuori servizio'}, 500), []);
      expect(
        () => api.getCitta(),
        throwsA(isA<BackendApiException>().having((e) => e.message, 'message', contains('fuori servizio'))),
      );
    });
  });

  group('getRegioni', () {
    test('chiama GET /api/regioni e parsa l\'elenco', () async {
      final richieste = <http.Request>[];
      final api = _api(_json(['Lombardia', 'Veneto'], 200), richieste);
      final regioni = await api.getRegioni();
      expect(regioni, ['Lombardia', 'Veneto']);
      expect(richieste.single.url.toString(), 'https://backend.test/api/regioni');
    });

    test('errore HTTP riporta il messaggio del server', () async {
      final api = _api(_json({'error': 'fuori servizio'}, 500), []);
      expect(
        () => api.getRegioni(),
        throwsA(isA<BackendApiException>().having((e) => e.message, 'message', contains('fuori servizio'))),
      );
    });
  });

  group('getFogli', () {
    test('chiama GET /api/fogli e restituisce una mappa chiave->url', () async {
      final richieste = <http.Request>[];
      final api = _api(
        _json([
          {'chiave': '2026-07', 'url': 'https://esempio.it/luglio'},
          {'chiave': '2026-06', 'url': 'https://esempio.it/giugno'},
        ], 200),
        richieste,
      );
      final fogli = await api.getFogli();
      expect(fogli, {'2026-07': 'https://esempio.it/luglio', '2026-06': 'https://esempio.it/giugno'});
      expect(richieste.single.url.toString(), 'https://backend.test/api/fogli');
    });

    test('righe senza chiave o url valide vengono ignorate', () async {
      final api = _api(
        _json([
          {'chiave': '2026-07'},
          {'url': 'https://esempio.it/senza-chiave'},
        ], 200),
        [],
      );
      expect(await api.getFogli(), isEmpty);
    });
  });

  group('getMateriali', () {
    test('chiama GET /api/materiali e parsa l\'elenco', () async {
      final richieste = <http.Request>[];
      final api = _api(
        _json([
          {'id': '1', 'nome': 'Garze'},
          {'id': '2', 'nome': 'Guanti'},
        ], 200),
        richieste,
      );
      final lista = await api.getMateriali();
      expect(lista, hasLength(2));
      expect(lista.first['nome'], 'Garze');
      expect(richieste.single.url.toString(), 'https://backend.test/api/materiali');
    });
  });

  group('messaggioErroreBackend', () {
    test('le eccezioni API passano il loro messaggio', () {
      expect(messaggioErroreBackend(const BackendApiException('ciao')), 'ciao');
    });

    test('le altre eccezioni diventano un messaggio di rete generico', () {
      expect(messaggioErroreBackend(Exception('socket')), contains('Impossibile contattare il server'));
    });
  });
}
