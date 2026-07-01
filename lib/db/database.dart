import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Schema SQL locale — identico a quello del branch React Native (schema.ts).
const _schema = '''
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS associazioni (
  id TEXT PRIMARY KEY,
  nome TEXT NOT NULL UNIQUE,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  is_synced INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS persone (
  id TEXT PRIMARY KEY,
  nome TEXT NOT NULL,
  cognome TEXT NOT NULL,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  is_synced INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS ospedali (
  id TEXT PRIMARY KEY,
  nome TEXT NOT NULL UNIQUE,
  citta TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  is_synced INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS tipologie_turno (
  id TEXT PRIMARY KEY,
  nome TEXT NOT NULL UNIQUE,
  ordine INTEGER DEFAULT 0,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  is_synced INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS tipologie_assistenza (
  id TEXT PRIMARY KEY,
  nome TEXT NOT NULL UNIQUE,
  ordine INTEGER DEFAULT 0,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  is_synced INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS turni (
  id TEXT PRIMARY KEY,
  associazione_id TEXT REFERENCES associazioni(id),
  numero_progressivo INTEGER,
  data TEXT NOT NULL,
  ore REAL,
  tipologia_id TEXT REFERENCES tipologie_turno(id),
  tipologie_extra TEXT DEFAULT '[]',
  num_servizi INTEGER DEFAULT 0,
  descrizione TEXT,
  note TEXT,
  eq1_autista_id TEXT REFERENCES persone(id),
  eq1_cs_id TEXT REFERENCES persone(id),
  eq1_terzo_id TEXT REFERENCES persone(id),
  eq1_quarto_id TEXT REFERENCES persone(id),
  eq1_centralinista_id TEXT REFERENCES persone(id),
  eq2_autista_id TEXT REFERENCES persone(id),
  eq2_cs_id TEXT REFERENCES persone(id),
  eq2_terzo_id TEXT REFERENCES persone(id),
  eq2_quarto_id TEXT REFERENCES persone(id),
  eq2_centralinista_id TEXT REFERENCES persone(id),
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  is_synced INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS servizi (
  id TEXT PRIMARY KEY,
  turno_id TEXT NOT NULL REFERENCES turni(id) ON DELETE CASCADE,
  codice_chiamata TEXT CHECK (codice_chiamata IN ('VERDE','GIALLO','ROSSO','DIMISSIONE')),
  codice_uscita   TEXT CHECK (codice_uscita IN ('VERDE','GIALLO','ROSSO','NERO','VUOTO','RIFIUTO')),
  ospedale_id TEXT REFERENCES ospedali(id),
  descrizione TEXT,
  ordine INTEGER DEFAULT 0,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  is_synced INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS assistenze (
  id TEXT PRIMARY KEY,
  associazione_id TEXT REFERENCES associazioni(id),
  numero_progressivo INTEGER,
  data TEXT NOT NULL,
  ore REAL,
  descrizione TEXT,
  note TEXT,
  eq1_autista_id TEXT REFERENCES persone(id),
  eq1_cs_id TEXT REFERENCES persone(id),
  eq1_terzo_id TEXT REFERENCES persone(id),
  eq1_quarto_id TEXT REFERENCES persone(id),
  eq1_centralinista_id TEXT REFERENCES persone(id),
  eq2_autista_id TEXT REFERENCES persone(id),
  eq2_cs_id TEXT REFERENCES persone(id),
  eq2_terzo_id TEXT REFERENCES persone(id),
  eq2_quarto_id TEXT REFERENCES persone(id),
  eq2_centralinista_id TEXT REFERENCES persone(id),
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  is_synced INTEGER DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_servizi_turno ON servizi(turno_id);
CREATE INDEX IF NOT EXISTS idx_turni_assoc ON turni(associazione_id);
CREATE INDEX IF NOT EXISTS idx_assistenze_assoc ON assistenze(associazione_id);

CREATE TABLE IF NOT EXISTS sync_meta (
  key TEXT PRIMARY KEY,
  value TEXT
);

CREATE TABLE IF NOT EXISTS deletions (
  table_name TEXT NOT NULL,
  id TEXT NOT NULL,
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  is_synced INTEGER DEFAULT 0,
  PRIMARY KEY (table_name, id)
);
''';

// Singleton del database: aperto una sola volta e riutilizzato.
Database? _db;

/// Restituisce l'istanza aperta del DB, inizializzandola se necessario.
/// Su desktop (Windows/Linux/macOS) usa sqflite_common_ffi perché sqflite
/// nativo non è disponibile fuori da Android/iOS.
Future<Database> getDb() async {
  if (_db != null) return _db!;
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  final dbPath = join(await getDatabasesPath(), 'ambulanza_turni.db');
  _db = await openDatabase(
    dbPath,
    version: 1,
    onCreate: _onCreate,
    onOpen: _onOpen,
  );
  return _db!;
}

/// Creazione iniziale: esegue lo schema completo.
Future<void> _onCreate(Database db, int version) async {
  // execRawBatch non esiste: iteriamo sugli statement separati da ';'.
  for (final stmt in _schema.split(';')) {
    final s = stmt.trim();
    if (s.isNotEmpty) {
      await db.execute(s);
    }
  }
}

/// Apre il DB esistente: abilita FK e applica le migrazioni idempotenti.
Future<void> _onOpen(Database db) async {
  await db.execute('PRAGMA foreign_keys = ON');
  await _runMigrations(db);
}

/// Migrazioni idempotenti: aggiungono colonne/tabelle mancanti su un DB
/// esistente senza distruggere i dati (stessa logica di migrations.ts).
Future<void> _runMigrations(Database db) async {
  // Assicura che le tabelle esistano (per DB creati prima di questa versione).
  for (final stmt in _schema.split(';')) {
    final s = stmt.trim();
    if (s.isNotEmpty) {
      try {
        await db.execute(s);
      } catch (_) {
        // Ignora errori "already exists" — le CREATE IF NOT EXISTS sono sicure.
      }
    }
  }

  // Migrazione: aggiunge la colonna ordine a tipologie_turno.
  // ALTER TABLE fallisce se la colonna esiste già — è il segnale che la migrazione
  // è già stata applicata, quindi il catch è intenzionale.
  try {
    await db.execute(
        'ALTER TABLE tipologie_turno ADD COLUMN ordine INTEGER DEFAULT 0');
    final rows = await db.query('tipologie_turno', orderBy: 'nome ASC');
    final batch = db.batch();
    for (int i = 0; i < rows.length; i++) {
      batch.update('tipologie_turno', {'ordine': i},
          where: 'id = ?', whereArgs: [rows[i]['id']]);
    }
    await batch.commit(noResult: true);
  } catch (_) {}

  // Migrazione: aggiunge la colonna ordine a tipologie_assistenza.
  try {
    await db.execute(
        'ALTER TABLE tipologie_assistenza ADD COLUMN ordine INTEGER DEFAULT 0');
    final rows = await db.query('tipologie_assistenza', orderBy: 'nome ASC');
    final batch = db.batch();
    for (int i = 0; i < rows.length; i++) {
      batch.update('tipologie_assistenza', {'ordine': i},
          where: 'id = ?', whereArgs: [rows[i]['id']]);
    }
    await batch.commit(noResult: true);
  } catch (_) {}
}
