/**
 * Migrazioni per i database già esistenti (sia native expo-sqlite, sia web sql.js).
 *
 * Lo SCHEMA usa `CREATE TABLE IF NOT EXISTS`, quindi su un DB già creato non
 * applica le modifiche a tabelle esistenti. Qui gestiamo gli aggiornamenti di
 * schema in modo idempotente.
 *
 * Interfaccia minima comune ai due backend.
 */
export interface MigratableDb {
  execAsync(sql: string): Promise<void>;
  getAllAsync<T>(sql: string): Promise<T[]>;
}

interface ColumnInfo {
  name: string;
}

interface TableSql {
  sql: string;
}

/** Esegue tutte le migrazioni necessarie sul database fornito. */
export async function runMigrations(db: MigratableDb): Promise<void> {
  await migrateServizi(db);
  await recomputeAllNumbers(db);
}

/**
 * Corregge la numerazione dei dati esistenti:
 *  - numero_progressivo di turni/assistenze = rango per data nell'associazione
 *  - ordine dei servizi = 1..N per turno (senza buchi)
 * Le query non hanno parametri, quindi si eseguono con execAsync.
 */
async function recomputeAllNumbers(db: MigratableDb): Promise<void> {
  await db.execAsync(`
    UPDATE turni SET numero_progressivo = (
      SELECT COUNT(*) FROM turni t2
      WHERE t2.associazione_id = turni.associazione_id
        AND (t2.data < turni.data
             OR (t2.data = turni.data AND t2.created_at <= turni.created_at))
    ) WHERE associazione_id IS NOT NULL;

    UPDATE assistenze SET numero_progressivo = (
      SELECT COUNT(*) FROM assistenze a2
      WHERE a2.associazione_id = assistenze.associazione_id
        AND (a2.data < assistenze.data
             OR (a2.data = assistenze.data AND a2.created_at <= assistenze.created_at))
    ) WHERE associazione_id IS NOT NULL;

    UPDATE servizi SET ordine = (
      SELECT COUNT(*) FROM servizi s2
      WHERE s2.turno_id = servizi.turno_id
        AND (s2.ordine < servizi.ordine
             OR (s2.ordine = servizi.ordine AND s2.created_at <= servizi.created_at))
    );
  `);
}

/**
 * Aggiorna la tabella `servizi` allo schema corrente:
 *  - colonna `descrizione`
 *  - colonna `ordine` (numero progressivo nel turno)
 *  - CHECK aggiornati: codice_chiamata con 'DIMISSIONE', codice_uscita in MAIUSCOLO
 *
 * SQLite non permette di modificare CHECK/colonne con ALTER complesso: quando
 * serve, ricostruiamo la tabella preservando e normalizzando i dati. Poi
 * inizializziamo `ordine` con un rango 1..N per ciascun turno.
 */
async function migrateServizi(db: MigratableDb): Promise<void> {
  const cols = await db.getAllAsync<ColumnInfo>('PRAGMA table_info(servizi)');
  if (cols.length === 0) return; // tabella non ancora creata: ci pensa lo SCHEMA

  const names = cols.map((c) => c.name);
  const hasDescrizione = names.includes('descrizione');
  const hasOrdine = names.includes('ordine');

  const tableRows = await db.getAllAsync<TableSql>(
    "SELECT sql FROM sqlite_master WHERE type='table' AND name='servizi'"
  );
  const ddl = tableRows[0]?.sql ?? '';
  const checkOk = ddl.includes("'DIMISSIONE'");

  const needsRebuild = !hasDescrizione || !hasOrdine || !checkOk;
  if (!needsRebuild) return;

  // Ricostruzione: si parte dalle sole colonne presenti in tutte le versioni.
  await db.execAsync(`
    PRAGMA foreign_keys = OFF;

    CREATE TABLE servizi_new (
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

    INSERT INTO servizi_new (id, turno_id, codice_chiamata, codice_uscita, ospedale_id, descrizione, ordine, created_at, updated_at, is_synced)
      SELECT
        id,
        turno_id,
        CASE UPPER(codice_chiamata)
          WHEN 'VERDE' THEN 'VERDE'
          WHEN 'GIALLO' THEN 'GIALLO'
          WHEN 'ROSSO' THEN 'ROSSO'
          WHEN 'DIMISSIONE' THEN 'DIMISSIONE'
          ELSE NULL
        END,
        CASE UPPER(codice_uscita)
          WHEN 'VERDE' THEN 'VERDE'
          WHEN 'GIALLO' THEN 'GIALLO'
          WHEN 'ROSSO' THEN 'ROSSO'
          WHEN 'NERO' THEN 'NERO'
          WHEN 'VUOTO' THEN 'VUOTO'
          WHEN 'RIFIUTO' THEN 'RIFIUTO'
          WHEN 'RIFIUTA' THEN 'RIFIUTO'
          ELSE NULL
        END,
        ospedale_id,
        NULL,
        0,
        created_at,
        updated_at,
        is_synced
      FROM servizi;

    DROP TABLE servizi;
    ALTER TABLE servizi_new RENAME TO servizi;

    CREATE INDEX IF NOT EXISTS idx_servizi_turno ON servizi(turno_id);

    -- Inizializza il numero progressivo 1..N per ciascun turno (per created_at, poi id).
    UPDATE servizi SET ordine = (
      SELECT COUNT(*) FROM servizi s2
      WHERE s2.turno_id = servizi.turno_id
        AND (s2.created_at < servizi.created_at
          OR (s2.created_at = servizi.created_at AND s2.id <= servizi.id))
    );

    PRAGMA foreign_keys = ON;
  `);
}
