// Test del client API del Magazzino Verde (lib/utils/magazzino_api.dart).
// Il server viene simulato con MockClient (package:http/testing): ogni test
// dichiara la risposta e verifica richiesta (URL, header, body) e parsing.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ambu_turni/utils/magazzino_api.dart';

/// Risposta JSON con charset esplicito utf-8 (il client decodifica i
/// bodyBytes come utf8: senza bytes espliciti il test non lo verificherebbe).
http.Response _json(Object body, int status) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status,
        headers: {'content-type': 'application/json; charset=utf-8'});

/// Client puntato a un MockClient che risponde sempre con [risposta],
/// catturando l'ultima richiesta in [richieste].
MagazzinoApi _api(http.Response risposta, List<http.Request> richieste) =>
    MagazzinoApi(
      baseUrl: 'https://magazzino.test',
      apiKey: 'chiave-di-prova',
      client: MockClient((req) async {
        richieste.add(req);
        return risposta;
      }),
    );

void main() {
  group('normalizzaUrl', () {
    test('aggiunge https:// se manca lo schema', () {
      expect(MagazzinoApi.normalizzaUrl('magazzino.esempio.it'),
          'https://magazzino.esempio.it');
    });

    test('rispetta lo schema esplicito (anche http)', () {
      expect(MagazzinoApi.normalizzaUrl('http://192.168.1.10:8080'),
          'http://192.168.1.10:8080');
    });

    test('rimuove gli slash finali', () {
      expect(MagazzinoApi.normalizzaUrl('https://magazzino.test///'),
          'https://magazzino.test');
    });

    test('stringa vuota o spazi restano vuoti', () {
      expect(MagazzinoApi.normalizzaUrl('   '), '');
    });
  });

  group('MaterialeMagazzino', () {
    test('fromMap legge tutti i campi del payload', () {
      final m = MaterialeMagazzino.fromMap({
        'id': 'abc',
        'name': 'maschera pediatrica',
        'description': 'misura S',
        'codes': ['8001234567890', '8009999999999'],
        'alert': 8,
        'amount': 160,
      });
      expect(m.id, 'abc');
      expect(m.nome, 'maschera pediatrica');
      expect(m.descrizione, 'misura S');
      expect(m.codici, ['8001234567890', '8009999999999']);
      expect(m.allerta, 8);
      expect(m.giacenza, 160);
    });

    test('campi assenti o null non fanno crashare il parsing', () {
      final m = MaterialeMagazzino.fromMap({'id': 'x', 'name': 'garze'});
      expect(m.descrizione, '');
      expect(m.codici, isEmpty);
      expect(m.allerta, 0);
      expect(m.giacenza, 0);
    });

    test('sottoScorta usa <= (giacenza uguale alla soglia conta)', () {
      MaterialeMagazzino con(int giacenza) => MaterialeMagazzino(
          id: 'x', nome: 'x', allerta: 5, giacenza: giacenza);
      expect(con(4).sottoScorta, isTrue);
      expect(con(5).sottoScorta, isTrue);
      expect(con(6).sottoScorta, isFalse);
    });
  });

  group('getMateriali', () {
    test('chiama GET /api/v1/materials con l\'header X-API-Key', () async {
      final richieste = <http.Request>[];
      final api = _api(_json([], 200), richieste);
      await api.getMateriali();
      expect(richieste, hasLength(1));
      expect(richieste.first.method, 'GET');
      expect(richieste.first.url.toString(),
          'https://magazzino.test/api/v1/materials');
      expect(richieste.first.headers['X-API-Key'], 'chiave-di-prova');
    });

    test('parsa la lista e la ordina per nome (case-insensitive)', () async {
      final api = _api(
        _json([
          {'id': '1', 'name': 'Zaino', 'amount': 3, 'alert': 1},
          {'id': '2', 'name': 'ambu', 'amount': 2, 'alert': 1},
          {'id': '3', 'name': 'Garze', 'amount': 50, 'alert': 10},
        ], 200),
        [],
      );
      final lista = await api.getMateriali();
      expect(lista.map((m) => m.nome).toList(), ['ambu', 'Garze', 'Zaino']);
    });

    test('decodifica i nomi con accenti come utf8', () async {
      final api = _api(
        _json([
          {'id': '1', 'name': 'cerotti già tagliati', 'amount': 1, 'alert': 0},
        ], 200),
        [],
      );
      final lista = await api.getMateriali();
      expect(lista.single.nome, 'cerotti già tagliati');
    });

    test('401 → messaggio sulla chiave API', () async {
      final api = _api(_json({'error': 'unauthorized'}, 401), []);
      expect(
        () => api.getMateriali(),
        throwsA(isA<MagazzinoApiException>().having(
            (e) => e.message, 'message', contains('Chiave API'))),
      );
    });

    test('503 → messaggio su nessuna chiave configurata sul server', () async {
      final api = _api(_json({'error': 'no key'}, 503), []);
      expect(
        () => api.getMateriali(),
        throwsA(isA<MagazzinoApiException>().having(
            (e) => e.message, 'message', contains('sul server'))),
      );
    });

    test('altri errori riportano codice e messaggio del server', () async {
      final api = _api(_json({'error': 'boom interno'}, 500), []);
      expect(
        () => api.getMateriali(),
        throwsA(isA<MagazzinoApiException>()
            .having((e) => e.message, 'message', contains('500'))
            .having((e) => e.message, 'message', contains('boom interno'))),
      );
    });

    test('body d\'errore non JSON (es. pagina del proxy) non fa crashare',
        () async {
      final api = _api(http.Response('<html>Bad Gateway</html>', 502), []);
      expect(
        () => api.getMateriali(),
        throwsA(isA<MagazzinoApiException>().having(
            (e) => e.message, 'message', contains('502'))),
      );
    });
  });

  group('registraMovimento', () {
    test('POST sull\'endpoint per ID con body {"amount": n}', () async {
      final richieste = <http.Request>[];
      final api = _api(
        _json({'id': 'abc', 'name': 'garze', 'amount': 45, 'alert': 10}, 201),
        richieste,
      );
      final aggiornato = await api.registraMovimento('abc', -5);
      expect(richieste.single.method, 'POST');
      expect(richieste.single.url.toString(),
          'https://magazzino.test/api/v1/materials/abc/transactions');
      expect(richieste.single.headers['X-API-Key'], 'chiave-di-prova');
      expect(richieste.single.headers['content-type'],
          startsWith('application/json'));
      expect(jsonDecode(richieste.single.body), {'amount': -5});
      // Il 201 risponde col materiale aggiornato: la UI lo usa direttamente.
      expect(aggiornato.giacenza, 45);
      expect(aggiornato.nome, 'garze');
    });

    test('404 (codice/materiale inesistente) → messaggio dedicato', () async {
      final api = _api(_json({'error': 'not found'}, 404), []);
      expect(
        () => api.registraMovimento('sconosciuto', 1),
        throwsA(isA<MagazzinoApiException>().having(
            (e) => e.message, 'message', contains('non trovato'))),
      );
    });
  });

  group('messaggioErroreMagazzino', () {
    test('le eccezioni API passano il loro messaggio', () {
      expect(
          messaggioErroreMagazzino(const MagazzinoApiException('ciao')), 'ciao');
    });

    test('le altre eccezioni diventano un messaggio di rete generico', () {
      expect(messaggioErroreMagazzino(Exception('socket')),
          contains('Impossibile contattare il server'));
    });
  });
}
