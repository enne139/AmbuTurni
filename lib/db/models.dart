// Modelli Dart che rispecchiano 1:1 le tabelle del database locale (schema.dart).
// Ogni classe ha fromMap() per leggere dal DB e toMap() per scrivere / fare backup.

class Associazione {
  final String id;
  final String nome;
  final String? createdAt;
  final String? updatedAt;
  final int isSynced;

  const Associazione({
    required this.id,
    required this.nome,
    this.createdAt,
    this.updatedAt,
    this.isSynced = 0,
  });

  factory Associazione.fromMap(Map<String, dynamic> m) => Associazione(
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
  final String? createdAt;
  final String? updatedAt;
  final int isSynced;

  const Ospedale({
    required this.id,
    required this.nome,
    this.citta,
    this.createdAt,
    this.updatedAt,
    this.isSynced = 0,
  });

  /// Etichetta visualizzata: "Nome - Città" oppure solo "Nome".
  String get label => citta != null && citta!.isNotEmpty ? '$nome - $citta' : nome;

  factory Ospedale.fromMap(Map<String, dynamic> m) => Ospedale(
        id: m['id'] as String,
        nome: m['nome'] as String,
        citta: m['citta'] as String?,
        createdAt: m['created_at'] as String?,
        updatedAt: m['updated_at'] as String?,
        isSynced: (m['is_synced'] as int?) ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'nome': nome,
        'citta': citta,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'is_synced': isSynced,
      };
}

class TipologiaTurno {
  final String id;
  final String nome;
  final String? createdAt;
  final String? updatedAt;
  final int isSynced;

  const TipologiaTurno({
    required this.id,
    required this.nome,
    this.createdAt,
    this.updatedAt,
    this.isSynced = 0,
  });

