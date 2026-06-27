import { getDb } from './index';

/**
 * Esportazione / importazione completa del database in JSON (backup locale).
 */

const TABLES = [
  'associazioni',
  'persone',
  'ospedali',
  'tipologie_turno',
  'tipologie_assistenza',
  'turni',
  'servizi',
  'assistenze',
] as const;

type TableName = (typeof TABLES)[number];

/** Ordine di inserimento che rispetta le foreign key (lookup prima dei figli). */
const INSERT_ORDER: TableName[] = [
  'associazioni',
  'persone',
  'ospedali',
  'tipologie_turno',
  'tipologie_assistenza',
  'turni',
  'assistenze',
  'servizi',
];

export interface BackupData {
  app: string;
  version: number;
  exportedAt: string;
  tables: Record<TableName, Record<string, unknown>[]>;
}

interface BackupDb {
  execAsync(sql: string): Promise<void>;
  getAllAsync<T>(sql: string): Promise<T[]>;
  runAsync(sql: string, params: (string | number | null)[]): Promise<unknown>;
}

/** Costruisce il JSON di backup con tutte le tabelle. */
export async function exportData(): Promise<string> {
  const db = (await getDb()) as BackupDb;
  const tables = {} as Record<TableName, Record<string, unknown>[]>;
  for (const t of TABLES) {
    tables[t] = await db.getAllAsync<Record<string, unknown>>(`SELECT * FROM ${t}`);
  }
  const backup: BackupData = {
    app: 'ambulanza-turni',
    version: 1,
    exportedAt: new Date().toISOString(),
    tables,
  };
  return JSON.stringify(backup, null, 2);
}

/** Numero totale di record in un backup (per messaggi all'utente). */
export function countRecords(data: BackupData): number {
  return TABLES.reduce((sum, t) => sum + (data.tables[t]?.length ?? 0), 0);
}

/** Valida e fa il parse del testo JSON di backup. */
export function parseBackup(json: string): BackupData {
  const parsed = JSON.parse(json) as Partial<BackupData>;
  if (!parsed || typeof parsed !== 'object' || !parsed.tables) {
    throw new Error('File non valido: manca la sezione "tables".');
  }
  return parsed as BackupData;
}

function normalizeValue(v: unknown): string | number | null {
  if (v === null || v === undefined) return null;
  if (typeof v === 'number' || typeof v === 'string') return v;
  if (typeof v === 'boolean') return v ? 1 : 0;
  return String(v);
}

/**
 * Importa i dati sostituendo completamente quelli attuali (restore).
 */
export async function importData(json: string): Promise<number> {
  const data = parseBackup(json);
  const db = (await getDb()) as BackupDb;

  await db.execAsync('PRAGMA foreign_keys = OFF;');
  try {
    // Svuota tutte le tabelle (figli prima, ma con FK off l'ordine non è critico).
    for (const t of [...INSERT_ORDER].reverse()) {
      await db.execAsync(`DELETE FROM ${t};`);
    }

    // Reinserisce nell'ordine corretto.
    let total = 0;
    for (const t of INSERT_ORDER) {
      const rows = data.tables[t] ?? [];
      for (const row of rows) {
        const cols = Object.keys(row);
        if (cols.length === 0) continue;
        const placeholders = cols.map(() => '?').join(', ');
        const params = cols.map((c) => normalizeValue(row[c]));
        await db.runAsync(
          `INSERT OR REPLACE INTO ${t} (${cols.join(', ')}) VALUES (${placeholders})`,
          params
        );
        total += 1;
      }
    }
    return total;
  } finally {
    await db.execAsync('PRAGMA foreign_keys = ON;');
  }
}
