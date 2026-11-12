import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import '../utils/platform_check.dart';

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
  via TEXT,
  lat REAL,
  lng REAL,
  regione TEXT,
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
  orario TEXT,
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
  is_synced INTEGER DEFAULT 0,
  campi TEXT DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS assistenze (
  id TEXT PRIMARY KEY,
  associazione_id TEXT REFERENCES associazioni(id),
  numero_progressivo INTEGER,
  data TEXT NOT NULL,
  ore REAL,
  orario TEXT,
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
CREATE INDEX IF NOT EXISTS idx_servizi_ospedale ON servizi(ospedale_id);
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
  is_synced INTEGER DEFAULT 0,
  mezzo TEXT
);

CREATE TABLE IF NOT EXISTS campi_servizio (
  id TEXT PRIMARY KEY,
  nome TEXT NOT NULL,
  tipo TEXT NOT NULL CHECK (tipo IN ('TENDINA','COLORI','TESTO','NUMERO','SESSO_ETA','ORARIO','COMBO')),
  opzioni TEXT DEFAULT '[]',
  visibile INTEGER NOT NULL DEFAULT 1,
  ordine INTEGER DEFAULT 0,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

''';

/// Versione corrente dello schema: ogni cambiamento allo schema la fa salire
/// di uno, con la sua migrazione in _onUpgrade (regola 7 del CLAUDE.md).
const int kVersioneDb = 17;

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

/// Solo per i test delle migrazioni: apre (o crea) il DB nel file [path]
/// alla [version] indicata con le migrazioni vere, così un test può creare
/// un DB con lo schema di una versione vecchia, chiuderlo e riaprirlo qui
/// per verificare che _onUpgrade porti i dati nella forma nuova.
@visibleForTesting
Future<Database> openTestDbAt(String path, {int version = kVersioneDb}) {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  return openDatabase(
    path,
    version: version,
    onCreate: _onCreate,
    onUpgrade: _onUpgrade,
    onOpen: _onOpen,
  );
}

/// Restituisce l'istanza aperta del DB, inizializzandola se necessario.
/// Su desktop (Windows/Linux/macOS) usa sqflite_common_ffi perché sqflite
/// nativo non è disponibile fuori da Android/iOS; su web usa
/// sqflite_common_ffi_web (SQLite compilato in WASM, persistito in IndexedDB
/// via il worker generato da `dart run sqflite_common_ffi_web:setup` in
/// web/sqflite_sw.js + web/sqlite3.wasm) perché né sqflite né la FFI nativa
/// esistono nel browser. Su web NON si passa da `getDatabasesPath()`: quella
/// chiamata lancia (`getDatabasesPath is null`, verificato a runtime in
/// Chrome) perché il metodo non è cablato in questa implementazione — si usa
/// direttamente un nome fisso come path, come nell'esempio del pacchetto
/// (il "filesystem" reale è IndexedDB, il nome è solo una chiave).
Future<Database> getDb() async {
  if (_db != null) return _db!;
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  } else if (isDesktop) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  final dbPath = kIsWeb
      ? 'ambulanza_turni.db'
      : join(await getDatabasesPath(), 'ambulanza_turni.db');
  _db = await openDatabase(
    dbPath,
    version: kVersioneDb,
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
  if (oldVersion < 9) {
    // Tool "Lista ospedali": via (indirizzo testuale) e lat/lng (geocoding
    // automatico via Nominatim, best-effort — restano NULL se il servizio
    // non risolve l'indirizzo o il device è offline al momento del salvataggio).
    try { await db.execute('ALTER TABLE ospedali ADD COLUMN via TEXT'); } catch (_) {}
    try { await db.execute('ALTER TABLE ospedali ADD COLUMN lat REAL'); } catch (_) {}
    try { await db.execute('ALTER TABLE ospedali ADD COLUMN lng REAL'); } catch (_) {}
  }
  if (oldVersion < 10) {
    // La sincronizzazione col vecchio backend generico non è mai stata
    // completata lato client (nessuna chiamata la usava davvero, vedi CLAUDE.md):
    // queste due tabelle erano solo scaffolding per quella funzionalità, ora
    // abbandonata a favore del backend condiviso ospedali (tool Lista
    // ospedali). Le colonne `is_synced` sulle altre tabelle restano: erano
    // scritte/lette solo da qui, toglierle richiederebbe ricostruire ogni
    // tabella per un beneficio nullo.
    try { await db.execute('DROP TABLE IF EXISTS sync_meta'); } catch (_) {}
    try { await db.execute('DROP TABLE IF EXISTS deletions'); } catch (_) {}
  }
  if (oldVersion < 11) {
    // Tool "Lista ospedali": regione, come lat/lng calcolata dal geocoding
    // dell'indirizzo (o inserita a mano) — usata per raggruppare la lista e
    // per scaricare in blocco gli ospedali di un'intera regione dal backend
    // condiviso.
    try { await db.execute('ALTER TABLE ospedali ADD COLUMN regione TEXT'); } catch (_) {}
  }
  if (oldVersion < 12) {
    // "Vedi turni" di un ospedale (getTurniPerOspedale) filtra su
    // servizi.ospedale_id senza indice: con anni di turni/servizi accumulati
    // la query degenera in uno scan completo della tabella servizi.
    try { await db.execute('CREATE INDEX IF NOT EXISTS idx_servizi_ospedale ON servizi(ospedale_id)'); } catch (_) {}
  }
  if (oldVersion < 13) {
    // Tools -> Materiali usati: da quale mezzo (ambulanza, numero a due
    // cifre scaricato dal backend condiviso) è stato preso il materiale.
    // Testo e non FK: i mezzi vivono sul backend, non in una tabella
    // locale — un mezzo tolto dalla pagina admin non deve invalidare le
    // righe già registrate. Le righe esistenti restano senza mezzo (NULL).
    try { await db.execute('ALTER TABLE materiali_usati ADD COLUMN mezzo TEXT'); } catch (_) {}
  }
  if (oldVersion < 14) {
    // Turni e assistenze: il campo "Descrizione" diventa "Orario" (testo
    // corto, es. "12:00 - 18:00"). Le descrizioni già salvate erano di fatto
    // tutte orari (indicazione dell'utente), quindi passano così come sono.
    // Niente ALTER TABLE ... RENAME COLUMN: richiede SQLite 3.25, che i
    // telefoni Android più vecchi (API < 30) non hanno. Le tabelle vengono
    // ricostruite come nella v8, con le FK spente durante onUpgrade: il DROP
    // di turni non tocca i servizi figli, che restano validi perché gli id
    // non cambiano. Gli statement CREATE sono copiati qui e non presi da
    // _schema, perché una migrazione deve restare uguale anche quando lo
    // schema corrente cambierà ancora.
    await _rinominaDescrizioneInOrario(db, 'turni', '''
      CREATE TABLE turni (
        id TEXT PRIMARY KEY,
        associazione_id TEXT REFERENCES associazioni(id),
        numero_progressivo INTEGER,
        data TEXT NOT NULL,
        ore REAL,
        tipologie TEXT DEFAULT '[]',
        num_servizi INTEGER DEFAULT 0,
        orario TEXT,
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
    ''', 'CREATE INDEX IF NOT EXISTS idx_turni_assoc ON turni(associazione_id)');
    await _rinominaDescrizioneInOrario(db, 'assistenze', '''
      CREATE TABLE assistenze (
        id TEXT PRIMARY KEY,
        associazione_id TEXT REFERENCES associazioni(id),
        numero_progressivo INTEGER,
        data TEXT NOT NULL,
        ore REAL,
        orario TEXT,
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
      )
    ''', 'CREATE INDEX IF NOT EXISTS idx_assistenze_assoc ON assistenze(associazione_id)');
  }
  if (oldVersion < 15) {
    // Campi personalizzati dei servizi: la tabella delle definizioni (nome,
    // tipo, valori possibili, mostrato o nascosto) e, nei servizi, una
    // colonna JSON id campo -> valore, come `tipologie` nei turni. I servizi
    // esistenti partono senza valori ('{}'). Niente is_synced: è un resto
    // della vecchia sincronizzazione, le tabelle nuove non lo hanno.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS campi_servizio (
        id TEXT PRIMARY KEY,
        nome TEXT NOT NULL,
        tipo TEXT NOT NULL CHECK (tipo IN ('TENDINA','COLORI','TESTO','NUMERO')),
        opzioni TEXT DEFAULT '[]',
        visibile INTEGER NOT NULL DEFAULT 1,
        ordine INTEGER DEFAULT 0,
        created_at TEXT DEFAULT (datetime('now')),
        updated_at TEXT DEFAULT (datetime('now'))
      )
    ''');
    try { await db.execute("ALTER TABLE servizi ADD COLUMN campi TEXT DEFAULT '{}'"); } catch (_) {}
    await _inserisciCampiServizioIniziali(db, _campiServizioV15);
  }
  if (oldVersion < 16) {
    // Sesso ed età diventano un campo speciale unico, coi due controlli
    // affiancati (richiesta dell'utente arrivata dopo la v15). Il tipo
    // SESSO_ETA va aggiunto al CHECK di campi_servizio, e SQLite non cambia
    // un CHECK con ALTER: la tabella si ricostruisce (nessuna FK punta qui).
    final sql = (await db.rawQuery(
            "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'campi_servizio'"))
        .first['sql'] as String;
    if (!sql.contains('SESSO_ETA')) {
      final righe = await db.query('campi_servizio');
      await db.execute('DROP TABLE campi_servizio');
      await db.execute('''
        CREATE TABLE campi_servizio (
          id TEXT PRIMARY KEY,
          nome TEXT NOT NULL,
          tipo TEXT NOT NULL CHECK (tipo IN ('TENDINA','COLORI','TESTO','NUMERO','SESSO_ETA')),
          opzioni TEXT DEFAULT '[]',
          visibile INTEGER NOT NULL DEFAULT 1,
          ordine INTEGER DEFAULT 0,
          created_at TEXT DEFAULT (datetime('now')),
          updated_at TEXT DEFAULT (datetime('now'))
        )
      ''');
      for (final riga in righe) {
        await db.insert('campi_servizio', riga);
      }
    }
    await _unisciSessoEta(db);
  }
  if (oldVersion < 17) {
    // Due tipi di campo nuovi, orario e combo box (richiesta dell'utente):
    // vanno nel CHECK di campi_servizio, che si ricostruisce come nella v16.
    // I valori dei servizi non cambiano.
    final sql = (await db.rawQuery(
            "SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'campi_servizio'"))
        .first['sql'] as String;
    if (!sql.contains('COMBO')) {
      final righe = await db.query('campi_servizio');
      await db.execute('DROP TABLE campi_servizio');
      await db.execute('''
        CREATE TABLE campi_servizio (
          id TEXT PRIMARY KEY,
          nome TEXT NOT NULL,
          tipo TEXT NOT NULL CHECK (tipo IN ('TENDINA','COLORI','TESTO','NUMERO','SESSO_ETA','ORARIO','COMBO')),
          opzioni TEXT DEFAULT '[]',
          visibile INTEGER NOT NULL DEFAULT 1,
          ordine INTEGER DEFAULT 0,
          created_at TEXT DEFAULT (datetime('now')),
          updated_at TEXT DEFAULT (datetime('now'))
        )
      ''');
      for (final riga in righe) {
        await db.insert('campi_servizio', riga);
      }
    }
  }
}

