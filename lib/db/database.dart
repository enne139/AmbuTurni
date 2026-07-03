import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// Schema SQL locale. Nato identico a quello dell'app React Native (schema.ts),
// ora dismessa: dalla v8 lo schema è libero di evolvere (vedi `tipologie`).
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
  tipologie TEXT DEFAULT '[]',
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
  quantita INTEGER NOT NULL DEFAULT 1 CHECK (quantita >= 1),
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
    version: 8,
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
    // Il backfill di `ordine` (indice alfabetico) gira solo se l'ALTER riesce:
    // se la colonna esiste già la migrazione era stata applicata (in passato
    // anche dal vecchio _runMigrations a ogni apertura) e non va rifatta.
    try {
      await db.execute('ALTER TABLE tipologie_turno ADD COLUMN ordine INTEGER DEFAULT 0');
      await _backfillOrdine(db, 'tipologie_turno');
    } catch (_) {}
    try { await db.execute('ALTER TABLE turni ADD COLUMN cambio_meta INTEGER DEFAULT 0'); } catch (_) {}
    try {
      await db.execute('ALTER TABLE tipologie_assistenza ADD COLUMN ordine INTEGER DEFAULT 0');
      await _backfillOrdine(db, 'tipologie_assistenza');
    } catch (_) {}
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
  if (oldVersion < 7) {
    // Aggiunge CHECK (quantita >= 1): prima il vincolo viveva solo nella UI
    // (pulsanti +/- clampati) e una scrittura difettosa poteva salvare 0 o
    // negativi. SQLite non supporta ALTER per aggiungere un CHECK: la tabella
    // va ricostruita, clampando a 1 gli eventuali valori già fuori range.
    final righe = await db.query('materiali_usati');
    await db.execute('DROP TABLE materiali_usati');
    await db.execute('''
      CREATE TABLE materiali_usati (
        id TEXT PRIMARY KEY,
        materiale_id TEXT NOT NULL REFERENCES materiali(id) ON DELETE CASCADE,
        quantita INTEGER NOT NULL DEFAULT 1 CHECK (quantita >= 1),
        unita TEXT,
        posizione TEXT CHECK (posizione IN ('AMBULANZA','BOMBOLINO','ZAINO')),
        note TEXT,
        created_at TEXT DEFAULT (datetime('now')),
        updated_at TEXT DEFAULT (datetime('now')),
        is_synced INTEGER DEFAULT 0
      )
    ''');
    for (final riga in righe) {
      final nuovaRiga = Map<String, dynamic>.from(riga);
      final quantita = (nuovaRiga['quantita'] as num?)?.toInt() ?? 1;
      nuovaRiga['quantita'] = quantita < 1 ? 1 : quantita;
      await db.insert('materiali_usati', nuovaRiga);
    }
  }
  if (oldVersion < 8) {
    // L'app React Native è stata dismessa: la distinzione tipologia_id
    // (primaria) / tipologie_extra (JSON) esisteva solo per compatibilità col
    // suo schema. Le due colonne vengono fuse in un'unica colonna `tipologie`
    // (array JSON di id, primaria in testa). SQLite non può rimuovere una
    // colonna con REFERENCES né fonderne due con ALTER: la tabella va
    // ricostruita. Le FK sono disattivate durante onUpgrade (il PRAGMA viene
    // acceso solo in _onOpen, che gira dopo), quindi il DROP non tocca i
    // servizi figli, che restano validi perché gli id dei turni non cambiano.
    final cols = await db.rawQuery('PRAGMA table_info(turni)');
    final haSchemaVecchio = cols.any((c) => c['name'] == 'tipologia_id');
    if (haSchemaVecchio) {
      final righe = await db.query('turni');
      await db.execute('DROP TABLE turni');
      await db.execute('''
        CREATE TABLE turni (
          id TEXT PRIMARY KEY,
          associazione_id TEXT REFERENCES associazioni(id),
          numero_progressivo INTEGER,
          data TEXT NOT NULL,
          ore REAL,
          tipologie TEXT DEFAULT '[]',
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
        )
      ''');
      // L'indice viene eliminato insieme alla tabella: va ricreato.
      await db.execute('CREATE INDEX IF NOT EXISTS idx_turni_assoc ON turni(associazione_id)');
      for (final riga in righe) {
        final nuovaRiga = Map<String, dynamic>.from(riga);
        nuovaRiga['tipologie'] =
            jsonEncode(_fondiTipologie(riga['tipologia_id'], riga['tipologie_extra']));
        nuovaRiga
          ..remove('tipologia_id')
          ..remove('tipologie_extra');
        await db.insert('turni', nuovaRiga);
      }
    }
  }
}

/// Fonde tipologia primaria ed extra nella lista unica della v8:
/// la primaria (se presente) resta in testa, seguono le extra nell'ordine
/// salvato. Il catch copre valori corrotti/legacy senza far fallire la
/// migrazione (stesso approccio del vecchio Turno.fromMap).
List<String> _fondiTipologie(dynamic tipologiaId, dynamic tipologieExtra) {
  final tipologie = <String>[
    if (tipologiaId is String && tipologiaId.isNotEmpty) tipologiaId,
  ];
  if (tipologieExtra is String && tipologieExtra.isNotEmpty) {
    try {
      final decoded = jsonDecode(tipologieExtra);
      if (decoded is List) tipologie.addAll(decoded.whereType<String>());
    } catch (_) {}
  }
  return tipologie;
}

/// Assegna a `ordine` l'indice alfabetico corrente (migrazione v1 -> v2:
/// preserva l'ordinamento per nome che l'utente vedeva prima della colonna).
Future<void> _backfillOrdine(Database db, String tabella) async {
  final rows = await db.query(tabella, orderBy: 'nome ASC');
  final batch = db.batch();
  for (int i = 0; i < rows.length; i++) {
    batch.update(tabella, {'ordine': i},
        where: 'id = ?', whereArgs: [rows[i]['id']]);
  }
  await batch.commit(noResult: true);
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

/// Apre il DB: solo i PRAGMA di connessione. Le modifiche allo schema vivono
/// ESCLUSIVAMENTE nel sistema versionato _onCreate/_onUpgrade — il vecchio
/// _runMigrations idempotente (schema completo + ALTER a ogni apertura) è
/// stato rimosso: due sistemi di migrazione paralleli rendevano ambiguo dove
/// aggiungere un cambiamento, l'origine della lezione v4→v5.
/// Il PRAGMA journal_mode va eseguito qui (fuori dalla transazione di
/// _onCreate, dove SQLite rifiuta il passaggio a WAL) e con rawQuery invece
/// di execute: su Android nativo restituisce una riga col nuovo modo, ed
/// execute/execSQL rifiuta le query che restituiscono risultati.
Future<void> _onOpen(Database db) async {
  await db.rawQuery('PRAGMA journal_mode = WAL');
  await db.execute('PRAGMA foreign_keys = ON');
}
