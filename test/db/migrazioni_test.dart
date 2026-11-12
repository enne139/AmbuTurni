// Test delle migrazioni del database: si crea un DB su file con lo schema di
// una versione vecchia, lo si chiude e lo si riapre con openTestDbAt, che usa
// il vero _onUpgrade. Su file e non in memoria perché un DB in memoria sparisce
// quando lo si chiude, e la migrazione scatta solo riaprendolo.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ambu_turni/db/database.dart';

/// Le tabelle di turni, assistenze e servizi come erano nella DB v13, con la
/// colonna `descrizione` (ridotte alle colonne che la migrazione v14 tocca o
/// deve conservare).
const _schemaV13 = [
  '''CREATE TABLE turni (
    id TEXT PRIMARY KEY,
    associazione_id TEXT,
    numero_progressivo INTEGER,
    data TEXT NOT NULL,
    ore REAL,
    tipologie TEXT DEFAULT '[]',
    num_servizi INTEGER DEFAULT 0,
    descrizione TEXT,
    note TEXT,
    eq1_autista_id TEXT,
    cambio_meta INTEGER DEFAULT 0,
    created_at TEXT,
    updated_at TEXT,
    is_synced INTEGER DEFAULT 0
  )''',
  '''CREATE TABLE servizi (
    id TEXT PRIMARY KEY,
    turno_id TEXT NOT NULL REFERENCES turni(id) ON DELETE CASCADE,
    codice_chiamata TEXT,
    codice_uscita TEXT,
    ospedale_id TEXT,
    descrizione TEXT,
    ordine INTEGER DEFAULT 0,
    created_at TEXT,
    updated_at TEXT,
    is_synced INTEGER DEFAULT 0
  )''',
  '''CREATE TABLE assistenze (
    id TEXT PRIMARY KEY,
    associazione_id TEXT,
    numero_progressivo INTEGER,
    data TEXT NOT NULL,
    ore REAL,
    descrizione TEXT,
    note TEXT,
    eq1_autista_id TEXT,
    created_at TEXT,
    updated_at TEXT,
    is_synced INTEGER DEFAULT 0
  )''',
];

Future<List<String>> _colonne(Database db, String tabella) async =>
    (await db.rawQuery('PRAGMA table_info($tabella)'))
        .map((c) => c['name'] as String)
        .toList();