/// v16: porta i campi separati "Sesso" (tendina) ed "Età" (numero) creati
/// dalla v15 nel campo speciale `sesso_eta`, insieme ai loro valori nei
/// servizi ({"sesso": id, "eta": numero}). Se uno dei due era stato
/// cancellato si usa quello che resta; se mancano tutti e due lo speciale
/// nasce nascosto, per rispettare la scelta di averli tolti, con i valori
/// M, F, A. Non fa niente se lo speciale c'è già.
Future<void> _unisciSessoEta(Database db) async {
  final campi = await db.query('campi_servizio');
  if (campi.any((c) => c['tipo'] == 'SESSO_ETA')) return;
  Map<String, Object?>? cerca(String id, String tipo) {
    for (final c in campi) {
      if (c['id'] == id && c['tipo'] == tipo) return c;
    }
    return null;
  }

  final sesso = cerca('sesso', 'TENDINA');
  final eta = cerca('eta', 'NUMERO');
  final vecchi = [if (sesso != null) sesso, if (eta != null) eta];
  final adesso = DateTime.now().toUtc().toIso8601String();
  await db.insert('campi_servizio', {
    'id': 'sesso_eta',
    'nome': 'Sesso ed età',
    'tipo': 'SESSO_ETA',
    'opzioni': sesso?['opzioni'] ?? jsonEncode(_opzioniSesso),
    'visibile': vecchi.isEmpty ? 0 : (vecchi.any((c) => c['visibile'] == 1) ? 1 : 0),
    // Al posto del primo dei due; se non c'erano, in fondo.
    'ordine': vecchi.isEmpty
        ? campi.length
        : vecchi.map((c) => (c['ordine'] as int?) ?? 0).reduce((a, b) => a < b ? a : b),
    'created_at': adesso,
    'updated_at': adesso,
  });
  if (vecchi.isEmpty) return;

  final servizi = await db.query('servizi',
      columns: ['id', 'campi'], where: "campi IS NOT NULL AND campi != '{}'");
  for (final servizio in servizi) {
    final Map<String, dynamic> valori;
    try {
      final decoded = jsonDecode(servizio['campi'] as String);
      if (decoded is! Map) continue;
      valori = Map<String, dynamic>.from(decoded);
    } catch (_) {
      continue; // JSON rovinato: il servizio resta com'era
    }
    final haSesso = sesso != null && valori.containsKey('sesso');
    final haEta = eta != null && valori.containsKey('eta');
    if (!haSesso && !haEta) continue;
    final valoreSesso = haSesso ? valori.remove('sesso') : null;
    final valoreEta = haEta ? valori.remove('eta') : null;
    final unito = <String, dynamic>{
      if (valoreSesso is String) 'sesso': valoreSesso,
      if (valoreEta is num) 'eta': valoreEta,
    };
    if (unito.isNotEmpty) valori['sesso_eta'] = unito;
    await db.update('servizi', {'campi': jsonEncode(valori)},
        where: 'id = ?', whereArgs: [servizio['id']]);
  }
  for (final c in vecchi) {
    await db.delete('campi_servizio', where: 'id = ?', whereArgs: [c['id']]);
  }
}

