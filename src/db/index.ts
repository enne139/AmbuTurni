import * as SQLite from 'expo-sqlite';
import { runMigrations } from './migrations';
import { SCHEMA } from './schema';

let dbInstance: SQLite.SQLiteDatabase | null = null;

/**
 * Apre (una sola volta) il database e inizializza lo schema.
 * Restituisce sempre la stessa istanza condivisa.
 */
export async function getDb(): Promise<SQLite.SQLiteDatabase> {
  if (dbInstance) return dbInstance;
  const db = await SQLite.openDatabaseAsync('ambulanza.db');
  await db.execAsync(SCHEMA);
  await runMigrations(db);
  dbInstance = db;
  return db;
}

/** Inizializza il DB all'avvio dell'app. */
export async function initDatabase(): Promise<void> {
  await getDb();
}
