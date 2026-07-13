// Modelli Dart che rispecchiano 1:1 le tabelle del database locale (schema.dart).
// Ogni classe ha fromMap() per leggere dal DB e toMap() per scrivere / fare backup.
import 'dart:convert';

class Associazione {
  final String id;
  final String nome;
  final String? colore;
  final String? createdAt;
  final String? updatedAt;
  final int isSynced;

  const Associazione({
    required this.id,
    required this.nome,
    this.colore,
    this.createdAt,
    this.updatedAt,
    this.isSynced = 0,
  });

  factory Associazione.fromMap(Map<String, dynamic> m) => Associazione(
        id: m['id'] as String,
        nome: m['nome'] as String,
        colore: m['colore'] as String?,
        createdAt: m['created_at'] as String?,
        updatedAt: m['updated_at'] as String?,
        isSynced: (m['is_synced'] as int?) ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'nome': nome,
        'colore': colore,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'is_synced': isSynced,
      };
}

class Persona {
  final String id;
  final String nome;
  final String cognome;
  final String? createdAt;
  final String? updatedAt;
  final int isSynced;

  const Persona({
    required this.id,
    required this.nome,
    required this.cognome,
    this.createdAt,
    this.updatedAt,
    this.isSynced = 0,
  });

  /// Restituisce "Cognome Nome" per la visualizzazione nelle liste.
  String get nomeCompleto => '$cognome $nome';

  factory Persona.fromMap(Map<String, dynamic> m) => Persona(
        id: m['id'] as String,
        nome: m['nome'] as String,
        cognome: m['cognome'] as String,
        createdAt: m['created_at'] as String?,
        updatedAt: m['updated_at'] as String?,
        isSynced: (m['is_synced'] as int?) ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'nome': nome,
        'cognome': cognome,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'is_synced': isSynced,
      };
}

class Ospedale {
  final String id;
  final String nome;
  final String? citta;
  final String? via;
  // Coordinate da geocoding automatico (tool Lista ospedali): null finché
  // non risolte o se l'indirizzo non è geocodificabile — l'ospedale resta
  // comunque utilizzabile ovunque, semplicemente non compare sulla mappa.
  final double? lat;
  final double? lng;
  final String? createdAt;
  final String? updatedAt;
  final int isSynced;

  const Ospedale({
    required this.id,
    required this.nome,
    this.citta,
    this.via,
    this.lat,
    this.lng,
    this.createdAt,
    this.updatedAt,
    this.isSynced = 0,
  });

  /// Etichetta visualizzata: "Nome - Città" oppure solo "Nome".
  String get label => citta != null && citta!.isNotEmpty ? '$nome - $citta' : nome;

  bool get haCoordinate => lat != null && lng != null;

  factory Ospedale.fromMap(Map<String, dynamic> m) => Ospedale(
        id: m['id'] as String,
        nome: m['nome'] as String,
        citta: m['citta'] as String?,
        via: m['via'] as String?,
        lat: (m['lat'] as num?)?.toDouble(),
        lng: (m['lng'] as num?)?.toDouble(),
        createdAt: m['created_at'] as String?,
        updatedAt: m['updated_at'] as String?,
        isSynced: (m['is_synced'] as int?) ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'nome': nome,
        'citta': citta,
        'via': via,
        'lat': lat,
        'lng': lng,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'is_synced': isSynced,
      };
}

class TipologiaTurno {
  final String id;
  final String nome;
  final int ordine;
  final String? colore;
  final String? createdAt;
  final String? updatedAt;
  final int isSynced;

  const TipologiaTurno({
    required this.id,
    required this.nome,
    this.ordine = 0,
    this.colore,
    this.createdAt,
    this.updatedAt,
    this.isSynced = 0,
  });

  factory TipologiaTurno.fromMap(Map<String, dynamic> m) => TipologiaTurno(
        id: m['id'] as String,
        nome: m['nome'] as String,
        ordine: (m['ordine'] as int?) ?? 0,
        colore: m['colore'] as String?,
        createdAt: m['created_at'] as String?,
        updatedAt: m['updated_at'] as String?,
        isSynced: (m['is_synced'] as int?) ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'nome': nome,
        'ordine': ordine,
        'colore': colore,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'is_synced': isSynced,
      };
}

