import { v4 as uuidv4 } from 'uuid';
import { getDb } from './index';

// ---------------------------------------------------------------------------
// TIPI
// ---------------------------------------------------------------------------

/** Voce generica usata dai campi selezionabili. */
export interface LookupItem {
  id: string;
  label: string;
}

export interface Associazione {
  id: string;
  nome: string;
  created_at: string;
  updated_at: string;
  is_synced: number;
}

export interface Persona {
  id: string;
  nome: string;
  cognome: string;
  created_at: string;
  updated_at: string;
  is_synced: number;
}

export interface Ospedale {
  id: string;
  nome: string;
  citta: string | null;
  created_at: string;
  updated_at: string;
  is_synced: number;
}

export interface Tipologia {
  id: string;
  nome: string;
  created_at: string;
  updated_at: string;
  is_synced: number;
}

export type CodiceChiamata = 'VERDE' | 'GIALLO' | 'ROSSO';
export type CodiceUscita = 'verde' | 'giallo' | 'rosso' | 'nero' | 'vuoto' | 'rifiuta';

/** Campi equipaggio condivisi da turni e assistenze. */
export interface EquipaggioFields {
  eq1_autista_id: string | null;
  eq1_cs_id: string | null;
  eq1_terzo_id: string | null;
  eq1_quarto_id: string | null;
  eq1_centralinista_id: string | null;
  eq2_autista_id: string | null;
  eq2_cs_id: string | null;
  eq2_terzo_id: string | null;
  eq2_quarto_id: string | null;
  eq2_centralinista_id: string | null;
}

export interface Turno extends EquipaggioFields {
  id: string;
  associazione_id: string | null;
  numero_progressivo: number | null;
  data: string;
  ore: number | null;
  tipologia_id: string | null;
  tipologie_extra: string; // JSON array (stringa)
  num_servizi: number;
  descrizione: string | null;
  note: string | null;
  created_at: string;
  updated_at: string;
  is_synced: number;
}

/** Turno con i nomi denormalizzati per le liste. */
export interface TurnoRow extends Turno {
  associazione_nome: string | null;
  tipologia_nome: string | null;
}

export interface Servizio {
  id: string;
  turno_id: string;
  codice_chiamata: CodiceChiamata | null;
  codice_uscita: CodiceUscita | null;
  ospedale_id: string | null;
  created_at: string;
  updated_at: string;
  is_synced: number;
}

export interface ServizioRow extends Servizio {
  ospedale_nome: string | null;
}

export interface Assistenza extends EquipaggioFields {
  id: string;
  associazione_id: string | null;
  numero_progressivo: number | null;
  data: string;
  ore: number | null;
  descrizione: string | null;
  note: string | null;
  created_at: string;
  updated_at: string;
  is_synced: number;
}

export interface AssistenzaRow extends Assistenza {
  associazione_nome: string | null;
}

/** Input per il salvataggio di un turno. */
export interface TurnoInput extends EquipaggioFields {
  id?: string;
  associazione_id: string | null;
  data: string;
  ore: number | null;
  tipologia_id: string | null;
  tipologie_extra: string[];
  descrizione: string | null;
  note: string | null;
}

/** Input per il salvataggio di un'assistenza. */
export interface AssistenzaInput extends EquipaggioFields {
  id?: string;
  associazione_id: string | null;
  data: string;
  ore: number | null;
  descrizione: string | null;
  note: string | null;
}

const EMPTY_EQUIPAGGIO: EquipaggioFields = {
  eq1_autista_id: null,
  eq1_cs_id: null,
  eq1_terzo_id: null,
  eq1_quarto_id: null,
  eq1_centralinista_id: null,
  eq2_autista_id: null,
  eq2_cs_id: null,
  eq2_terzo_id: null,
  eq2_quarto_id: null,
  eq2_centralinista_id: null,
};

export const emptyEquipaggio = (): EquipaggioFields => ({ ...EMPTY_EQUIPAGGIO });

function nowISO(): string {
  return new Date().toISOString();
}

// ---------------------------------------------------------------------------
// LOOKUP: ASSOCIAZIONI
// ---------------------------------------------------------------------------

export async function getAssociazioni(): Promise<Associazione[]> {
  const db = await getDb();
  return db.getAllAsync<Associazione>('SELECT * FROM associazioni ORDER BY nome COLLATE NOCASE');
}