/// Valori del sesso con cui parte il campo speciale (indicati dall'utente).
const _opzioniSesso = [
  {'id': 'm', 'nome': 'M'},
  {'id': 'f', 'nome': 'F'},
  {'id': 'a', 'nome': 'A'},
];

/// "Colore invio": colori presi dalla palette dell'app, così si ritrovano
/// uguali nel selettore quando si modifica il campo.
const _campoColoreInvio = {
  'id': 'colore_invio',
  'nome': 'Colore invio',
  'tipo': 'COLORI',
  'opzioni': [
    {'id': 'verde', 'nome': 'Verde', 'colore': '#43A047'},
    {'id': 'giallo', 'nome': 'Giallo', 'colore': '#FDD835'},
    {'id': 'rosso', 'nome': 'Rosso', 'colore': '#E53935'},
  ],
};

/// Campi personalizzati con cui parte una installazione nuova (indicati
/// dall'utente): il campo speciale sesso ed età e Colore invio. Id fissi e
/// leggibili al posto degli UUID: sono uguali su ogni dispositivo.
const _campiServizioIniziali = [
  {'id': 'sesso_eta', 'nome': 'Sesso ed età', 'tipo': 'SESSO_ETA', 'opzioni': _opzioniSesso},
  _campoColoreInvio,
];