void main() {
  late Directory cartella;
  late String percorso;

  setUp(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    cartella = await Directory.systemTemp.createTemp('ambuturni_migrazioni_');
    percorso = p.join(cartella.path, 'test.db');
  });

  tearDown(() async {
    await cartella.delete(recursive: true);
  });

  test('v13 → ultima: orario (v14), campi dei servizi (v15), sesso ed età uniti (v16)', () async {
    final vecchio = await openDatabase(percorso, version: 13, onCreate: (db, _) async {
      for (final sql in _schemaV13) {
        await db.execute(sql);
      }
    });
    await vecchio.insert('turni', {
      'id': 't1',
      'data': '2026-11-01',
      'ore': 6.0,
      'tipologie': '["tip1"]',
      'num_servizi': 1,
      'descrizione': '12:00 - 18:00',
      'note': 'nota del turno',
      'eq1_autista_id': 'p1',
    });
    await vecchio.insert('servizi', {
      'id': 's1',
      'turno_id': 't1',
      'codice_chiamata': 'GIALLO',
      'descrizione': 'descrizione del servizio',
    });
    await vecchio.insert('assistenze', {
      'id': 'a1',
      'data': '2026-11-02',
      'descrizione': '14:00 - 19:00',
      'note': 'stadio',
    });
    await vecchio.close();

    final db = await openTestDbAt(percorso);
    try {
      // Colonne: orario al posto di descrizione, servizi invariati.
      expect(await _colonne(db, 'turni'), allOf(contains('orario'), isNot(contains('descrizione'))));
      expect(await _colonne(db, 'assistenze'), allOf(contains('orario'), isNot(contains('descrizione'))));
      expect(await _colonne(db, 'servizi'), contains('descrizione'));

      // Valori spostati, il resto della riga intatto.
      final turno = (await db.query('turni')).single;
      expect(turno['orario'], '12:00 - 18:00');
      expect(turno['note'], 'nota del turno');
      expect(turno['tipologie'], '["tip1"]');
      expect(turno['eq1_autista_id'], 'p1');
      final assistenza = (await db.query('assistenze')).single;
      expect(assistenza['orario'], '14:00 - 19:00');
      expect(assistenza['note'], 'stadio');

      // Il servizio resta collegato al turno ricostruito.
      final servizio = (await db.query('servizi')).single;
      expect(servizio['turno_id'], 't1');
      expect(servizio['descrizione'], 'descrizione del servizio');

      // v15 e v16: campi personalizzati iniziali (sesso ed età già uniti nel
      // campo speciale) e servizi esistenti senza valori.
      expect(await _colonne(db, 'servizi'), contains('campi'));
      expect(servizio['campi'], '{}');
      final campi = await db.query('campi_servizio', orderBy: 'ordine');
      expect(campi.map((c) => c['nome']), ['Sesso ed età', 'Colore invio']);
      expect(campi.first['tipo'], 'SESSO_ETA');

      // Gli indici eliminati col DROP sono stati ricreati.
      final indici = (await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'index'"))
          .map((r) => r['name'])
          .toSet();
      expect(indici, containsAll(['idx_turni_assoc', 'idx_assistenze_assoc']));
    } finally {
      await db.close();
    }
  });

  test('un DB nuovo ha già orario, la colonna campi e i campi iniziali', () async {
    final db = await openTestDbAt(percorso);
    try {
      expect(await _colonne(db, 'turni'), allOf(contains('orario'), isNot(contains('descrizione'))));
      expect(await _colonne(db, 'assistenze'), allOf(contains('orario'), isNot(contains('descrizione'))));
      expect(await _colonne(db, 'servizi'), contains('campi'));
      final campi = await db.query('campi_servizio', orderBy: 'ordine');
      expect(campi.map((c) => c['id']), ['sesso_eta', 'colore_invio']);
    } finally {
      await db.close();
    }
  });

  test('v15 → v16: Sesso ed Età separati diventano il campo speciale, valori compresi', () async {
    final vecchio = await openDatabase(percorso, version: 15, onCreate: (db, _) async {
      // Solo le tabelle che la v16 tocca, come le creava la v15.
      await db.execute('''CREATE TABLE servizi (
        id TEXT PRIMARY KEY, turno_id TEXT NOT NULL, descrizione TEXT,
        ordine INTEGER DEFAULT 0, campi TEXT DEFAULT '{}'
      )''');
      await db.execute('''CREATE TABLE campi_servizio (
        id TEXT PRIMARY KEY,
        nome TEXT NOT NULL,
        tipo TEXT NOT NULL CHECK (tipo IN ('TENDINA','COLORI','TESTO','NUMERO')),
        opzioni TEXT DEFAULT '[]',
        visibile INTEGER NOT NULL DEFAULT 1,
        ordine INTEGER DEFAULT 0,
        created_at TEXT,
        updated_at TEXT
      )''');
    });
    // Come dopo la v15, con l'Età spostata in fondo e un campo dell'utente.
    await vecchio.insert('campi_servizio', {'id': 'sesso', 'nome': 'Sesso', 'tipo': 'TENDINA', 'ordine': 0, 'visibile': 1,
        'opzioni': '[{"id":"m","nome":"M"},{"id":"f","nome":"F"},{"id":"a","nome":"A"}]'});
    await vecchio.insert('campi_servizio', {'id': 'colore_invio', 'nome': 'Colore invio', 'tipo': 'COLORI', 'ordine': 1,
        'opzioni': '[{"id":"verde","nome":"Verde","colore":"#43A047"}]'});
    await vecchio.insert('campi_servizio', {'id': 'mio', 'nome': 'Note', 'tipo': 'TESTO', 'ordine': 2});
    await vecchio.insert('campi_servizio', {'id': 'eta', 'nome': 'Età', 'tipo': 'NUMERO', 'ordine': 3, 'visibile': 0});
    await vecchio.insert('servizi', {'id': 's1', 'turno_id': 't1', 'campi': '{"sesso":"f","eta":45,"colore_invio":"verde","mio":"ok"}'});
    await vecchio.insert('servizi', {'id': 's2', 'turno_id': 't1', 'campi': '{"eta":7}'});
    await vecchio.insert('servizi', {'id': 's3', 'turno_id': 't1', 'campi': '{"mio":"solo questo"}'});
    await vecchio.close();

    final db = await openTestDbAt(percorso);
    try {
      final campi = await db.query('campi_servizio', orderBy: 'ordine');
      expect(campi.map((c) => c['id']), ['sesso_eta', 'colore_invio', 'mio']);
      final speciale = campi.first;
      expect(speciale['tipo'], 'SESSO_ETA');
      expect(speciale['opzioni'], contains('"F"'));
      expect(speciale['visibile'], 1); // il Sesso era visibile

      Future<Map<String, dynamic>> campiDi(String id) async =>
          jsonDecode((await db.query('servizi', where: 'id = ?', whereArgs: [id])).single['campi'] as String)
              as Map<String, dynamic>;
      expect(await campiDi('s1'), {'colore_invio': 'verde', 'mio': 'ok', 'sesso_eta': {'sesso': 'f', 'eta': 45}});
      expect(await campiDi('s2'), {'sesso_eta': {'eta': 7}});
      expect(await campiDi('s3'), {'mio': 'solo questo'});

      // Il CHECK nuovo accetta il tipo speciale e rifiuta i tipi sconosciuti.
      await db.insert('campi_servizio', {'id': 'x', 'nome': 'X', 'tipo': 'SESSO_ETA'});
      expect(() => db.insert('campi_servizio', {'id': 'y', 'nome': 'Y', 'tipo': 'BOH'}), throwsA(anything));
    } finally {
      await db.close();
    }
  });
}