export async function getAssociazioniLookup(): Promise<LookupItem[]> {
  const rows = await getAssociazioni();
  return rows.map((r) => ({ id: r.id, label: r.nome }));
}

export async function addAssociazione(nome: string): Promise<LookupItem> {
  const db = await getDb();
  const trimmed = nome.trim();
  const existing = await db.getFirstAsync<Associazione>(
    'SELECT * FROM associazioni WHERE nome = ? COLLATE NOCASE',
    [trimmed]
  );
  if (existing) return { id: existing.id, label: existing.nome };
  const id = uuidv4();
  const ts = nowISO();
  await db.runAsync(
    'INSERT INTO associazioni (id, nome, created_at, updated_at, is_synced) VALUES (?, ?, ?, ?, 0)',
    [id, trimmed, ts, ts]
  );
  return { id, label: trimmed };
}

export async function deleteAssociazione(id: string): Promise<void> {
  const db = await getDb();
  await db.runAsync('DELETE FROM associazioni WHERE id = ?', [id]);
}

// ---------------------------------------------------------------------------
// LOOKUP: PERSONE
// ---------------------------------------------------------------------------

export async function getPersone(): Promise<Persona[]> {
  const db = await getDb();
  return db.getAllAsync<Persona>(
    'SELECT * FROM persone ORDER BY cognome COLLATE NOCASE, nome COLLATE NOCASE'
  );
}

export async function getPersoneLookup(): Promise<LookupItem[]> {
  const rows = await getPersone();
  return rows.map((r) => ({ id: r.id, label: `${r.cognome} ${r.nome}`.trim() }));
}

/** Aggiunge una persona con cognome e nome separati. */
export async function addPersona(cognome: string, nome: string): Promise<LookupItem> {
  const db = await getDb();
  const id = uuidv4();
  const ts = nowISO();
  const c = cognome.trim();
  const n = nome.trim();
  await db.runAsync(
    'INSERT INTO persone (id, nome, cognome, created_at, updated_at, is_synced) VALUES (?, ?, ?, ?, ?, 0)',
    [id, n, c, ts, ts]
  );
  return { id, label: `${c} ${n}`.trim() };
}

/**
 * Aggiunge una persona a partire da un testo "Cognome Nome".
 * Il primo token diventa cognome, il resto nome.
 */
export async function addPersonaFromText(text: string): Promise<LookupItem> {
  const parts = text.trim().split(/\s+/);
  const cognome = parts.shift() ?? '';
  const nome = parts.join(' ');
  return addPersona(cognome, nome);
}

export async function deletePersona(id: string): Promise<void> {
  const db = await getDb();
  await db.runAsync('DELETE FROM persone WHERE id = ?', [id]);
}

// ---------------------------------------------------------------------------
// LOOKUP: OSPEDALI
// ---------------------------------------------------------------------------

export async function getOspedali(): Promise<Ospedale[]> {
  const db = await getDb();
  return db.getAllAsync<Ospedale>('SELECT * FROM ospedali ORDER BY nome COLLATE NOCASE');
}

export async function getOspedaliLookup(): Promise<LookupItem[]> {
  const rows = await getOspedali();
  return rows.map((r) => ({ id: r.id, label: r.nome }));
}

export async function addOspedale(nome: string, citta?: string): Promise<LookupItem> {
  const db = await getDb();
  const trimmed = nome.trim();
  const existing = await db.getFirstAsync<Ospedale>(
    'SELECT * FROM ospedali WHERE nome = ? COLLATE NOCASE',
    [trimmed]
  );
  if (existing) return { id: existing.id, label: existing.nome };
  const id = uuidv4();
  const ts = nowISO();
  await db.runAsync(
    'INSERT INTO ospedali (id, nome, citta, created_at, updated_at, is_synced) VALUES (?, ?, ?, ?, ?, 0)',
    [id, trimmed, citta?.trim() ?? null, ts, ts]
  );
  return { id, label: trimmed };
}

export async function deleteOspedale(id: string): Promise<void> {
  const db = await getDb();
  await db.runAsync('DELETE FROM ospedali WHERE id = ?', [id]);
}

