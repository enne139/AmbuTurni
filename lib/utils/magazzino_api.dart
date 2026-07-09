// Client dell'API JSON di "Magazzino Verde", il gestionale di magazzino
// esterno (progetto Go separato, stessa istanza Gitea del backend). Dart puro
// (niente import Flutter) per lo stesso motivo di piano_mensile.dart: così è
// unit-testabile con un http.Client finto (MockClient), senza server vero.
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Materiale come lo espone l'endpoint `/api/v1/materials` di Magazzino
/// Verde. Campi 1:1 col payload JSON; i nomi Dart sono in italiano per
/// coerenza col resto dell'app (il mapping inglese→italiano vive solo qui).
class MaterialeMagazzino {
  final String id;
  final String nome;
  final String descrizione;
  final List<String> codici; // codici a barre associati
  final int allerta; // soglia di allerta ("alert")
  final int giacenza; // quantità in giacenza ("amount")

  const MaterialeMagazzino({
    required this.id,
    required this.nome,
    this.descrizione = '',
    this.codici = const [],
    this.allerta = 0,
    this.giacenza = 0,
  });

  /// Regola del gestionale: un materiale è "sotto scorta" quando la giacenza
  /// è minore *o uguale* alla soglia (stesso criterio della home web).
  bool get sottoScorta => giacenza <= allerta;

  factory MaterialeMagazzino.fromMap(Map<String, dynamic> map) =>
      MaterialeMagazzino(
        id: map['id'] as String? ?? '',
        nome: map['name'] as String? ?? '',
        descrizione: map['description'] as String? ?? '',
        codici: (map['codes'] as List?)?.whereType<String>().toList() ?? const [],
        allerta: (map['alert'] as num?)?.toInt() ?? 0,
        giacenza: (map['amount'] as num?)?.toInt() ?? 0,
      );
}

/// Errore dell'API con messaggio già pronto da mostrare all'utente.
class MagazzinoApiException implements Exception {
  final String message;
  const MagazzinoApiException(this.message);

  @override
  String toString() => message;
}

/// Traduce una qualunque eccezione delle chiamate API in un messaggio
/// leggibile: le MagazzinoApiException lo sono già, per il resto (DNS,
/// connessione rifiutata, ecc.) si aggiunge una premessa comprensibile.
String messaggioErroreMagazzino(Object e) {
  if (e is MagazzinoApiException) return e.message;
  if (e is TimeoutException) return 'Il server non risponde (timeout).';
  return 'Impossibile contattare il server. ($e)';
}

/// Client minimale dei soli endpoint usati dall'app: lista materiali e
/// registrazione movimenti per ID. La ricerca per codice a barre resta fuori:
/// è pensata per lo scanner sul Raspberry Pi, qui i codici servono solo come
/// campo di ricerca testuale sulla lista già scaricata.
class MagazzinoApi {
  final String baseUrl;
  final String apiKey;
  final http.Client _client;

  // Le risposte sono piccole (JSON di poche decine di materiali): un server
  // che non risponde entro 20s è irraggiungibile, meglio dirlo che lasciare
  // lo spinner all'infinito.
  static const _timeout = Duration(seconds: 20);

  MagazzinoApi({
    required String baseUrl,
    required this.apiKey,
    http.Client? client,
  })  : baseUrl = normalizzaUrl(baseUrl),
        _client = client ?? http.Client();

  /// Normalizza l'URL incollato dall'utente: senza schema si assume https
  /// (il login del gestionale in produzione richiede comunque HTTPS) e si
  /// tolgono gli slash finali per poter concatenare i path degli endpoint.
  static String normalizzaUrl(String url) {
    var u = url.trim();
    if (u.isEmpty) return u;
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'https://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  Map<String, String> get _headers => {'X-API-Key': apiKey};

  /// GET /api/v1/materials — materiali visibili (non archiviati), ordinati
  /// per nome: l'API non garantisce un ordine e la lista in UI deve essere
  /// stabile tra un refresh e l'altro.
  Future<List<MaterialeMagazzino>> getMateriali() async {
    final resp = await _client
        .get(Uri.parse('$baseUrl/api/v1/materials'), headers: _headers)
        .timeout(_timeout);
    if (resp.statusCode != 200) _lanciaErrore(resp);
    final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
    if (decoded is! List) {
      throw const MagazzinoApiException('Risposta del server non riconosciuta.');
    }
    final materiali = decoded
        .whereType<Map>()
        .map((m) => MaterialeMagazzino.fromMap(Map<String, dynamic>.from(m)))
        .toList();
    materiali.sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
    return materiali;
  }

  /// POST /api/v1/materials/{id}/transactions — registra un movimento:
  /// [amount] positivo = carico, negativo = scarico (la giacenza si muove
  /// solo così, mai scrivendola direttamente: lo storico resta coerente).
  /// Restituisce il materiale aggiornato che il server risponde con 201,
  /// così la UI mostra subito la giacenza nuova senza ricaricare la lista.
  Future<MaterialeMagazzino> registraMovimento(
      String materialeId, int amount) async {
    final resp = await _client
        .post(
          Uri.parse('$baseUrl/api/v1/materials/$materialeId/transactions'),
          headers: {..._headers, 'Content-Type': 'application/json'},
          body: jsonEncode({'amount': amount}),
        )
        .timeout(_timeout);
    if (resp.statusCode != 201) _lanciaErrore(resp);
    final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
    if (decoded is! Map) {
      throw const MagazzinoApiException('Risposta del server non riconosciuta.');
    }
    return MaterialeMagazzino.fromMap(Map<String, dynamic>.from(decoded));
  }

  /// Converte una risposta d'errore nel messaggio per l'utente. I codici
  /// documentati dall'API hanno una spiegazione dedicata; per gli altri si
  /// riporta l'eventuale campo {"error": ...} del server.
  Never _lanciaErrore(http.Response resp) {
    switch (resp.statusCode) {
      case 401:
        throw const MagazzinoApiException(
            'Chiave API mancante o errata: controlla la configurazione.');
      case 503:
        throw const MagazzinoApiException(
            'Nessuna chiave API configurata sul server.');
      case 404:
        throw const MagazzinoApiException('Materiale non trovato sul server.');
    }
    String? messaggioServer;
    try {
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      if (decoded is Map && decoded['error'] is String) {
        messaggioServer = decoded['error'] as String;
      }
    } catch (_) {
      // Body non JSON (es. pagina d'errore del reverse proxy): basta il codice.
    }
    throw MagazzinoApiException(
        'Errore del server (${resp.statusCode})'
        '${messaggioServer == null ? '' : ': $messaggioServer'}.');
  }
}
