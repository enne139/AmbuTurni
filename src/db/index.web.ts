import initSqlJs from 'sql.js';
import { runMigrations } from './migrations';
import { SCHEMA } from './schema';

/**
 * Backend database per il WEB.
 *
 * `expo-sqlite` non ha implementazione web in SDK 52: per far girare l'app nel
 * browser usiamo `sql.js` (SQLite compilato in WebAssembly, puro JS) e mimiamo la
 * stessa API asincrona di expo-sqlite usata in `src/db/helpers.ts`
 * (`execAsync`, `getAllAsync`, `getFirstAsync`, `runAsync`).
 *
 * La persistenza avviene su `localStorage`: il database viene esportato (bytes)
 * e salvato come base64 a ogni mutazione. Su native resta invece `src/db/index.ts`.
 */

type SqlParam = string | number | null;

export interface WebSQLiteDatabase {
  execAsync(sql: string): Promise<void>;
  getAllAsync<T>(sql: string, params?: SqlParam[]): Promise<T[]>;
  getFirstAsync<T>(sql: string, params?: SqlParam[]): Promise<T | null>;
  runAsync(
    sql: string,
    params?: SqlParam[]
  ): Promise<{ lastInsertRowId: number; changes: number }>;
}

const STORAGE_KEY = 'ambulanza.db';

// Accesso ai global del browser senza dipendere dalla lib DOM in tsconfig.
const webGlobal = globalThis as unknown as {
  localStorage?: {
    getItem(key: string): string | null;
    setItem(key: string, value: string): void;
  };
  btoa(data: string): string;
  atob(data: string): string;
};

function uint8ToBase64(bytes: Uint8Array): string {
  let binary = '';
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...Array.from(bytes.subarray(i, i + chunk)));
  }
  return webGlobal.btoa(binary);
}

function base64ToUint8(b64: string): Uint8Array {
  const binary = webGlobal.atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

class SqlJsDatabase implements WebSQLiteDatabase {
  // `db` è un'istanza sql.js (tipizzata come any tramite la dichiarazione di modulo).
  constructor(private readonly db: any) {}

  private persist(): void {
    try {
      const data: Uint8Array = this.db.export();
      webGlobal.localStorage?.setItem(STORAGE_KEY, uint8ToBase64(data));
    } catch (e) {
      console.warn('[web-db] persistenza fallita:', e);
    }
  }

  async execAsync(sql: string): Promise<void> {
    this.db.exec(sql);
    this.persist();
  }

  async getAllAsync<T>(sql: string, params: SqlParam[] = []): Promise<T[]> {
    const stmt = this.db.prepare(sql);
    try {
      if (params.length) stmt.bind(params);
      const rows: T[] = [];
      while (stmt.step()) rows.push(stmt.getAsObject() as T);
      return rows;
    } finally {
      stmt.free();
    }
  }

  async getFirstAsync<T>(sql: string, params: SqlParam[] = []): Promise<T | null> {
    const stmt = this.db.prepare(sql);
    try {
      if (params.length) stmt.bind(params);
      return stmt.step() ? (stmt.getAsObject() as T) : null;
    } finally {
      stmt.free();
    }
  }

  async runAsync(
    sql: string,
    params: SqlParam[] = []
  ): Promise<{ lastInsertRowId: number; changes: number }> {
    this.db.run(sql, params);
    this.persist();
    return { lastInsertRowId: 0, changes: this.db.getRowsModified() };
  }
}

let dbPromise: Promise<WebSQLiteDatabase> | null = null;

async function open(): Promise<WebSQLiteDatabase> {
  const SQL = await initSqlJs({
    locateFile: (file: string) => `https://cdn.jsdelivr.net/npm/sql.js@1.14.1/dist/${file}`,
  });
  const saved = webGlobal.localStorage?.getItem(STORAGE_KEY);
  const db = saved ? new SQL.Database(base64ToUint8(saved)) : new SQL.Database();
  const wrapper = new SqlJsDatabase(db);
  await wrapper.execAsync(SCHEMA);
  await runMigrations(wrapper);
  return wrapper;
}

export async function getDb(): Promise<WebSQLiteDatabase> {
  if (!dbPromise) dbPromise = open();
  return dbPromise;
}

export async function initDatabase(): Promise<void> {
  await getDb();
}