// ---------------------------------------------------------------------------
// LOOKUP: TIPOLOGIE TURNO / ASSISTENZA
// ---------------------------------------------------------------------------

export async function getTipologieTurno(): Promise<Tipologia[]> {
  const db = await getDb();
  return db.getAllAsync<Tipologia>('SELECT * FROM tipologie_turno ORDER BY nome COLLATE NOCASE');
}

export async function getTipologieTurnoLookup(): Promise<LookupItem[]> {
  const rows = await getTipologieTurno();
  return rows.map((r) => ({ id: r.id, label: r.nome }));
}

export async function addTipologiaTurno(nome: string): Promise<LookupItem> {
  const db = await getDb();
  const trimmed = nome.trim();
  const existing = await db.getFirstAsync<Tipologia>(
    'SELECT * FROM tipologie_turno WHERE nome = ? COLLATE NOCASE',
    [trimmed]
  );
  if (existing) return { id: existing.id, label: existing.nome };
  const id = uuidv4();
  const ts = nowISO();
  await db.runAsync(
    'INSERT INTO tipologie_turno (id, nome, created_at, updated_at, is_synced) VALUES (?, ?, ?, ?, 0)',
    [id, trimmed, ts, ts]
  );
  return { id, label: trimmed };
}

export async function getTipologieAssistenza(): Promise<Tipologia[]> {
  const db = await getDb();
  return db.getAllAsync<Tipologia>(
    'SELECT * FROM tipologie_assistenza ORDER BY nome COLLATE NOCASE'
  );
}

export async function addTipologiaAssistenza(nome: string): Promise<LookupItem> {
  const db = await getDb();
  const trimmed = nome.trim();
  const existing = await db.getFirstAsync<Tipologia>(
    'SELECT * FROM tipologie_assistenza WHERE nome = ? COLLATE NOCASE',
    [trimmed]
  );
  if (existing) return { id: existing.id, label: existing.nome };
  const id = uuidv4();
  const ts = nowISO();
  await db.runAsync(
    'INSERT INTO tipologie_assistenza (id, nome, created_at, updated_at, is_synced) VALUES (?, ?, ?, ?, 0)',
    [id, trimmed, ts, ts]
  );
  return { id, label: trimmed };
}

// ---------------------------------------------------------------------------
// PROGRESSIVI
// ---------------------------------------------------------------------------

export async function getNextProgressivoTurno(associazioneId: string | null): Promise<number> {
  if (!associazioneId) return 1;
  const db = await getDb();
  const row = await db.getFirstAsync<{ c: number }>(
    'SELECT COUNT(*) AS c FROM turni WHERE associazione_id = ?',
    [associazioneId]
  );
  return (row?.c ?? 0) + 1;
}

export async function getNextProgressivoAssistenza(
  associazioneId: string | null
): Promise<number> {
  if (!associazioneId) return 1;
  const db = await getDb();
  const row = await db.getFirstAsync<{ c: number }>(
    'SELECT COUNT(*) AS c FROM assistenze WHERE associazione_id = ?',
    [associazioneId]
  );
  return (row?.c ?? 0) + 1;
}

// ---------------------------------------------------------------------------
// TURNI
// ---------------------------------------------------------------------------

export async function getTurni(): Promise<TurnoRow[]> {
  const db = await getDb();
  return db.getAllAsync<TurnoRow>(`
    SELECT t.*, a.nome AS associazione_nome, tt.nome AS tipologia_nome
    FROM turni t
    LEFT JOIN associazioni a ON a.id = t.associazione_id
    LEFT JOIN tipologie_turno tt ON tt.id = t.tipologia_id
    ORDER BY t.data DESC, t.created_at DESC
  `);
}

export async function getTurnoById(id: string): Promise<TurnoRow | null> {
  const db = await getDb();
  const row = await db.getFirstAsync<TurnoRow>(
    `SELECT t.*, a.nome AS associazione_nome, tt.nome AS tipologia_nome
     FROM turni t
     LEFT JOIN associazioni a ON a.id = t.associazione_id
     LEFT JOIN tipologie_turno tt ON tt.id = t.tipologia_id
     WHERE t.id = ?`,
    [id]
  );
  return row ?? null;
}

