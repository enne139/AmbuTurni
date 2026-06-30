import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'database.dart';
import 'models.dart';

// Generatore UUID usato per tutti gli id locali.
const _uuid = Uuid();
String newId() => _uuid.v4();

String _now() => DateTime.now().toUtc().toIso8601String();

// ---------------------------------------------------------------------------
// ANAGRAFICHE
// ---------------------------------------------------------------------------

Future<List<Associazione>> getAssociazioni() async {
  final db = await getDb();
  final rows = await db.query('associazioni', orderBy: 'nome ASC');
  return rows.map(Associazione.fromMap).toList();
}

Future<void> saveAssociazione(String nome, {String? id}) async {
  final db = await getDb();
  final now = _now();
  if (id == null) {
    await db.insert('associazioni', {
      'id': newId(),
      'nome': nome,
      'created_at': now,
      'updated_at': now,
      'is_synced': 0,
    });
  } else {
    await db.update(
      'associazioni',
      {'nome': nome, 'updated_at': now, 'is_synced': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

Future<void> deleteAssociazione(String id) async {
  final db = await getDb();
  await db.delete('associazioni', where: 'id = ?', whereArgs: [id]);
}

Future<List<Persona>> getPersone() async {
  final db = await getDb();
  final rows = await db.query('persone', orderBy: 'cognome ASC, nome ASC');
  return rows.map(Persona.fromMap).toList();
}

Future<void> savePersona(String cognome, String nome, {String? id}) async {
  final db = await getDb();
  final now = _now();
  if (id == null) {
    await db.insert('persone', {
      'id': newId(),
      'cognome': cognome,
      'nome': nome,
      'created_at': now,
      'updated_at': now,
      'is_synced': 0,
    });
  } else {
    await db.update(
      'persone',
      {'cognome': cognome, 'nome': nome, 'updated_at': now, 'is_synced': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

Future<void> deletePersona(String id) async {
  final db = await getDb();
  await db.delete('persone', where: 'id = ?', whereArgs: [id]);
}

Future<List<Ospedale>> getOspedali() async {
  final db = await getDb();
  final rows = await db.query('ospedali', orderBy: 'nome ASC');
  return rows.map(Ospedale.fromMap).toList();
}

Future<void> saveOspedale(String nome, String? citta, {String? id}) async {
  final db = await getDb();
  final now = _now();
  if (id == null) {
    await db.insert('ospedali', {
      'id': newId(),
      'nome': nome,
      'citta': citta,
      'created_at': now,
      'updated_at': now,
      'is_synced': 0,
    });
  } else {
    await db.update(
      'ospedali',
      {'nome': nome, 'citta': citta, 'updated_at': now, 'is_synced': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

Future<void> deleteOspedale(String id) async {
  final db = await getDb();
  await db.delete('ospedali', where: 'id = ?', whereArgs: [id]);
}

Future<List<TipologiaTurno>> getTipologieTurno() async {
  final db = await getDb();
  final rows = await db.query('tipologie_turno', orderBy: 'nome ASC');
  return rows.map(TipologiaTurno.fromMap).toList();
}

Future<void> saveTipologiaTurno(String nome, {String? id}) async {
  final db = await getDb();
  final now = _now();
  if (id == null) {
    await db.insert('tipologie_turno', {
      'id': newId(),
      'nome': nome,
      'created_at': now,
      'updated_at': now,
      'is_synced': 0,
    });
  } else {
    await db.update(
      'tipologie_turno',
      {'nome': nome, 'updated_at': now, 'is_synced': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

// ---------------------------------------------------------------------------
// TURNI
// ---------------------------------------------------------------------------

/// Restituisce i turni ordinati per data decrescente, con JOIN su associazione
/// e tipologia per avere i nomi già disponibili senza query aggiuntive.
Future<List<Turno>> getTurni({String? associazioneId}) async {
  final db = await getDb();
  final where = associazioneId != null ? 'WHERE t.associazione_id = ?' : '';
  final args = associazioneId != null ? [associazioneId] : [];
  final rows = await db.rawQuery('''
    SELECT t.*,
           a.nome AS associazione_nome,
           tp.nome AS tipologia_nome
    FROM turni t
    LEFT JOIN associazioni a ON a.id = t.associazione_id
    LEFT JOIN tipologie_turno tp ON tp.id = t.tipologia_id
    $where
    ORDER BY t.data DESC, t.created_at DESC
  ''', args);
  return rows.map(Turno.fromMap).toList();
}

Future<Turno?> getTurnoById(String id) async {
  final db = await getDb();
  final rows = await db.rawQuery('''
    SELECT t.*,
           a.nome AS associazione_nome,
           tp.nome AS tipologia_nome
    FROM turni t
    LEFT JOIN associazioni a ON a.id = t.associazione_id
    LEFT JOIN tipologie_turno tp ON tp.id = t.tipologia_id
    WHERE t.id = ?
  ''', [id]);
  if (rows.isEmpty) return null;
  return Turno.fromMap(rows.first);
}

/// Salva (insert o update) un turno e ricalcola la numerazione progressiva.
Future<void> saveTurno(Turno turno) async {
  final db = await getDb();
  final now = _now();
  final map = turno.toMap()..['updated_at'] = now..['is_synced'] = 0;
  await db.insert(
    'turni',
    map,
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
  await _ricalcolaNumerazioneTurni(db, turno.associazioneId);
}

Future<void> deleteTurno(String id) async {
  final db = await getDb();
  // Legge associazione_id prima di cancellare per ricalcolare.
  final rows = await db.query('turni', columns: ['associazione_id'], where: 'id = ?', whereArgs: [id]);
  final assocId = rows.isNotEmpty ? rows.first['associazione_id'] as String? : null;
  await db.delete('turni', where: 'id = ?', whereArgs: [id]);
  await _ricalcolaNumerazioneTurni(db, assocId);
}

/// Ricalcola numero_progressivo per tutti i turni di una associazione,
/// ordinati per data crescente (il più vecchio = #1).
Future<void> _ricalcolaNumerazioneTurni(dynamic db, String? assocId) async {
  if (assocId == null) return;
  final rows = await db.query(
    'turni',
    columns: ['id'],
    where: 'associazione_id = ?',
    whereArgs: [assocId],
    orderBy: 'data ASC, created_at ASC',
  );
  for (int i = 0; i < rows.length; i++) {
    await db.update(
      'turni',
      {'numero_progressivo': i + 1},
      where: 'id = ?',
      whereArgs: [rows[i]['id']],
    );
  }
}

// ---------------------------------------------------------------------------
// SERVIZI
// ---------------------------------------------------------------------------

/// Restituisce i servizi di un turno con JOIN sull'ospedale, ordinati per ordine.
Future<List<Servizio>> getServizi(String turnoId) async {
  final db = await getDb();
  final rows = await db.rawQuery('''
    SELECT s.*,
           o.nome AS ospedale_nome,
           o.citta AS ospedale_citta
    FROM servizi s
    LEFT JOIN ospedali o ON o.id = s.ospedale_id
    WHERE s.turno_id = ?
    ORDER BY s.ordine ASC
  ''', [turnoId]);
  return rows.map(Servizio.fromMap).toList();
}

Future<void> saveServizio(Servizio servizio) async {
  final db = await getDb();
  final now = _now();
  final map = servizio.toMap()..['updated_at'] = now..['is_synced'] = 0;
  await db.insert('servizi', map, conflictAlgorithm: ConflictAlgorithm.replace);
  await _aggiornaNumServizi(db, servizio.turnoId);
}

Future<void> deleteServizio(String id, String turnoId) async {
  final db = await getDb();
  await db.delete('servizi', where: 'id = ?', whereArgs: [id]);
  await _aggiornaNumServizi(db, turnoId);
}

/// Aggiorna il contatore num_servizi nel turno padre.
Future<void> _aggiornaNumServizi(dynamic db, String turnoId) async {
  final count = Sqflite.firstIntValue(
    await db.rawQuery('SELECT COUNT(*) FROM servizi WHERE turno_id = ?', [turnoId]),
  );
  await db.update('turni', {'num_servizi': count ?? 0}, where: 'id = ?', whereArgs: [turnoId]);
}

/// Sposta un servizio di una posizione (su o giù) aggiornando i campi ordine.
Future<void> spostaServizio(String turnoId, int fromIndex, int toIndex) async {
  final db = await getDb();
  final servizi = await getServizi(turnoId);
  if (fromIndex < 0 || fromIndex >= servizi.length) return;
  if (toIndex < 0 || toIndex >= servizi.length) return;
  final batch = db.batch();
  // Scambia gli ordini dei due servizi.
  batch.update('servizi', {'ordine': toIndex}, where: 'id = ?', whereArgs: [servizi[fromIndex].id]);
  batch.update('servizi', {'ordine': fromIndex}, where: 'id = ?', whereArgs: [servizi[toIndex].id]);
  await batch.commit(noResult: true);
}

// ---------------------------------------------------------------------------
// ASSISTENZE
// ---------------------------------------------------------------------------

Future<List<Assistenza>> getAssistenze({String? associazioneId}) async {
  final db = await getDb();
  final where = associazioneId != null ? 'WHERE a.associazione_id = ?' : '';
  final args = associazioneId != null ? [associazioneId] : [];
  final rows = await db.rawQuery('''
    SELECT a.*,
           ass.nome AS associazione_nome
    FROM assistenze a
    LEFT JOIN associazioni ass ON ass.id = a.associazione_id
    $where
    ORDER BY a.data DESC, a.created_at DESC
  ''', args);
  return rows.map(Assistenza.fromMap).toList();
}

Future<Assistenza?> getAssistenzaById(String id) async {
  final db = await getDb();
  final rows = await db.rawQuery('''
    SELECT a.*,
           ass.nome AS associazione_nome
    FROM assistenze a
    LEFT JOIN associazioni ass ON ass.id = a.associazione_id
    WHERE a.id = ?
  ''', [id]);
  if (rows.isEmpty) return null;
  return Assistenza.fromMap(rows.first);
}

Future<void> saveAssistenza(Assistenza assistenza) async {
  final db = await getDb();
  final now = _now();
  final map = assistenza.toMap()..['updated_at'] = now..['is_synced'] = 0;
  await db.insert('assistenze', map, conflictAlgorithm: ConflictAlgorithm.replace);
  await _ricalcolaNumerazioneAssistenze(db, assistenza.associazioneId);
}

Future<void> deleteAssistenza(String id) async {
  final db = await getDb();
  final rows = await db.query('assistenze', columns: ['associazione_id'], where: 'id = ?', whereArgs: [id]);
  final assocId = rows.isNotEmpty ? rows.first['associazione_id'] as String? : null;
  await db.delete('assistenze', where: 'id = ?', whereArgs: [id]);
  await _ricalcolaNumerazioneAssistenze(db, assocId);
}

Future<void> _ricalcolaNumerazioneAssistenze(dynamic db, String? assocId) async {
  if (assocId == null) return;
  final rows = await db.query(
    'assistenze',
    columns: ['id'],
    where: 'associazione_id = ?',
    whereArgs: [assocId],
    orderBy: 'data ASC, created_at ASC',
  );
  for (int i = 0; i < rows.length; i++) {
    await db.update(
      'assistenze',
      {'numero_progressivo': i + 1},
      where: 'id = ?',
      whereArgs: [rows[i]['id']],
    );
  }
}

// ---------------------------------------------------------------------------
// STATISTICHE
// ---------------------------------------------------------------------------

class StatisticheData {
  final int totTurni;
  final int totServizi;
  final double oreTurni;
  final int totAssistenze;
  final double oreAssistenze;

  const StatisticheData({
    required this.totTurni,
    required this.totServizi,
    required this.oreTurni,
    required this.totAssistenze,
    required this.oreAssistenze,
  });

  double get oreTotali => oreTurni + oreAssistenze;
}

Future<StatisticheData> getStatistiche({String? associazioneId}) async {
  final db = await getDb();
  final whereT = associazioneId != null ? 'WHERE associazione_id = ?' : '';
  final args = associazioneId != null ? [associazioneId] : [];

  final turniRows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt, COALESCE(SUM(ore),0) AS ore FROM turni $whereT', args);
  final serviziRows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM servizi s LEFT JOIN turni t ON t.id = s.turno_id $whereT', args);
  final assRows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt, COALESCE(SUM(ore),0) AS ore FROM assistenze $whereT', args);

  return StatisticheData(
    totTurni: (turniRows.first['cnt'] as int?) ?? 0,
    oreTurni: (turniRows.first['ore'] as num?)?.toDouble() ?? 0,
    totServizi: (serviziRows.first['cnt'] as int?) ?? 0,
    totAssistenze: (assRows.first['cnt'] as int?) ?? 0,
    oreAssistenze: (assRows.first['ore'] as num?)?.toDouble() ?? 0,
  );
}
