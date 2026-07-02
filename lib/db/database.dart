import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Schema SQL locale — identico a quello del branch React Native (schema.ts).
const _schema = '''
CREATE TABLE IF NOT EXISTS associazioni (
  id TEXT PRIMARY KEY,
  nome TEXT NOT NULL UNIQUE,
  colore TEXT,
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
  colore TEXT,
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
  cambio_meta INTEGER DEFAULT 0,
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

CREATE TABLE IF NOT EXISTS materiali (
  id TEXT PRIMARY KEY,
  nome TEXT NOT NULL UNIQUE,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  is_synced INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS materiali_usati (
  id TEXT PRIMARY KEY,
  materiale_id TEXT NOT NULL REFERENCES materiali(id) ON DELETE CASCADE,
  quantita INTEGER NOT NULL DEFAULT 1,
  unita TEXT,
  posizione TEXT CHECK (posizione IN ('AMBULANZA','BOMBOLINO','ZAINO')),
  note TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  is_synced INTEGER DEFAULT 0
);

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

/// Solo per i test: inietta un DB (tipicamente in-memory) nel singleton.
/// Non usare in produzione — il singleton non viene resettato all'uscita del test.
void setDbForTesting(Database db) => _db = db;

/// Solo per i test: apre un DB in-memory con lo schema e le migrazioni complete.
Future<Database> openTestDb() async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  return openDatabase(
    inMemoryDatabasePath,
    version: 1,
    onCreate: _onCreate,
    onOpen: _onOpen,
  );
}

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
    version: 6,
    onCreate: _onCreate,
    onUpgrade: _onUpgrade,
    onOpen: _onOpen,
  );
  return _db!;
}

/// Upgrade del DB: aggiunge le colonne/tabelle per ogni nuova versione.
/// ALTER TABLE fallisce silenziosamente se la colonna esiste già (catch intenzionale).
Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
  if (oldVersion < 2) {
    try { await db.execute('ALTER TABLE tipologie_turno ADD COLUMN ordine INTEGER DEFAULT 0'); } catch (_) {}
    try { await db.execute('ALTER TABLE turni ADD COLUMN cambio_meta INTEGER DEFAULT 0'); } catch (_) {}
    try { await db.execute('ALTER TABLE tipologie_assistenza ADD COLUMN ordine INTEGER DEFAULT 0'); } catch (_) {}
  }
  if (oldVersion < 3) {
    try { await db.execute('ALTER TABLE associazioni ADD COLUMN colore TEXT'); } catch (_) {}
    try { await db.execute('ALTER TABLE tipologie_turno ADD COLUMN colore TEXT'); } catch (_) {}
  }
  if (oldVersion < 4) {
    // Tabelle nuove (Tools -> Materiali usati): CREATE TABLE IF NOT EXISTS è
    // già idempotente di suo, il try/catch è solo per uniformità con le altre
    // entry di questo metodo.
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS materiali (
          id TEXT PRIMARY KEY,
          nome TEXT NOT NULL UNIQUE,
          created_at TEXT DEFAULT (datetime('now')),
          updated_at TEXT DEFAULT (datetime('now')),
          is_synced INTEGER DEFAULT 0
        )
      ''');
    } catch (_) {}
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS materiali_usati (
          id TEXT PRIMARY KEY,
          materiale_id TEXT NOT NULL REFERENCES materiali(id),
          quantita INTEGER NOT NULL DEFAULT 1,
          unita TEXT,
          posizione TEXT CHECK (posizione IN ('AMBULANZA','BOMBOLINO','ZAINO')),
          note TEXT,
          ripristinato INTEGER DEFAULT 0,
          created_at TEXT DEFAULT (datetime('now')),
          updated_at TEXT DEFAULT (datetime('now')),
          is_synced INTEGER DEFAULT 0
        )
      ''');
    } catch (_) {}
    try { await db.execute('CREATE INDEX IF NOT EXISTS idx_materiali_usati_ripristinato ON materiali_usati(ripristinato)'); } catch (_) {}
  }
  if (oldVersion < 5) {
    // Chi ha già aperto l'app durante lo sviluppo del branch feature/tools ha
    // una materiali_usati creata dalla v4 col vecchio schema (quantita TEXT
    // libero + colonna data, poi sostituiti da quantita INTEGER/unita/posizione
    // senza bump di versione): qui la tabella va ricostruita SOLO se è ancora
    // nella forma vecchia (rilevata dalla presenza della colonna "data"),
    // preservando i dati con un parsing best-effort invece di un DROP secco.
    final cols = await db.rawQuery("PRAGMA table_info(materiali_usati)");
    final haSchemaVecchio = cols.any((c) => c['name'] == 'data');
    if (haSchemaVecchio) {
      final righeVecchie = await db.query('materiali_usati');
      await db.execute('DROP TABLE materiali_usati');
      await db.execute('''
        CREATE TABLE materiali_usati (
          id TEXT PRIMARY KEY,
          materiale_id TEXT NOT NULL REFERENCES materiali(id),
          quantita INTEGER NOT NULL DEFAULT 1,
          unita TEXT,
          posizione TEXT CHECK (posizione IN ('AMBULANZA','BOMBOLINO','ZAINO')),
          note TEXT,
          ripristinato INTEGER DEFAULT 0,
          created_at TEXT DEFAULT (datetime('now')),
          updated_at TEXT DEFAULT (datetime('now')),
          is_synced INTEGER DEFAULT 0
        )
      ''');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_materiali_usati_ripristinato ON materiali_usati(ripristinato)');
      // "2 confezioni" -> quantita 2, unita "confezioni"; "500ml" -> 500, "ml";
      // "3" -> 3, null; "scatola" (senza numero) -> 1, "scatola".
      final numeroIniziale = RegExp(r'^(\d+)\s*(.*)$');
      for (final riga in righeVecchie) {
        final quantitaGrezza = (riga['quantita']?.toString() ?? '1').trim();
        final match = numeroIniziale.firstMatch(quantitaGrezza);
        final quantita = match != null ? int.parse(match.group(1)!) : 1;
        final resto = match != null ? match.group(2)!.trim() : quantitaGrezza;
        await db.insert('materiali_usati', {
          'id': riga['id'],
          'materiale_id': riga['materiale_id'],
          'quantita': quantita,
          'unita': resto.isEmpty ? null : resto,
          'posizione': null,
          'note': riga['note'],
          'ripristinato': riga['ripristinato'] ?? 0,
          'created_at': riga['created_at'],
          'updated_at': riga['updated_at'],
          'is_synced': 0,
        });
      }
    }
  }
  if (oldVersion < 6) {
    // Su richiesta esplicita: niente più storico dei materiali ripristinati
    // (prima restavano in tabella con ripristinato = 1) e la foreign key su
    // materiali_usati diventa ON DELETE CASCADE, per poter eliminare un
    // materiale dal catalogo anche se ha ancora utilizzi collegati (prima
    // SQLite lo impediva). Entrambe richiedono di ricreare la tabella: SQLite
    // non supporta ALTER per rimuovere una colonna vincolata da un CHECK
    // impliclito né per cambiare i vincoli di una foreign key esistente.
    // Le righe già ripristinate (ripristinato = 1) vengono scartate qui,
    // proprio per non portarsi dietro lo storico che non si vuole più tenere;
    // solo quelle ancora attive vengono preservate nella tabella ricostruita.
    final cols = await db.rawQuery("PRAGMA table_info(materiali_usati)");
    final haColonnaRipristinato = cols.any((c) => c['name'] == 'ripristinato');
    if (haColonnaRipristinato) {
      final righeAttive =
          await db.query('materiali_usati', where: 'ripristinato = 0');
      await db.execute('DROP TABLE materiali_usati');
      await db.execute('''
        CREATE TABLE materiali_usati (
          id TEXT PRIMARY KEY,
          materiale_id TEXT NOT NULL REFERENCES materiali(id) ON DELETE CASCADE,
          quantita INTEGER NOT NULL DEFAULT 1,
          unita TEXT,
          posizione TEXT CHECK (posizione IN ('AMBULANZA','BOMBOLINO','ZAINO')),
          note TEXT,
          created_at TEXT DEFAULT (datetime('now')),
          updated_at TEXT DEFAULT (datetime('now')),
          is_synced INTEGER DEFAULT 0
        )
      ''');
      for (final riga in righeAttive) {
        final nuovaRiga = Map<String, dynamic>.from(riga)..remove('ripristinato');
        await db.insert('materiali_usati', nuovaRiga);
      }
    }
  }
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

/// Apre il DB esistente: abilita FK/WAL e applica le migrazioni idempotenti.
/// Il PRAGMA journal_mode va eseguito qui (fuori dalla transazione di
/// _onCreate, dove SQLite rifiuta il passaggio a WAL) e con rawQuery invece
/// di execute: su Android nativo restituisce una riga col nuovo modo, ed
/// execute/execSQL rifiuta le query che restituiscono risultati.
Future<void> _onOpen(Database db) async {
  await db.rawQuery('PRAGMA journal_mode = WAL');
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

  // Migrazione: aggiunge cambio_meta ai turni.
  try {
    await db
        .execute('ALTER TABLE turni ADD COLUMN cambio_meta INTEGER DEFAULT 0');
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