/** Inserisce o aggiorna un turno. Restituisce l'id del turno. */
export async function saveTurno(input: TurnoInput): Promise<string> {
  const db = await getDb();
  const ts = nowISO();
  const extraJson = JSON.stringify(input.tipologie_extra ?? []);

  const existing = input.id
    ? await db.getFirstAsync<Turno>('SELECT * FROM turni WHERE id = ?', [input.id])
    : null;

  if (existing) {
    await db.runAsync(
      `UPDATE turni SET
        associazione_id = ?, data = ?, ore = ?, tipologia_id = ?, tipologie_extra = ?,
        descrizione = ?, note = ?,
        eq1_autista_id = ?, eq1_cs_id = ?, eq1_terzo_id = ?, eq1_quarto_id = ?, eq1_centralinista_id = ?,
        eq2_autista_id = ?, eq2_cs_id = ?, eq2_terzo_id = ?, eq2_quarto_id = ?, eq2_centralinista_id = ?,
        updated_at = ?, is_synced = 0
      WHERE id = ?`,
      [
        input.associazione_id,
        input.data,
        input.ore,
        input.tipologia_id,
        extraJson,
        input.descrizione,
        input.note,
        input.eq1_autista_id,
        input.eq1_cs_id,
        input.eq1_terzo_id,
        input.eq1_quarto_id,
        input.eq1_centralinista_id,
        input.eq2_autista_id,
        input.eq2_cs_id,
        input.eq2_terzo_id,
        input.eq2_quarto_id,
        input.eq2_centralinista_id,
        ts,
        existing.id,
      ]
    );
    return existing.id;
  }

  const id = input.id ?? uuidv4();
  const progressivo = await getNextProgressivoTurno(input.associazione_id);
  await db.runAsync(
    `INSERT INTO turni (
      id, associazione_id, numero_progressivo, data, ore, tipologia_id, tipologie_extra,
      num_servizi, descrizione, note,
      eq1_autista_id, eq1_cs_id, eq1_terzo_id, eq1_quarto_id, eq1_centralinista_id,
      eq2_autista_id, eq2_cs_id, eq2_terzo_id, eq2_quarto_id, eq2_centralinista_id,
      created_at, updated_at, is_synced
    ) VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)`,
    [
      id,
      input.associazione_id,
      progressivo,
      input.data,
      input.ore,
      input.tipologia_id,
      extraJson,
      input.descrizione,
      input.note,
      input.eq1_autista_id,
      input.eq1_cs_id,
      input.eq1_terzo_id,
      input.eq1_quarto_id,
      input.eq1_centralinista_id,
      input.eq2_autista_id,
      input.eq2_cs_id,
      input.eq2_terzo_id,
      input.eq2_quarto_id,
      input.eq2_centralinista_id,
      ts,
      ts,
    ]
  );
  return id;
}

export async function deleteTurno(id: string): Promise<void> {
  const db = await getDb();
  await db.runAsync('DELETE FROM turni WHERE id = ?', [id]);
}

// ---------------------------------------------------------------------------
// SERVIZI
// ---------------------------------------------------------------------------

export async function getServiziByTurno(turnoId: string): Promise<ServizioRow[]> {
  const db = await getDb();
  return db.getAllAsync<ServizioRow>(
    `SELECT s.*, o.nome AS ospedale_nome
     FROM servizi s
     LEFT JOIN ospedali o ON o.id = s.ospedale_id
     WHERE s.turno_id = ?
     ORDER BY s.created_at ASC`,
    [turnoId]
  );
}

/** Ricalcola e salva il numero di servizi del turno. */
export async function updateNumServizi(turnoId: string): Promise<number> {
  const db = await getDb();
  const row = await db.getFirstAsync<{ c: number }>(
    'SELECT COUNT(*) AS c FROM servizi WHERE turno_id = ?',
    [turnoId]
  );
  const count = row?.c ?? 0;
  await db.runAsync('UPDATE turni SET num_servizi = ?, updated_at = ?, is_synced = 0 WHERE id = ?', [
    count,
    nowISO(),
    turnoId,
  ]);
  return count;
}

