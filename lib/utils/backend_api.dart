// Client del backend condiviso ospedali (backend/, Go): un'unica istanza
// gestita centralmente (default in utils/prefs_keys.dart, kBackendUrlDefault)
// da cui i client scaricano l'elenco ospedali filtrato per città. Dart puro
// (niente import Flutter), come magazzino_api.dart/geocoding_api.dart, per
// essere unit-testabile con un http.Client finto (MockClient).
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Errore dell'API con messaggio già pronto da mostrare all'utente.
class BackendApiException implements Exception {
  final String message;
  const BackendApiException(this.message);

  @override
  String toString() => message;
}

/// Traduce una qualunque eccezione della chiamata in un messaggio leggibile.
String messaggioErroreBackend(Object e) {
  if (e is BackendApiException) return e.message;
  if (e is TimeoutException) return 'Il server non risponde (timeout).';
  return 'Impossibile contattare il server. ($e)';
}

/// Client minimale dell'unico endpoint usato dall'app: l'elenco ospedali
/// (pubblico, nessuna chiave/login — quelli servono solo alla pagina admin
/// del backend per aggiungerli).
class BackendApi {
  final String baseUrl;
  final http.Client _client;

  static const _timeout = Duration(seconds: 20);
  // Più corto del timeout delle chiamate vere: usato solo per il pulsante
  // "verifica" nel dialog di configurazione, che non deve far aspettare
  // l'utente a lungo per scoprire che l'indirizzo è sbagliato.
  static const _timeoutVerifica = Duration(seconds: 8);

  BackendApi({required String baseUrl, http.Client? client})
      : baseUrl = normalizzaUrl(baseUrl),
        _client = client ?? http.Client();

  /// Normalizza l'URL configurato: senza schema si assume https, si tolgono
  /// gli slash finali per poter concatenare il path dell'endpoint (stesso
  /// pattern di MagazzinoApi.normalizzaUrl).
  static String normalizzaUrl(String url) {
    var u = url.trim();
    if (u.isEmpty) return u;
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'https://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  /// GET /api/health — true se il server risponde. Non lancia mai eccezioni
  /// (a differenza degli altri metodi): usata solo per il pulsante "verifica"
  /// nel dialog di configurazione, dove serve un semplice sì/no, non un
  /// messaggio d'errore dettagliato.
  Future<bool> verificaConnessione() async {
    try {
      final resp = await _client.get(Uri.parse('$baseUrl/api/health')).timeout(_timeoutVerifica);
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// GET /api/ospedali — elenco ospedali (nome/via/citta/lat/lng, stesso
  /// formato di db/backup.dart), filtrato per città se indicata.
  Future<List<Map<String, dynamic>>> getOspedali({String? citta}) async {
    final query = (citta != null && citta.trim().isNotEmpty) ? {'citta': citta.trim()} : null;
    final uri = Uri.parse('$baseUrl/api/ospedali').replace(queryParameters: query);
    final resp = await _client.get(uri).timeout(_timeout);
    if (resp.statusCode != 200) _lanciaErrore(resp);
    final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
    if (decoded is! List) {
      throw const BackendApiException('Risposta del server non riconosciuta.');
    }
    return decoded.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  }

  /// GET /api/citta — città che hanno almeno un ospedale, ordinate
  /// alfabeticamente: usata per mostrare un elenco selezionabile invece di
  /// far digitare alla cieca un nome città in "Scarica ospedali per città".
  Future<List<String>> getCitta() async {
    final resp = await _client.get(Uri.parse('$baseUrl/api/citta')).timeout(_timeout);
    if (resp.statusCode != 200) _lanciaErrore(resp);
    final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
    if (decoded is! List) {
      throw const BackendApiException('Risposta del server non riconosciuta.');
    }
    return decoded.whereType<String>().toList();
  }

  Never _lanciaErrore(http.Response resp) {
    String? messaggioServer;
    try {
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      if (decoded is Map && decoded['error'] is String) {
        messaggioServer = decoded['error'] as String;
      }
    } catch (_) {
      // Body non JSON (es. pagina d'errore del reverse proxy): basta il codice.
    }
    throw BackendApiException(
        'Errore del server (${resp.statusCode})'
        '${messaggioServer == null ? '' : ': $messaggioServer'}.');
  }
}
