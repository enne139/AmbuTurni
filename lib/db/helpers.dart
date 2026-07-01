// Tutte le funzioni CRUD dell'app. Ogni funzione che scrive invalida
// is_synced = 0 così il sync manager sa cosa deve spingere al server.
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'database.dart';
import 'models.dart';

// UUID v4 casuale — garantisce unicità senza coordinazione col server,
// compatibile con l'id TEXT PRIMARY KEY usato anche su PostgreSQL.
const _uuid = Uuid();
String newId() => _uuid.v4();

// ISO 8601 UTC: formato identico a quello usato dal backend Node per i
// campi updated_at, così i confronti di timestamp funzionano cross-platform.
String _now() => DateTime.now().toUtc().toIso8601String();

// ---------------------------------------------------------------------------
// ANAGRAFICHE
// ---------------------------------------------------------------------------

/// Restituisce tutte le associazioni ordinate per nome.
Future<List<Associazione>> getAssociazioni() async {
  final db = await getDb();
  final rows = await db.query('associazioni', orderBy: 'nome ASC');
  return rows.map(Associazione.fromMap).toList();
}

/// Inserisce o aggiorna un'associazione.
/// Se [id] è null viene creata una nuova riga con un UUID fresco;
/// altrimenti viene aggiornata la riga esistente (rename/recolor).
Future<void> saveAssociazione(String nome, {String? id, String? colore}) async {
  final db = await getDb();
  final now = _now();
  if (id == null) {
    await db.insert('associazioni', {
      'id': newId(),
      'nome': nome,
      'colore': colore,
      'created_at': now,
      'updated_at': now,
      'is_synced': 0,
    });
  } else {
    await db.update(
      'associazioni',
      {'nome': nome, 'colore': colore, 'updated_at': now, 'is_synced': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

Future<void> deleteAssociazione(String id) async {
  final db = await getDb();
  await db.delete('associazioni', where: 'id = ?', whereArgs: [id]);
}

/// Restituisce tutte le persone ordinate per cognome poi nome.
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
  // Ordine esplicito per permettere all'utente di personalizzare la sequenza.
  final rows =
      await db.query('tipologie_turno', orderBy: 'ordine ASC, nome ASC');
  return rows.map(TipologiaTurno.fromMap).toList();
}

/// Inserisce o rinomina una tipologia turno.
/// Le tipologie non si eliminano (spec originale): potrebbero essere
/// associate a turni esistenti e romperebbe la foreign key.
Future<void> saveTipologiaTurno(String nome, {String? id, String? colore}) async {
  final db = await getDb();
  final now = _now();
  if (id == null) {
    // Mette la nuova tipologia in fondo all'ordine corrente.
    final count = (await db
            .rawQuery('SELECT COUNT(*) AS n FROM tipologie_turno'))[0]['n']
        as int;
    await db.insert('tipologie_turno', {
      'id': newId(),
      'nome': nome,
      'ordine': count,
      'colore': colore,
      'created_at': now,
      'updated_at': now,
      'is_synced': 0,
    });
  } else {
    await db.update(
      'tipologie_turno',
      {'nome': nome, 'colore': colore, 'updated_at': now, 'is_synced': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

/// Scambia l'ordine di due tipologie adiacenti tramite batch atomico,
/// stesso pattern di spostaServizio.
Future<void> spostaTipologia(int fromIndex, int toIndex) async {
  final db = await getDb();
  final list = await getTipologieTurno();
  if (fromIndex < 0 || fromIndex >= list.length) return;
  if (toIndex < 0 || toIndex >= list.length) return;
  final batch = db.batch();
  batch.update('tipologie_turno', {'ordine': toIndex},
      where: 'id = ?', whereArgs: [list[fromIndex].id]);
  batch.update('tipologie_turno', {'ordine': fromIndex},
      where: 'id = ?', whereArgs: [list[toIndex].id]);
  await batch.commit(noResult: true);
}

// ---------------------------------------------------------------------------
// TURNI
// ---------------------------------------------------------------------------

/// Restituisce i turni ordinati per data decrescente.
/// LEFT JOIN su associazioni e tipologie_turno per denormalizzare i nomi
/// ed evitare N+1 query nelle liste (un'unica query basta per tutto).
///
/// Se [ricerca] è valorizzato, filtra sui turni la cui descrizione/note oppure
/// la descrizione di un servizio collegato contengono il testo (case-insensitive
/// per via del collate NOCASE di default di SQLite su colonne TEXT).
/// Il JOIN su servizi e il DISTINCT si attivano solo in questo caso: nelle query
/// senza ricerca (il caso comune) si evita di introdurre righe duplicate per i
/// turni con più servizi.
Future<List<Turno>> getTurni({String? associazioneId, String? ricerca}) async {
  final db = await getDb();
  final conditions = <String>[];
  final args = <dynamic>[];
  if (associazioneId != null) {
    conditions.add('t.associazione_id = ?');
    args.add(associazioneId);
  }
  final q = ricerca?.trim();
  final cercaTesto = q != null && q.isNotEmpty;
  if (cercaTesto) {
    conditions.add('(t.descrizione LIKE ? OR t.note LIKE ? OR s.descrizione LIKE ?)');
    args.addAll(['%$q%', '%$q%', '%$q%']);
  }
  final where = conditions.isEmpty ? '' : 'WHERE ${conditions.join(' AND ')}';
  final joinServizi = cercaTesto ? 'LEFT JOIN servizi s ON s.turno_id = t.id' : '';
  final distinct = cercaTesto ? 'DISTINCT ' : '';
  final rows = await db.rawQuery('''
    SELECT $distinct t.*,
           a.nome AS associazione_nome,
           a.colore AS associazione_colore,
           tp.nome AS tipologia_nome,
           tp.colore AS tipologia_colore
    FROM turni t
    LEFT JOIN associazioni a ON a.id = t.associazione_id
    LEFT JOIN tipologie_turno tp ON tp.id = t.tipologia_id
    $joinServizi
    $where
    ORDER BY t.data DESC, t.created_at DESC
  ''', args);
  return rows.map(Turno.fromMap).toList();
}

/// Restituisce i turni (ordinati per data decrescente) in cui [personaId]
/// compare in uno qualsiasi dei 10 ruoli di equipaggio (eq1/eq2 x 5 ruoli).
Future<List<Turno>> getTurniPerPersona(String personaId) async {
  final db = await getDb();
  final rows = await db.rawQuery('''
    SELECT t.*,
           a.nome AS associazione_nome,
           a.colore AS associazione_colore,
           tp.nome AS tipologia_nome,
           tp.colore AS tipologia_colore
    FROM turni t
    LEFT JOIN associazioni a ON a.id = t.associazione_id
    LEFT JOIN tipologie_turno tp ON tp.id = t.tipologia_id
    WHERE t.eq1_autista_id = ? OR t.eq1_cs_id = ? OR t.eq1_terzo_id = ? OR t.eq1_quarto_id = ? OR t.eq1_centralinista_id = ?
       OR t.eq2_autista_id = ? OR t.eq2_cs_id = ? OR t.eq2_terzo_id = ? OR t.eq2_quarto_id = ? OR t.eq2_centralinista_id = ?
    ORDER BY t.data DESC, t.created_at DESC
  ''', List.filled(10, personaId));
  return rows.map(Turno.fromMap).toList();
}

/// Restituisce i turni in cui [ospedaleId] compare in almeno un servizio.
/// DISTINCT necessario perché un turno può avere più servizi con lo stesso ospedale.
Future<List<Turno>> getTurniPerOspedale(String ospedaleId) async {
  final db = await getDb();
  final rows = await db.rawQuery('''
    SELECT DISTINCT t.*,
           a.nome AS associazione_nome,
           a.colore AS associazione_colore,
           tp.nome AS tipologia_nome,
           tp.colore AS tipologia_colore
    FROM turni t
    LEFT JOIN associazioni a ON a.id = t.associazione_id
    LEFT JOIN tipologie_turno tp ON tp.id = t.tipologia_id
    INNER JOIN servizi s ON s.turno_id = t.id
    WHERE s.ospedale_id = ?
    ORDER BY t.data DESC, t.created_at DESC
  ''', [ospedaleId]);
  return rows.map(Turno.fromMap).toList();
}

/// Restituisce un singolo turno con i campi denormalizzati, o null se non esiste.
Future<Turno?> getTurnoById(String id) async {
  final db = await getDb();
  final rows = await db.rawQuery('''
    SELECT t.*,
           a.nome AS associazione_nome,
           a.colore AS associazione_colore,
           tp.nome AS tipologia_nome,
           tp.colore AS tipologia_colore
    FROM turni t
    LEFT JOIN associazioni a ON a.id = t.associazione_id
    LEFT JOIN tipologie_turno tp ON tp.id = t.tipologia_id
    WHERE t.id = ?
  ''', [id]);
  if (rows.isEmpty) return null;
  return Turno.fromMap(rows.first);
}

/// Salva un turno e ricalcola la numerazione progressiva dell'associazione.
Future<void> saveTurno(Turno turno) async {
  final db = await getDb();
  final now = _now();
  final map = turno.toMap()
    ..['updated_at'] = now
    ..['is_synced'] = 0;
  // INSERT OR REPLACE cancella la riga e la reinserisce, innescando ON DELETE CASCADE
  // sui servizi figli. Si distingue invece tra INSERT (nuovo) e UPDATE (esistente)
  // per non perdere i servizi associati al turno in modifica.
  final exists = await db.query('turni',
      columns: ['id'], where: 'id = ?', whereArgs: [turno.id], limit: 1);
  if (exists.isEmpty) {
    await db.insert('turni', map);
  } else {
    // 'id' escluso: includerlo innesca ON DELETE CASCADE sui servizi figli.
    // 'num_servizi' escluso: è gestito esclusivamente da _aggiornaNumServizi;
    // includerlo azzererebbe il contatore ogni volta che si modifica il turno.
    final updateMap = Map<String, dynamic>.from(map)
      ..remove('id')
      ..remove('num_servizi');
    await db.update('turni', updateMap, where: 'id = ?', whereArgs: [turno.id]);
  }
  // La numerazione va ricalcolata dopo ogni salvataggio perché l'ordine
  // per data potrebbe essere cambiato (es. si modifica la data di un turno).
  await _ricalcolaNumerazioneTurni(db, turno.associazioneId);
}

/// Elimina un turno (i servizi figli vengono eliminati via ON DELETE CASCADE).
/// Legge associazione_id prima di cancellare perché dopo la DELETE non è più
/// disponibile, ma serve per ricalcolare la numerazione progressiva.
Future<void> deleteTurno(String id) async {
  final db = await getDb();
  final rows = await db.query('turni',
      columns: ['associazione_id'], where: 'id = ?', whereArgs: [id]);
  final assocId =
      rows.isNotEmpty ? rows.first['associazione_id'] as String? : null;
  await db.delete('turni', where: 'id = ?', whereArgs: [id]);
  await _ricalcolaNumerazioneTurni(db, assocId);
}

/// Ricalcola numero_progressivo per tutti i turni di un'associazione.
/// Il turno più vecchio (data ASC) riceve il numero 1; in caso di data
/// uguale si usa created_at come discriminante per stabilità.
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
    await db.update('turni', {'numero_progressivo': i + 1},
        where: 'id = ?', whereArgs: [rows[i]['id']]);
  }
}

// ---------------------------------------------------------------------------
// SERVIZI
// ---------------------------------------------------------------------------

/// Restituisce i servizi di un turno ordinati per campo `ordine`.
/// LEFT JOIN su ospedali per denormalizzare nome e città (mostrati in lista).
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

/// Salva un servizio e aggiorna il contatore num_servizi nel turno padre.
Future<void> saveServizio(Servizio servizio) async {
  final db = await getDb();
  final now = _now();
  final map = servizio.toMap()
    ..['updated_at'] = now
    ..['is_synced'] = 0;
  final exists = await db.query('servizi',
      columns: ['id'], where: 'id = ?', whereArgs: [servizio.id], limit: 1);
  if (exists.isEmpty) {
    await db.insert('servizi', map);
  } else {
    final updateMap = Map<String, dynamic>.from(map)..remove('id');
    await db.update('servizi', updateMap,
        where: 'id = ?', whereArgs: [servizio.id]);
  }
  await _aggiornaNumServizi(db, servizio.turnoId);
}

Future<void> deleteServizio(String id, String turnoId) async {
  final db = await getDb();
  await db.delete('servizi', where: 'id = ?', whereArgs: [id]);
  await _aggiornaNumServizi(db, turnoId);
}

/// Mantiene num_servizi nel turno denormalizzato per evitare una COUNT(*)
/// a ogni rendering della lista turni (che mostra "N serv." sul card).
Future<void> _aggiornaNumServizi(dynamic db, String turnoId) async {
  final count = Sqflite.firstIntValue(
    await db.rawQuery(
        'SELECT COUNT(*) FROM servizi WHERE turno_id = ?', [turnoId]),
  );
  await db.update('turni', {'num_servizi': count ?? 0},
      where: 'id = ?', whereArgs: [turnoId]);
}

/// Scambia i valori del campo `ordine` di due servizi adiacenti tramite
/// batch atomico — evita lo stato temporaneo in cui due righe hanno lo
/// stesso ordine, che causerebbe instabilità nell'ordinamento.
Future<void> spostaServizio(
    String turnoId, int fromIndex, int toIndex) async {
  final db = await getDb();
  final servizi = await getServizi(turnoId);
  if (fromIndex < 0 || fromIndex >= servizi.length) return;
  if (toIndex < 0 || toIndex >= servizi.length) return;
  final batch = db.batch();
  batch.update('servizi', {'ordine': toIndex},
      where: 'id = ?', whereArgs: [servizi[fromIndex].id]);
  batch.update('servizi', {'ordine': fromIndex},
      where: 'id = ?', whereArgs: [servizi[toIndex].id]);
  await batch.commit(noResult: true);
}

// ---------------------------------------------------------------------------
// ASSISTENZE
// ---------------------------------------------------------------------------

/// Come getTurni ma per le assistenze; LEFT JOIN solo su associazioni
/// perché le assistenze non hanno tipologia né servizi.
Future<List<Assistenza>> getAssistenze({String? associazioneId}) async {
  final db = await getDb();
  final where =
      associazioneId != null ? 'WHERE a.associazione_id = ?' : '';
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

/// Come getTurniPerPersona ma per le assistenze (stessi 10 ruoli equipaggio).
Future<List<Assistenza>> getAssistenzePerPersona(String personaId) async {
  final db = await getDb();
  final rows = await db.rawQuery('''
    SELECT a.*,
           ass.nome AS associazione_nome
    FROM assistenze a
    LEFT JOIN associazioni ass ON ass.id = a.associazione_id
    WHERE a.eq1_autista_id = ? OR a.eq1_cs_id = ? OR a.eq1_terzo_id = ? OR a.eq1_quarto_id = ? OR a.eq1_centralinista_id = ?
       OR a.eq2_autista_id = ? OR a.eq2_cs_id = ? OR a.eq2_terzo_id = ? OR a.eq2_quarto_id = ? OR a.eq2_centralinista_id = ?
    ORDER BY a.data DESC, a.created_at DESC
  ''', List.filled(10, personaId));
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
  final map = assistenza.toMap()
    ..['updated_at'] = now
    ..['is_synced'] = 0;
  final exists = await db.query('assistenze',
      columns: ['id'], where: 'id = ?', whereArgs: [assistenza.id], limit: 1);
  if (exists.isEmpty) {
    await db.insert('assistenze', map);
  } else {
    final updateMap = Map<String, dynamic>.from(map)..remove('id');
    await db.update('assistenze', updateMap,
        where: 'id = ?', whereArgs: [assistenza.id]);
  }
  await _ricalcolaNumerazioneAssistenze(db, assistenza.associazioneId);
}

Future<void> deleteAssistenza(String id) async {
  final db = await getDb();
  final rows = await db.query('assistenze',
      columns: ['associazione_id'], where: 'id = ?', whereArgs: [id]);
  final assocId =
      rows.isNotEmpty ? rows.first['associazione_id'] as String? : null;
  await db.delete('assistenze', where: 'id = ?', whereArgs: [id]);
  await _ricalcolaNumerazioneAssistenze(db, assocId);
}

/// Stessa logica di _ricalcolaNumerazioneTurni ma per le assistenze.
Future<void> _ricalcolaNumerazioneAssistenze(
    dynamic db, String? assocId) async {
  if (assocId == null) return;
  final rows = await db.query(
    'assistenze',
    columns: ['id'],
    where: 'associazione_id = ?',
    whereArgs: [assocId],
    orderBy: 'data ASC, created_at ASC',
  );
  for (int i = 0; i < rows.length; i++) {
    await db.update('assistenze', {'numero_progressivo': i + 1},
        where: 'id = ?', whereArgs: [rows[i]['id']]);
  }
}

/// Ricalcola la numerazione progressiva di turni e assistenze per tutte le
/// associazioni. Chiamato dopo l'import del backup, dove i dati vengono
/// inseriti con raw INSERT senza passare per saveTurno/saveAssistenza.
Future<void> ricalcolaTutteLeNumerazioni() async {
  final db = await getDb();
  final assoc = await db.query('associazioni', columns: ['id']);
  for (final row in assoc) {
    final id = row['id'] as String;
    await _ricalcolaNumerazioneTurni(db, id);
    await _ricalcolaNumerazioneAssistenze(db, id);
  }
}

// ---------------------------------------------------------------------------
// STATISTICHE
// ---------------------------------------------------------------------------

/// Contenitore dei dati aggregati mostrati nella schermata Statistiche.
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

/// Esegue tre query aggregate in parallelo (turni, servizi, assistenze).
/// COALESCE(SUM(ore), 0) gestisce il caso in cui nessuna riga ha ore valorizzate:
/// senza COALESCE SQLite restituirebbe NULL, che in Dart diventerebbe un crash.
Future<StatisticheData> getStatistiche({String? associazioneId}) async {
  final db = await getDb();
  final whereT =
      associazioneId != null ? 'WHERE associazione_id = ?' : '';
  final args = associazioneId != null ? [associazioneId] : [];

  final turniRows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt, COALESCE(SUM(ore),0) AS ore FROM turni $whereT',
      args);
  final serviziRows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt FROM servizi s '
      'LEFT JOIN turni t ON t.id = s.turno_id $whereT',
      args);
  final assRows = await db.rawQuery(
      'SELECT COUNT(*) AS cnt, COALESCE(SUM(ore),0) AS ore FROM assistenze $whereT',
      args);

  return StatisticheData(
    totTurni: (turniRows.first['cnt'] as int?) ?? 0,
    oreTurni: (turniRows.first['ore'] as num?)?.toDouble() ?? 0,
    totServizi: (serviziRows.first['cnt'] as int?) ?? 0,
    totAssistenze: (assRows.first['cnt'] as int?) ?? 0,
    oreAssistenze: (assRows.first['ore'] as num?)?.toDouble() ?? 0,
  );
}