export async function addServizio(
  turnoId: string,
  codiceChiamata: CodiceChiamata,
  codiceUscita: CodiceUscita,
  ospedaleId: string | null
): Promise<string> {
  const db = await getDb();
  const id = uuidv4();
  const ts = nowISO();
  await db.runAsync(
    `INSERT INTO servizi (id, turno_id, codice_chiamata, codice_uscita, ospedale_id, created_at, updated_at, is_synced)
     VALUES (?, ?, ?, ?, ?, ?, ?, 0)`,
    [id, turnoId, codiceChiamata, codiceUscita, ospedaleId, ts, ts]
  );
  await updateNumServizi(turnoId);
  return id;
}

export async function deleteServizio(id: string, turnoId: string): Promise<void> {
  const db = await getDb();
  await db.runAsync('DELETE FROM servizi WHERE id = ?', [id]);
  await updateNumServizi(turnoId);
}

// ---------------------------------------------------------------------------
// ASSISTENZE
// ---------------------------------------------------------------------------

export async function getAssistenze(): Promise<AssistenzaRow[]> {
  const db = await getDb();
  return db.getAllAsync<AssistenzaRow>(`
    SELECT a.*, ass.nome AS associazione_nome
    FROM assistenze a
    LEFT JOIN associazioni ass ON ass.id = a.associazione_id
    ORDER BY a.data DESC, a.created_at DESC
  `);
}

export async function getAssistenzaById(id: string): Promise<AssistenzaRow | null> {
  const db = await getDb();
  const row = await db.getFirstAsync<AssistenzaRow>(
    `SELECT a.*, ass.nome AS associazione_nome
     FROM assistenze a
     LEFT JOIN associazioni ass ON ass.id = a.associazione_id
     WHERE a.id = ?`,
    [id]
  );
  return row ?? null;
}

export async function saveAssistenza(input: AssistenzaInput): Promise<string> {
  const db = await getDb();
  const ts = nowISO();

  const existing = input.id
    ? await db.getFirstAsync<Assistenza>('SELECT * FROM assistenze WHERE id = ?', [input.id])
    : null;

  if (existing) {
    await db.runAsync(
      `UPDATE assistenze SET
        associazione_id = ?, data = ?, ore = ?, descrizione = ?, note = ?,
        eq1_autista_id = ?, eq1_cs_id = ?, eq1_terzo_id = ?, eq1_quarto_id = ?, eq1_centralinista_id = ?,
        eq2_autista_id = ?, eq2_cs_id = ?, eq2_terzo_id = ?, eq2_quarto_id = ?, eq2_centralinista_id = ?,
        updated_at = ?, is_synced = 0
      WHERE id = ?`,
      [
        input.associazione_id,
        input.data,
        input.ore,
        input.descrizione,
        input.note,
        input.eq1_autista_id,
        input.eq1_cs_id,
        input.eq1_terzo_id,
        input.eq1_quarto_id,
        input.eq1_centralinista_id,
        input.eq2_autista_id,
        input.eq2_cs_id,
        input.eq2_terzo_id,
        input.eq2_quarto_id,
        input.eq2_centralinista_id,
        ts,
        existing.id,
      ]
    );
    return existing.id;
  }

  const id = input.id ?? uuidv4();
  const progressivo = await getNextProgressivoAssistenza(input.associazione_id);
  await db.runAsync(
    `INSERT INTO assistenze (
      id, associazione_id, numero_progressivo, data, ore, descrizione, note,
      eq1_autista_id, eq1_cs_id, eq1_terzo_id, eq1_quarto_id, eq1_centralinista_id,
      eq2_autista_id, eq2_cs_id, eq2_terzo_id, eq2_quarto_id, eq2_centralinista_id,
      created_at, updated_at, is_synced
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)`,
    [
      id,
      input.associazione_id,
      progressivo,
      input.data,
      input.ore,
      input.descrizione,
      input.note,
      input.eq1_autista_id,
      input.eq1_cs_id,
      input.eq1_terzo_id,
      input.eq1_quarto_id,
      input.eq1_centralinista_id,
      input.eq2_autista_id,
      input.eq2_cs_id,
      input.eq2_terzo_id,
      input.eq2_quarto_id,
      input.eq2_centralinista_id,
      ts,
      ts,
    ]
  );
  return id;
}

export async function deleteAssistenza(id: string): Promise<void> {
  const db = await getDb();
  await db.runAsync('DELETE FROM assistenze WHERE id = ?', [id]);
}
