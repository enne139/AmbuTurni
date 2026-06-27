// Client di sincronizzazione: dialoga col backend REST (vedi /backend).
//
// Flusso: login (token JWT) → push delle righe locali modificate (is_synced = 0)
// → pull delle modifiche remote dopo l'ultimo cursore → applicazione in locale.
// Conflitti gestiti lato server con last-write-wins su updated_at.
import { getDb } from '../db';

/** Tabelle sincronizzabili (whitelist: usata anche per validare i nomi in arrivo). */
const SYNC_TABLES = [
  'associazioni',
  'persone',
  'ospedali',
  'tipologie_turno',
  'tipologie_assistenza',
  'turni',
  'assistenze',
  'servizi',
] as const;

type SyncTable = (typeof SYNC_TABLES)[number];

/** Sottoinsieme dell'API del DB usato qui (cast per evitare differenze tra i due backend). */
interface SyncDb {
  execAsync(sql: string): Promise<void>;
  getAllAsync<T>(sql: string, params?: (string | number | null)[]): Promise<T[]>;
  getFirstAsync<T>(sql: string, params?: (string | number | null)[]): Promise<T | null>;
  runAsync(sql: string, params?: (string | number | null)[]): Promise<unknown>;
}

interface RemoteRecord {
  table: string;
  id: string;
  data: Record<string, unknown>;
  deleted: boolean;
}

export interface SyncResult {
  pushed: number;
  pulled: number;
}

async function db(): Promise<SyncDb> {
  return (await getDb()) as unknown as SyncDb;
}

// --- Metadati (sync_meta): server_url, token, last_sync_at ---

async function getMeta(key: string): Promise<string | null> {
  const d = await db();
  const row = await d.getFirstAsync<{ value: string }>(
    'SELECT value FROM sync_meta WHERE key = ?',
    [key]
  );
  return row?.value ?? null;
}

async function setMeta(key: string, value: string | null): Promise<void> {
  const d = await db();
  await d.runAsync(
    'INSERT INTO sync_meta (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value',
    [key, value]
  );
}

export async function getServerUrl(): Promise<string> {
  return (await getMeta('server_url')) ?? '';
}

export async function isLoggedIn(): Promise<boolean> {
  return !!(await getMeta('token'));
}

/** Normalizza l'URL: rimuove gli slash finali. */
function cleanUrl(url: string): string {
  return url.trim().replace(/\/+$/, '');
}

/** Esegue il login e memorizza URL + token. Lancia un errore se fallisce. */
export async function login(serverUrl: string, username: string, password: string): Promise<void> {
  const base = cleanUrl(serverUrl);
  const res = await fetch(`${base}/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username, password }),
  });
  if (!res.ok) {
    throw new Error(res.status === 401 ? 'Credenziali non valide' : `Errore server (${res.status})`);
  }
  const json = (await res.json()) as { token?: string };
  if (!json.token) throw new Error('Risposta del server non valida');
  await setMeta('server_url', base);
  await setMeta('token', json.token);
}

/** Rimuove il token (mantiene l'URL per comodità). */
export async function logout(): Promise<void> {
  await setMeta('token', null);
}

function normalize(v: unknown): string | number | null {
  if (v === null || v === undefined) return null;
  if (typeof v === 'number' || typeof v === 'string') return v;
  if (typeof v === 'boolean') return v ? 1 : 0;
  return String(v);
}

/** Invia al server tutte le righe locali con is_synced = 0; al successo le marca sincronizzate. */
async function pushChanges(base: string, token: string): Promise<number> {
  const d = await db();
  const changes: { table: SyncTable; id: string; data: Record<string, unknown>; updated_at: unknown }[] =
    [];
  const idsByTable: Record<string, string[]> = {};

  for (const table of SYNC_TABLES) {
    const rows = await d.getAllAsync<Record<string, unknown>>(
      `SELECT * FROM ${table} WHERE is_synced = 0`
    );
    for (const row of rows) {
      changes.push({ table, id: String(row.id), data: row, updated_at: row.updated_at });
      (idsByTable[table] ??= []).push(String(row.id));
    }
  }

  if (changes.length === 0) return 0;

  const res = await fetch(`${base}/sync/push`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
    body: JSON.stringify({ changes }),
  });
  if (!res.ok) throw new Error(`Push fallito (${res.status})`);

  // Marca come sincronizzate solo le righe effettivamente inviate.
  for (const [table, ids] of Object.entries(idsByTable)) {
    for (const id of ids) {
      await d.runAsync(`UPDATE ${table} SET is_synced = 1 WHERE id = ?`, [id]);
    }
  }
  return changes.length;
}

/** Scarica le modifiche remote dopo l'ultimo cursore e le applica in locale. */
async function pullChanges(base: string, token: string): Promise<number> {
  const d = await db();
  const since = (await getMeta('last_sync_at')) ?? '1970-01-01T00:00:00Z';

  const res = await fetch(`${base}/sync/pull?since=${encodeURIComponent(since)}`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!res.ok) throw new Error(`Pull fallito (${res.status})`);
  const json = (await res.json()) as { records: RemoteRecord[]; serverTime: string };

  // Applica con foreign key disattivate: i record arrivano in ordine di tempo, non di dipendenza.
  await d.execAsync('PRAGMA foreign_keys = OFF;');
  try {
    for (const rec of json.records) {
      if (!SYNC_TABLES.includes(rec.table as SyncTable)) continue; // tabella non riconosciuta
      if (rec.deleted) {
        await d.runAsync(`DELETE FROM ${rec.table} WHERE id = ?`, [rec.id]);
        continue;
      }
      // I dati remoti sono già "sincronizzati": forziamo is_synced = 1 in locale.
      const data: Record<string, unknown> = { ...rec.data, is_synced: 1 };
      const cols = Object.keys(data);
      const placeholders = cols.map(() => '?').join(', ');
      const params = cols.map((c) => normalize(data[c]));
      await d.runAsync(
        `INSERT OR REPLACE INTO ${rec.table} (${cols.join(', ')}) VALUES (${placeholders})`,
        params
      );
    }
  } finally {
    await d.execAsync('PRAGMA foreign_keys = ON;');
  }

  // Salva il nuovo cursore (orario del server) per la prossima sync.
  await setMeta('last_sync_at', json.serverTime);
  return json.records.length;
}

/** Esegue una sincronizzazione completa (push + pull). Richiede di essere loggati. */
export async function syncNow(): Promise<SyncResult> {
  const base = await getMeta('server_url');
  const token = await getMeta('token');
  if (!base || !token) throw new Error('Non sei autenticato: esegui prima il login.');

  const pushed = await pushChanges(base, token);
  const pulled = await pullChanges(base, token);
  return { pushed, pulled };
}

/**
 * Vecchia firma mantenuta per compatibilità. Usa invece `login()` + `syncNow()`.
 * @deprecated
 */
export async function syncWithServer(serverUrl: string): Promise<void> {
  console.log('[Sync] usa login()/syncNow(). Server URL:', serverUrl);
}