  factory TipologiaTurno.fromMap(Map<String, dynamic> m) => TipologiaTurno(
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
  final String? tipologiaId;
  final List<String> tipologieExtra; // id tipologie aggiuntive
  final int numServizi;
  final String? descrizione;
  final String? note;
  // Equipaggio prima parte
  final String? eq1AutostaId;
  final String? eq1CsId;
  final String? eq1TerzoId;
  final String? eq1QuartoId;
  final String? eq1CentralinistaId;
  // Equipaggio seconda parte
  final String? eq2AutostaId;
  final String? eq2CsId;
  final String? eq2TerzoId;
  final String? eq2QuartoId;
  final String? eq2CentralinistaId;
  final String? createdAt;
  final String? updatedAt;
  final int isSynced;

  // Campi denormalizzati (JOIN) — popolati dalla query lista.
  final String? associazioneNome;
  final String? tipologiaNome;

  const Turno({
    required this.id,
    this.associazioneId,
    this.numeroProgressivo,
    required this.data,
    this.ore,
    this.tipologiaId,
    this.tipologieExtra = const [],
    this.numServizi = 0,
    this.descrizione,
    this.note,
    this.eq1AutostaId,
    this.eq1CsId,
    this.eq1TerzoId,
    this.eq1QuartoId,
    this.eq1CentralinistaId,
    this.eq2AutostaId,
    this.eq2CsId,
    this.eq2TerzoId,
    this.eq2QuartoId,
    this.eq2CentralinistaId,
    this.createdAt,
    this.updatedAt,
    this.isSynced = 0,
    this.associazioneNome,
    this.tipologiaNome,
  });

  factory Turno.fromMap(Map<String, dynamic> m) {
    List<String> extra = [];
    final rawExtra = m['tipologie_extra'];
    if (rawExtra != null && rawExtra is String && rawExtra.isNotEmpty) {
      try {
        // Il campo è salvato come JSON array di stringhe.
        final decoded = (rawExtra as String).replaceAll('[', '').replaceAll(']', '');
        if (decoded.isNotEmpty) {
          extra = decoded.split(',').map((e) => e.trim().replaceAll('"', '')).where((e) => e.isNotEmpty).toList();
        }
      } catch (_) {}
    }
    return Turno(
      id: m['id'] as String,
      associazioneId: m['associazione_id'] as String?,
      numeroProgressivo: m['numero_progressivo'] as int?,
      data: m['data'] as String,
      ore: (m['ore'] as num?)?.toDouble(),
      tipologiaId: m['tipologia_id'] as String?,
      tipologieExtra: extra,
      numServizi: (m['num_servizi'] as int?) ?? 0,
      descrizione: m['descrizione'] as String?,
      note: m['note'] as String?,
      eq1AutostaId: m['eq1_autista_id'] as String?,
      eq1CsId: m['eq1_cs_id'] as String?,
      eq1TerzoId: m['eq1_terzo_id'] as String?,
      eq1QuartoId: m['eq1_quarto_id'] as String?,
      eq1CentralinistaId: m['eq1_centralinista_id'] as String?,
      eq2AutostaId: m['eq2_autista_id'] as String?,
      eq2CsId: m['eq2_cs_id'] as String?,
      eq2TerzoId: m['eq2_terzo_id'] as String?,
      eq2QuartoId: m['eq2_quarto_id'] as String?,
      eq2CentralinistaId: m['eq2_centralinista_id'] as String?,
      createdAt: m['created_at'] as String?,
      updatedAt: m['updated_at'] as String?,
      isSynced: (m['is_synced'] as int?) ?? 0,
      associazioneNome: m['associazione_nome'] as String?,
      tipologiaNome: m['tipologia_nome'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'associazione_id': associazioneId,
        'numero_progressivo': numeroProgressivo,
        'data': data,
        'ore': ore,
        'tipologia_id': tipologiaId,
        'tipologie_extra': '[${tipologieExtra.map((e) => '"$e"').join(',')}]',
        'num_servizi': numServizi,
        'descrizione': descrizione,
        'note': note,
        'eq1_autista_id': eq1AutostaId,
        'eq1_cs_id': eq1CsId,
        'eq1_terzo_id': eq1TerzoId,
        'eq1_quarto_id': eq1QuartoId,
        'eq1_centralinista_id': eq1CentralinistaId,
        'eq2_autista_id': eq2AutostaId,
        'eq2_cs_id': eq2CsId,
        'eq2_terzo_id': eq2TerzoId,
        'eq2_quarto_id': eq2QuartoId,
        'eq2_centralinista_id': eq2CentralinistaId,
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
    String? tipologiaId,
    List<String>? tipologieExtra,
    int? numServizi,
    String? descrizione,
    String? note,
    String? eq1AutostaId,
    String? eq1CsId,
    String? eq1TerzoId,
    String? eq1QuartoId,
    String? eq1CentralinistaId,
    String? eq2AutostaId,
    String? eq2CsId,
    String? eq2TerzoId,
    String? eq2QuartoId,
    String? eq2CentralinistaId,
    String? createdAt,
    String? updatedAt,
    int? isSynced,
  }) => Turno(
        id: id ?? this.id,
        associazioneId: associazioneId ?? this.associazioneId,
        numeroProgressivo: numeroProgressivo ?? this.numeroProgressivo,
        data: data ?? this.data,
        ore: ore ?? this.ore,
        tipologiaId: tipologiaId ?? this.tipologiaId,
        tipologieExtra: tipologieExtra ?? this.tipologieExtra,
        numServizi: numServizi ?? this.numServizi,
        descrizione: descrizione ?? this.descrizione,
        note: note ?? this.note,
        eq1AutostaId: eq1AutostaId ?? this.eq1AutostaId,
        eq1CsId: eq1CsId ?? this.eq1CsId,
        eq1TerzoId: eq1TerzoId ?? this.eq1TerzoId,
        eq1QuartoId: eq1QuartoId ?? this.eq1QuartoId,
        eq1CentralinistaId: eq1CentralinistaId ?? this.eq1CentralinistaId,
        eq2AutostaId: eq2AutostaId ?? this.eq2AutostaId,
        eq2CsId: eq2CsId ?? this.eq2CsId,
        eq2TerzoId: eq2TerzoId ?? this.eq2TerzoId,
        eq2QuartoId: eq2QuartoId ?? this.eq2QuartoId,
        eq2CentralinistaId: eq2CentralinistaId ?? this.eq2CentralinistaId,
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

class Assistenza {
  final String id;
  final String? associazioneId;
  final int? numeroProgressivo;
  final String data;
  final double? ore;
  final String? descrizione;
  final String? note;
  final String? eq1AutostaId;
  final String? eq1CsId;
  final String? eq1TerzoId;
  final String? eq1QuartoId;
  final String? eq1CentralinistaId;
  final String? eq2AutostaId;
  final String? eq2CsId;
  final String? eq2TerzoId;
  final String? eq2QuartoId;
  final String? eq2CentralinistaId;
  final String? createdAt;
  final String? updatedAt;
  final int isSynced;

  final String? associazioneNome;

  const Assistenza({
    required this.id,
    this.associazioneId,
    this.numeroProgressivo,
    required this.data,
    this.ore,
    this.descrizione,
    this.note,
    this.eq1AutostaId,
    this.eq1CsId,
    this.eq1TerzoId,
    this.eq1QuartoId,
    this.eq1CentralinistaId,
    this.eq2AutostaId,
    this.eq2CsId,
    this.eq2TerzoId,
    this.eq2QuartoId,
    this.eq2CentralinistaId,
    this.createdAt,
    this.updatedAt,
    this.isSynced = 0,
    this.associazioneNome,
  });

  factory Assistenza.fromMap(Map<String, dynamic> m) => Assistenza(
        id: m['id'] as String,
        associazioneId: m['associazione_id'] as String?,
        numeroProgressivo: m['numero_progressivo'] as int?,
        data: m['data'] as String,
        ore: (m['ore'] as num?)?.toDouble(),
        descrizione: m['descrizione'] as String?,
        note: m['note'] as String?,
        eq1AutostaId: m['eq1_autista_id'] as String?,
        eq1CsId: m['eq1_cs_id'] as String?,
        eq1TerzoId: m['eq1_terzo_id'] as String?,
        eq1QuartoId: m['eq1_quarto_id'] as String?,
        eq1CentralinistaId: m['eq1_centralinista_id'] as String?,
        eq2AutostaId: m['eq2_autista_id'] as String?,
        eq2CsId: m['eq2_cs_id'] as String?,
        eq2TerzoId: m['eq2_terzo_id'] as String?,
        eq2QuartoId: m['eq2_quarto_id'] as String?,
        eq2CentralinistaId: m['eq2_centralinista_id'] as String?,
        createdAt: m['created_at'] as String?,
        updatedAt: m['updated_at'] as String?,
        isSynced: (m['is_synced'] as int?) ?? 0,
        associazioneNome: m['associazione_nome'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'associazione_id': associazioneId,
        'numero_progressivo': numeroProgressivo,
        'data': data,
        'ore': ore,
        'descrizione': descrizione,
        'note': note,
        'eq1_autista_id': eq1AutostaId,
        'eq1_cs_id': eq1CsId,
        'eq1_terzo_id': eq1TerzoId,
        'eq1_quarto_id': eq1QuartoId,
        'eq1_centralinista_id': eq1CentralinistaId,
        'eq2_autista_id': eq2AutostaId,
        'eq2_cs_id': eq2CsId,
        'eq2_terzo_id': eq2TerzoId,
        'eq2_quarto_id': eq2QuartoId,
        'eq2_centralinista_id': eq2CentralinistaId,
        'created_at': createdAt,
        'updated_at': updatedAt,
        'is_synced': isSynced,
      };
}