// Equipaggio: 5 ruoli per parte (autista, CS, terzo, quarto, centralinista).
// I campi sono nullable — solo i presenti vengono salvati.
class Equipaggio {
  final String? autista;
  final String? cs;
  final String? terzo;
  final String? quarto;
  final String? centralinista;

  const Equipaggio({
    this.autista,
    this.cs,
    this.terzo,
    this.quarto,
    this.centralinista,
  });

  bool get isEmpty =>
      autista == null &&
      cs == null &&
      terzo == null &&
      quarto == null &&
      centralinista == null;

  /// Restituisce lista degli id presenti (non null).
  List<String> get ids => [
        if (autista != null) autista!,
        if (cs != null) cs!,
        if (terzo != null) terzo!,
        if (quarto != null) quarto!,
        if (centralinista != null) centralinista!,
      ];
}

class Turno {
  final String id;
  final String? associazioneId;
  final int? numeroProgressivo;
  final String data;
  final double? ore;
  // Id delle tipologie del turno (multi-valore, v8): la vecchia distinzione
  // tipologia_id/tipologie_extra esisteva solo per compatibilità con lo schema
  // dell'app React Native, ormai dismessa. I nomi si risolvono via
  // AnagraficheProvider.byIdTipologia nelle schermate.
  final List<String> tipologie;
  final int numServizi;
  final String? descrizione;
  final String? note;
  // Equipaggio prima parte
  final String? eq1AutistaId;
  final String? eq1CsId;
  final String? eq1TerzoId;
  final String? eq1QuartoId;
  final String? eq1CentralinistaId;
  // Equipaggio seconda parte
  final String? eq2AutistaId;
  final String? eq2CsId;
  final String? eq2TerzoId;
  final String? eq2QuartoId;
  final String? eq2CentralinistaId;
  // true se l'equipaggio è cambiato a metà turno (1ª e 2ª parte diverse).
  final bool cambioMeta;
  final String? createdAt;
  final String? updatedAt;
  final int isSynced;

  // Campi denormalizzati (JOIN) — popolati dalla query lista.
  final String? associazioneNome;
  final String? associazioneColore;

  const Turno({
    required this.id,
    this.associazioneId,
    this.numeroProgressivo,
    required this.data,
    this.ore,
    this.tipologie = const [],
    this.numServizi = 0,
    this.descrizione,
    this.note,
    this.eq1AutistaId,
    this.eq1CsId,
    this.eq1TerzoId,
    this.eq1QuartoId,
    this.eq1CentralinistaId,
    this.eq2AutistaId,
    this.eq2CsId,
    this.eq2TerzoId,
    this.eq2QuartoId,
    this.eq2CentralinistaId,
    this.cambioMeta = false,
    this.createdAt,
    this.updatedAt,
    this.isSynced = 0,
    this.associazioneNome,
    this.associazioneColore,
  });

