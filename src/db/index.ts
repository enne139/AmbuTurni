import * as SQLite from 'expo-sqlite';

let dbInstance: SQLite.SQLiteDatabase | null = null;

/** Schema completo del database locale. */
const SCHEMA = `
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
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now')),
  is_synced INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS tipologie_assistenza (
  id TEXT PRIMARY KEY,
  nome TEXT NOT NULL UNIQUE,
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
  codice_chiamata TEXT CHECK (codice_chiamata IN ('VERDE','GIALLO','ROSSO')),
  codice_uscita   TEXT CHECK (codice_uscita IN ('verde','giallo','rosso','nero','vuoto','rifiuta')),
  ospedale_id TEXT REFERENCES ospedali(id),
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
`;

/**
 * Apre (una sola volta) il database e inizializza lo schema.
 * Restituisce sempre la stessa istanza condivisa.
 */
export async function getDb(): Promise<SQLite.SQLiteDatabase> {
  if (dbInstance) return dbInstance;
  const db = await SQLite.openDatabaseAsync('ambulanza.db');
  await db.execAsync(SCHEMA);
  dbInstance = db;
  return db;
}

/** Inizializza il DB all'avvio dell'app. */
export async function initDatabase(): Promise<void> {
  await getDb();
}
