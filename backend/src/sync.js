// Logica di sincronizzazione: push (dal client) e pull (verso il client).
import { pool } from './db.js';

/**
 * Applica le modifiche inviate dal client.
 * @param {Array<{table:string,id:string,data:object,updated_at?:string,deleted?:boolean}>} changes
 * @returns {Promise<{applied:number, serverTime:string}>}
 *
 * Conflitti risolti con last-write-wins sul campo `client_updated_at`: una
 * modifica viene applicata solo se è più recente (o uguale) di quella memorizzata.
 * `updated_at` (orario server) viene sempre aggiornato così il pull la includerà.
 */
export async function push(changes) {
  let applied = 0;
  for (const c of changes) {
    if (!c || !c.table || !c.id) continue;
    const res = await pool.query(
      `INSERT INTO records (table_name, id, data, client_updated_at, updated_at, deleted)
       VALUES ($1, $2, $3, $4, now(), $5)
       ON CONFLICT (table_name, id) DO UPDATE
         SET data = EXCLUDED.data,
             client_updated_at = EXCLUDED.client_updated_at,
             updated_at = now(),
             deleted = EXCLUDED.deleted
         WHERE EXCLUDED.client_updated_at >= records.client_updated_at
            OR records.client_updated_at IS NULL`,
      [c.table, c.id, c.data ?? {}, c.updated_at ?? null, c.deleted ?? false]
    );
    applied += res.rowCount;
  }
  const t = await pool.query('SELECT now() AS now');
  return { applied, serverTime: t.rows[0].now };
}

/**
 * Restituisce tutti i record modificati lato server dopo `since`.
 * @param {string} since timestamp ISO (cursore dell'ultima sync del client)
 * @returns {Promise<{records:Array, serverTime:string}>}
 */
export async function pull(since) {
  const r = await pool.query(
    `SELECT table_name AS "table", id, data, deleted
     FROM records
     WHERE updated_at > $1
     ORDER BY updated_at ASC`,
    [since]
  );
  const t = await pool.query('SELECT now() AS now');
  return { records: r.rows, serverTime: t.rows[0].now };
}
