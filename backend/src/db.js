// Connessione a PostgreSQL e inizializzazione dello schema del backend di sync.
import pg from 'pg';

const { Pool } = pg;

// Pool di connessioni. Usa DATABASE_URL (consigliato) oppure le variabili PG* standard.
export const pool = new Pool(
  process.env.DATABASE_URL
    ? { connectionString: process.env.DATABASE_URL }
    : {
        host: process.env.PGHOST || 'db',
        port: Number(process.env.PGPORT || 5432),
        user: process.env.PGUSER || 'ambulanza',
        password: process.env.PGPASSWORD || 'ambulanza',
        database: process.env.PGDATABASE || 'ambulanza',
      }
);

/**
 * Crea le tabelle se non esistono.
 *
 * - `users`: credenziali (password con hash bcrypt) per il login.
 * - `records`: archivio generico dei dati sincronizzati. Ogni riga delle tabelle
 *   dell'app (turni, servizi, ecc.) è salvata come JSON, identificata da
 *   (table_name, id). `client_updated_at` serve per il last-write-wins;
 *   `updated_at` (orario server) è il cursore usato dal pull.
 */
export async function initSchema() {
  await pool.query(`
    CREATE TABLE IF NOT EXISTS users (
      username TEXT PRIMARY KEY,
      password_hash TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now()
    );

    CREATE TABLE IF NOT EXISTS records (
      table_name        TEXT NOT NULL,
      id                TEXT NOT NULL,
      data              JSONB NOT NULL,
      client_updated_at TIMESTAMPTZ,
      updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
      deleted           BOOLEAN NOT NULL DEFAULT false,
      PRIMARY KEY (table_name, id)
    );

    CREATE INDEX IF NOT EXISTS idx_records_updated ON records (updated_at);
  `);
}