/// I campi iniziali come li creava la migrazione v15, quando sesso ed età
/// erano ancora due campi separati: la migrazione deve restare uguale anche
/// se i campi iniziali cambiano, e la v16 li unisce nel campo speciale.
const _campiServizioV15 = [
  {'id': 'sesso', 'nome': 'Sesso', 'tipo': 'TENDINA', 'opzioni': _opzioniSesso},
  {'id': 'eta', 'nome': 'Età', 'tipo': 'NUMERO', 'opzioni': []},
  _campoColoreInvio,
];

/// Inserisce [campi] solo se la tabella è vuota: se l'utente li ha già
/// cancellati o cambiati non vanno ricreati.
Future<void> _inserisciCampiServizioIniziali(Database db, List<Map<String, Object>> campi) async {
  final n = (await db.rawQuery('SELECT COUNT(*) AS n FROM campi_servizio')).first['n'] as int;
  if (n > 0) return;
  final adesso = DateTime.now().toUtc().toIso8601String();
  for (var i = 0; i < campi.length; i++) {
    final campo = campi[i];
    await db.insert('campi_servizio', {
      'id': campo['id'],
      'nome': campo['nome'],
      'tipo': campo['tipo'],
      'opzioni': jsonEncode(campo['opzioni']),
      'visibile': 1,
      'ordine': i,
      'created_at': adesso,
      'updated_at': adesso,
    });
  }
}

/// Ricostruisce [tabella] con [creaTabella] (stesso schema, ma `orario` al
/// posto di `descrizione`) e ci ricopia le righe spostando il valore da una
/// colonna all'altra. Gira solo se la tabella ha ancora la colonna vecchia:
/// rilanciata su una tabella già convertita non fa niente. [indice] va
/// ricreato perché il DROP lo elimina insieme alla tabella.
Future<void> _rinominaDescrizioneInOrario(
    Database db, String tabella, String creaTabella, String indice) async {
  final cols = await db.rawQuery('PRAGMA table_info($tabella)');
  if (!cols.any((c) => c['name'] == 'descrizione')) return;
  final righe = await db.query(tabella);
  await db.execute('DROP TABLE $tabella');
  await db.execute(creaTabella);
  await db.execute(indice);
  for (final riga in righe) {
    final nuovaRiga = Map<String, dynamic>.from(riga);
    nuovaRiga['orario'] = nuovaRiga.remove('descrizione');
    await db.insert(tabella, nuovaRiga);
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
  await _inserisciCampiServizioIniziali(db, _campiServizioIniziali);
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
/// Su web niente WAL: il DB WASM non ha un vero filesystem con locking tra
/// processi (persiste tramite un worker su IndexedDB), quindi il problema
/// che il WAL risolveva su Android non si pone.
Future<void> _onOpen(Database db) async {
  if (!kIsWeb) {
    await db.rawQuery('PRAGMA journal_mode = WAL');
  }
  await db.execute('PRAGMA foreign_keys = ON');
}