  factory Turno.fromMap(Map<String, dynamic> m) {
    List<String> tipologie = [];
    final rawTipologie = m['tipologie'];
    if (rawTipologie is String && rawTipologie.isNotEmpty) {
      // Il campo è un array JSON di stringhe: jsonDecode al posto del vecchio
      // parsing manuale con replaceAll/split, fragile e duplicato. Il catch
      // copre eventuali valori corrotti/legacy senza far crashare la lettura.
      try {
        final decoded = jsonDecode(rawTipologie);
        if (decoded is List) {
          tipologie = decoded.whereType<String>().toList();
        }
      } catch (_) {}
    }
    return Turno(
      id: m['id'] as String,
      associazioneId: m['associazione_id'] as String?,
      numeroProgressivo: m['numero_progressivo'] as int?,
      data: m['data'] as String,
      ore: (m['ore'] as num?)?.toDouble(),
      tipologie: tipologie,
      numServizi: (m['num_servizi'] as int?) ?? 0,
      descrizione: m['descrizione'] as String?,
      note: m['note'] as String?,
      eq1AutistaId: m['eq1_autista_id'] as String?,
      eq1CsId: m['eq1_cs_id'] as String?,
      eq1TerzoId: m['eq1_terzo_id'] as String?,
      eq1QuartoId: m['eq1_quarto_id'] as String?,
      eq1CentralinistaId: m['eq1_centralinista_id'] as String?,
      eq2AutistaId: m['eq2_autista_id'] as String?,
      eq2CsId: m['eq2_cs_id'] as String?,
      eq2TerzoId: m['eq2_terzo_id'] as String?,
      eq2QuartoId: m['eq2_quarto_id'] as String?,
      eq2CentralinistaId: m['eq2_centralinista_id'] as String?,
      cambioMeta: ((m['cambio_meta'] as int?) ?? 0) == 1,
      createdAt: m['created_at'] as String?,
      updatedAt: m['updated_at'] as String?,
      isSynced: (m['is_synced'] as int?) ?? 0,
      associazioneNome: m['associazione_nome'] as String?,
      associazioneColore: m['associazione_colore'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'associazione_id': associazioneId,
        'numero_progressivo': numeroProgressivo,
        'data': data,
        'ore': ore,
        'tipologie': jsonEncode(tipologie),
        'num_servizi': numServizi,
        'descrizione': descrizione,
        'note': note,
        'eq1_autista_id': eq1AutistaId,
        'eq1_cs_id': eq1CsId,
        'eq1_terzo_id': eq1TerzoId,
        'eq1_quarto_id': eq1QuartoId,
        'eq1_centralinista_id': eq1CentralinistaId,
        'eq2_autista_id': eq2AutistaId,
        'eq2_cs_id': eq2CsId,
        'eq2_terzo_id': eq2TerzoId,
        'eq2_quarto_id': eq2QuartoId,
        'eq2_centralinista_id': eq2CentralinistaId,
        'cambio_meta': cambioMeta ? 1 : 0,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'is_synced': isSynced,
      };

  Turno copyWith({
    String? id,
    String? associazioneId,
    int? numeroProgressivo,
    String? data,
    double? ore,
    List<String>? tipologie,
    int? numServizi,
    String? descrizione,
    String? note,
    String? eq1AutistaId,
    String? eq1CsId,
    String? eq1TerzoId,
    String? eq1QuartoId,
    String? eq1CentralinistaId,
    String? eq2AutistaId,
    String? eq2CsId,
    String? eq2TerzoId,
    String? eq2QuartoId,
    String? eq2CentralinistaId,
    bool? cambioMeta,
    String? createdAt,
    String? updatedAt,
    int? isSynced,
  }) => Turno(
        id: id ?? this.id,
        associazioneId: associazioneId ?? this.associazioneId,
        numeroProgressivo: numeroProgressivo ?? this.numeroProgressivo,
        data: data ?? this.data,
        ore: ore ?? this.ore,
        tipologie: tipologie ?? this.tipologie,
        numServizi: numServizi ?? this.numServizi,
        descrizione: descrizione ?? this.descrizione,
        note: note ?? this.note,
        eq1AutistaId: eq1AutistaId ?? this.eq1AutistaId,
        eq1CsId: eq1CsId ?? this.eq1CsId,
        eq1TerzoId: eq1TerzoId ?? this.eq1TerzoId,
        eq1QuartoId: eq1QuartoId ?? this.eq1QuartoId,
        eq1CentralinistaId: eq1CentralinistaId ?? this.eq1CentralinistaId,
        eq2AutistaId: eq2AutistaId ?? this.eq2AutistaId,
        eq2CsId: eq2CsId ?? this.eq2CsId,
        eq2TerzoId: eq2TerzoId ?? this.eq2TerzoId,
        eq2QuartoId: eq2QuartoId ?? this.eq2QuartoId,
        eq2CentralinistaId: eq2CentralinistaId ?? this.eq2CentralinistaId,
        cambioMeta: cambioMeta ?? this.cambioMeta,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        isSynced: isSynced ?? this.isSynced,
      );
}

// Codici validi per chiamata e uscita del servizio.
const List<String> codiciChiamata = ['VERDE', 'GIALLO', 'ROSSO', 'DIMISSIONE'];
const List<String> codiciUscita = ['VERDE', 'GIALLO', 'ROSSO', 'NERO', 'VUOTO', 'RIFIUTO'];

class Servizio {
  final String id;
  final String turnoId;
  final String? codiceChiamata;
  final String? codiceUscita;
  final String? ospedaleId;
  final String? descrizione;
  final int ordine;
  final String? createdAt;
  final String? updatedAt;
  final int isSynced;

  // Campi denormalizzati (JOIN) dalla query.
  final String? ospedaleNome;
  final String? ospedaleCitta;

  const Servizio({
    required this.id,
    required this.turnoId,
    this.codiceChiamata,
    this.codiceUscita,
    this.ospedaleId,
    this.descrizione,
    this.ordine = 0,
    this.createdAt,
    this.updatedAt,
    this.isSynced = 0,
    this.ospedaleNome,
    this.ospedaleCitta,
  });

  factory Servizio.fromMap(Map<String, dynamic> m) => Servizio(
        id: m['id'] as String,
        turnoId: m['turno_id'] as String,
        codiceChiamata: m['codice_chiamata'] as String?,
        codiceUscita: m['codice_uscita'] as String?,
        ospedaleId: m['ospedale_id'] as String?,
        descrizione: m['descrizione'] as String?,
        ordine: (m['ordine'] as int?) ?? 0,
        createdAt: m['created_at'] as String?,
        updatedAt: m['updated_at'] as String?,
        isSynced: (m['is_synced'] as int?) ?? 0,
        ospedaleNome: m['ospedale_nome'] as String?,
        ospedaleCitta: m['ospedale_citta'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'turno_id': turnoId,
        'codice_chiamata': codiceChiamata,
        'codice_uscita': codiceUscita,
        'ospedale_id': ospedaleId,
        'descrizione': descrizione,
        'ordine': ordine,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'is_synced': isSynced,
      };
}

// ---------------------------------------------------------------------------
// TOOLS -> MATERIALI USATI
// ---------------------------------------------------------------------------

class Materiale {
  final String id;
  final String nome;
  final String? createdAt;
  final String? updatedAt;
  final int isSynced;

  const Materiale({
    required this.id,
    required this.nome,
    this.createdAt,
    this.updatedAt,
    this.isSynced = 0,
  });

  factory Materiale.fromMap(Map<String, dynamic> m) => Materiale(
        id: m['id'] as String,
        nome: m['nome'] as String,
        createdAt: m['created_at'] as String?,
        updatedAt: m['updated_at'] as String?,
        isSynced: (m['is_synced'] as int?) ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'nome': nome,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'is_synced': isSynced,
      };
}

// Posizioni valide per un utilizzo di materiale (dove si trovava/va ripristinato).
const List<String> posizioniMateriale = ['AMBULANZA', 'BOMBOLINO', 'ZAINO'];

/// Un utilizzo di materiale da ripristinare. `quantita` è numerica (incrementabile
/// con i pulsanti +/- in lista) mentre `unita` è testo libero separato, perché in
/// ambulanza le unità di misura sono eterogenee (es. "flaconi", "ml", "confezioni")
/// e un unico campo numerico non le rappresenterebbe. Nessuno storico: una riga
/// esiste solo finché non viene ripristinata o eliminata (vedi helpers.dart).
class MaterialeUsato {
  final String id;
  final String materialeId;
  final int quantita;
  final String? unita;
  final String? posizione;
  final String? note;
  final String? createdAt;
  final String? updatedAt;
  final int isSynced;

  // Denormalizzato dal JOIN con materiali.
  final String? materialeNome;

  const MaterialeUsato({
    required this.id,
    required this.materialeId,
    this.quantita = 1,
    this.unita,
    this.posizione,
    this.note,
    this.createdAt,
    this.updatedAt,
    this.isSynced = 0,
    this.materialeNome,
  });

  /// Etichetta quantità + unità per la visualizzazione (es. "3 flaconi", "500 ml", "2").
  String get quantitaLabel => unita != null && unita!.isNotEmpty ? '$quantita $unita' : '$quantita';

  factory MaterialeUsato.fromMap(Map<String, dynamic> m) => MaterialeUsato(
        id: m['id'] as String,
        materialeId: m['materiale_id'] as String,
        quantita: (m['quantita'] as num?)?.toInt() ?? 1,
        unita: m['unita'] as String?,
        posizione: m['posizione'] as String?,
        note: m['note'] as String?,
        createdAt: m['created_at'] as String?,
        updatedAt: m['updated_at'] as String?,
        isSynced: (m['is_synced'] as int?) ?? 0,
        materialeNome: m['materiale_nome'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'materiale_id': materialeId,
        'quantita': quantita,
        'unita': unita,
        'posizione': posizione,
        'note': note,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'is_synced': isSynced,
      };

  MaterialeUsato copyWith({int? quantita}) => MaterialeUsato(
        id: id,
        materialeId: materialeId,
        quantita: quantita ?? this.quantita,
        unita: unita,
        posizione: posizione,
        note: note,
        createdAt: createdAt,
        updatedAt: updatedAt,
        isSynced: isSynced,
        materialeNome: materialeNome,
      );
}

class Assistenza {
  final String id;
  final String? associazioneId;
  final int? numeroProgressivo;
  final String data;
  final double? ore;
  final String? descrizione;
  final String? note;
  final String? eq1AutistaId;
  final String? eq1CsId;
  final String? eq1TerzoId;
  final String? eq1QuartoId;
  final String? eq1CentralinistaId;
  final String? eq2AutistaId;
  final String? eq2CsId;
  final String? eq2TerzoId;
  final String? eq2QuartoId;
  final String? eq2CentralinistaId;
  final String? createdAt;
  final String? updatedAt;
  final int isSynced;

  final String? associazioneNome;
  // Denormalizzato dal JOIN con associazioni (come in Turno): serve ai
  // pallini della vista calendario. Non entra in toMap.
  final String? associazioneColore;

  const Assistenza({
    required this.id,
    this.associazioneId,
    this.numeroProgressivo,
    required this.data,
    this.ore,
    this.descrizione,
    this.note,
    this.eq1AutistaId,
    this.eq1CsId,
    this.eq1TerzoId,
    this.eq1QuartoId,
    this.eq1CentralinistaId,
    this.eq2AutistaId,
    this.eq2CsId,
    this.eq2TerzoId,
    this.eq2QuartoId,
    this.eq2CentralinistaId,
    this.createdAt,
    this.updatedAt,
    this.isSynced = 0,
    this.associazioneNome,
    this.associazioneColore,
  });

  factory Assistenza.fromMap(Map<String, dynamic> m) => Assistenza(
        id: m['id'] as String,
        associazioneId: m['associazione_id'] as String?,
        numeroProgressivo: m['numero_progressivo'] as int?,
        data: m['data'] as String,
        ore: (m['ore'] as num?)?.toDouble(),
        descrizione: m['descrizione'] as String?,
        note: m['note'] as String?,
        eq1AutistaId: m['eq1_autista_id'] as String?,
        eq1CsId: m['eq1_cs_id'] as String?,
        eq1TerzoId: m['eq1_terzo_id'] as String?,
        eq1QuartoId: m['eq1_quarto_id'] as String?,
        eq1CentralinistaId: m['eq1_centralinista_id'] as String?,
        eq2AutistaId: m['eq2_autista_id'] as String?,
        eq2CsId: m['eq2_cs_id'] as String?,
        eq2TerzoId: m['eq2_terzo_id'] as String?,
        eq2QuartoId: m['eq2_quarto_id'] as String?,
        eq2CentralinistaId: m['eq2_centralinista_id'] as String?,
        createdAt: m['created_at'] as String?,
        updatedAt: m['updated_at'] as String?,
        isSynced: (m['is_synced'] as int?) ?? 0,
        associazioneNome: m['associazione_nome'] as String?,
        associazioneColore: m['associazione_colore'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'associazione_id': associazioneId,
        'numero_progressivo': numeroProgressivo,
        'data': data,
        'ore': ore,
        'descrizione': descrizione,
        'note': note,
        'eq1_autista_id': eq1AutistaId,
        'eq1_cs_id': eq1CsId,
        'eq1_terzo_id': eq1TerzoId,
        'eq1_quarto_id': eq1QuartoId,
        'eq1_centralinista_id': eq1CentralinistaId,
        'eq2_autista_id': eq2AutistaId,
        'eq2_cs_id': eq2CsId,
        'eq2_terzo_id': eq2TerzoId,
        'eq2_quarto_id': eq2QuartoId,
        'eq2_centralinista_id': eq2CentralinistaId,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'is_synced': isSynced,
      };
}
