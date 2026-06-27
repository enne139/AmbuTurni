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

// Le interfacce seguenti rispecchiano 1:1 le righe delle tabelle definite in
// schema.ts. I tipi *Row estendono la riga con campi denormalizzati (JOIN) usati
// nelle liste/dettagli. I tipi *Input sono i dati editabili passati al salvataggio.

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

export type CodiceChiamata = 'VERDE' | 'GIALLO' | 'ROSSO' | 'DIMISSIONE';
export type CodiceUscita =
  | 'VERDE'
  | 'GIALLO'
  | 'ROSSO'
  | 'NERO'
  | 'VUOTO'
  | 'RIFIUTO';

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
  descrizione: string | null;
  ordine: number;
  created_at: string;
  updated_at: string;
  is_synced: number;
}

export interface ServizioRow extends Servizio {
  ospedale_nome: string | null;
  ospedale_citta: string | null;
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

/**
 * Registra un tombstone per un'eliminazione, così la sincronizzazione può
 * propagarla agli altri dispositivi. Va chiamata SOLO per cancellazioni "locali"
 * (azioni dell'utente), non quando si applica una cancellazione ricevuta in pull.
 */
async function recordDeletion(table: string, id: string): Promise<void> {
  const db = await getDb();
  await db.runAsync(
    `INSERT INTO deletions (table_name, id, updated_at, is_synced) VALUES (?, ?, ?, 0)
     ON CONFLICT(table_name, id) DO UPDATE SET updated_at = excluded.updated_at, is_synced = 0`,
    [table, id, nowISO()]
  );
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

export async function updateAssociazione(id: string, nome: string): Promise<void> {
  const db = await getDb();
  await db.runAsync(
    'UPDATE associazioni SET nome = ?, updated_at = ?, is_synced = 0 WHERE id = ?',
    [nome.trim(), nowISO(), id]
  );
}

export async function deleteAssociazione(id: string): Promise<void> {
  const db = await getDb();
  await db.runAsync('DELETE FROM associazioni WHERE id = ?', [id]);
  await recordDeletion('associazioni', id);
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

export async function updatePersona(id: string, cognome: string, nome: string): Promise<void> {
  const db = await getDb();
  await db.runAsync(
    'UPDATE persone SET cognome = ?, nome = ?, updated_at = ?, is_synced = 0 WHERE id = ?',
    [cognome.trim(), nome.trim(), nowISO(), id]
  );
}

export async function deletePersona(id: string): Promise<void> {
  const db = await getDb();
  await db.runAsync('DELETE FROM persone WHERE id = ?', [id]);
  await recordDeletion('persone', id);
}

// ---------------------------------------------------------------------------
// LOOKUP: OSPEDALI
// ---------------------------------------------------------------------------

export async function getOspedali(): Promise<Ospedale[]> {
  const db = await getDb();
  return db.getAllAsync<Ospedale>('SELECT * FROM ospedali ORDER BY nome COLLATE NOCASE');
}

/** Etichetta "Nome — Città" (o solo Nome se manca la città). */
export function ospedaleLabel(nome: string, citta?: string | null): string {
  return citta && citta.trim() ? `${nome} — ${citta}` : nome;
}

export async function getOspedaliLookup(): Promise<LookupItem[]> {
  const rows = await getOspedali();
  return rows.map((r) => ({ id: r.id, label: ospedaleLabel(r.nome, r.citta) }));
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

export async function updateOspedale(id: string, nome: string, citta?: string): Promise<void> {
  const db = await getDb();
  await db.runAsync(
    'UPDATE ospedali SET nome = ?, citta = ?, updated_at = ?, is_synced = 0 WHERE id = ?',
    [nome.trim(), citta?.trim() ?? null, nowISO(), id]
  );
}

export async function deleteOspedale(id: string): Promise<void> {
  const db = await getDb();
  await db.runAsync('DELETE FROM ospedali WHERE id = ?', [id]);
  await recordDeletion('ospedali', id);
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

export async function updateTipologiaTurno(id: string, nome: string): Promise<void> {
  const db = await getDb();
  await db.runAsync(
    'UPDATE tipologie_turno SET nome = ?, updated_at = ?, is_synced = 0 WHERE id = ?',
    [nome.trim(), nowISO(), id]
  );
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
//
// Il numero progressivo è il RANGO per data (crescente) all'interno
// dell'associazione: il turno/assistenza più vecchio è #1. Viene ricalcolato
// automaticamente a ogni inserimento, modifica o eliminazione, così resta
// sempre corretto anche dopo cancellazioni o cambi di data.
// ---------------------------------------------------------------------------

/** Anteprima del numero che avrebbe un turno con la data indicata (1-based). */
export async function previewProgressivoTurno(
  associazioneId: string | null,
  data: string
): Promise<number> {
  if (!associazioneId) return 1;
  const db = await getDb();
  const row = await db.getFirstAsync<{ c: number }>(
    'SELECT COUNT(*) AS c FROM turni WHERE associazione_id = ? AND data < ?',
    [associazioneId, data]
  );
  return (row?.c ?? 0) + 1;
}

/** Anteprima del numero che avrebbe un'assistenza con la data indicata. */
export async function previewProgressivoAssistenza(
  associazioneId: string | null,
  data: string
): Promise<number> {
  if (!associazioneId) return 1;
  const db = await getDb();
  const row = await db.getFirstAsync<{ c: number }>(
    'SELECT COUNT(*) AS c FROM assistenze WHERE associazione_id = ? AND data < ?',
    [associazioneId, data]
  );
  return (row?.c ?? 0) + 1;
}

/** Riassegna numero_progressivo a tutti i turni: rango per data nell'associazione. */
async function recomputeProgressiviTurni(): Promise<void> {
  const db = await getDb();
  await db.runAsync(
    `UPDATE turni SET numero_progressivo = (
       SELECT COUNT(*) FROM turni t2
       WHERE t2.associazione_id = turni.associazione_id
         AND (t2.data < turni.data
              OR (t2.data = turni.data AND t2.created_at <= turni.created_at))
     )
     WHERE associazione_id IS NOT NULL`,
    []
  );
}

/** Riassegna numero_progressivo a tutte le assistenze: rango per data nell'associazione. */
async function recomputeProgressiviAssistenze(): Promise<void> {
  const db = await getDb();
  await db.runAsync(
    `UPDATE assistenze SET numero_progressivo = (
       SELECT COUNT(*) FROM assistenze a2
       WHERE a2.associazione_id = assistenze.associazione_id
         AND (a2.data < assistenze.data
              OR (a2.data = assistenze.data AND a2.created_at <= assistenze.created_at))
     )
     WHERE associazione_id IS NOT NULL`,
    []
  );
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
    await recomputeProgressiviTurni();
    return existing.id;
  }

  const id = input.id ?? uuidv4();
  await db.runAsync(
    `INSERT INTO turni (
      id, associazione_id, numero_progressivo, data, ore, tipologia_id, tipologie_extra,
      num_servizi, descrizione, note,
      eq1_autista_id, eq1_cs_id, eq1_terzo_id, eq1_quarto_id, eq1_centralinista_id,
      eq2_autista_id, eq2_cs_id, eq2_terzo_id, eq2_quarto_id, eq2_centralinista_id,
      created_at, updated_at, is_synced
    ) VALUES (?, ?, 0, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)`,
    [
      id,
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
      ts,
    ]
  );
  await recomputeProgressiviTurni();
  return id;
}

export async function deleteTurno(id: string): Promise<void> {
  const db = await getDb();
  // I servizi figli vengono rimossi in cascata: registriamo un tombstone anche per
  // ciascuno di essi, altrimenti resterebbero sul server e tornerebbero col pull.
  const figli = await db.getAllAsync<{ id: string }>(
    'SELECT id FROM servizi WHERE turno_id = ?',
    [id]
  );
  await db.runAsync('DELETE FROM turni WHERE id = ?', [id]);
  for (const s of figli) await recordDeletion('servizi', s.id);
  await recordDeletion('turni', id);
  await recomputeProgressiviTurni();
}

// ---------------------------------------------------------------------------
// SERVIZI
// ---------------------------------------------------------------------------

export async function getServiziByTurno(turnoId: string): Promise<ServizioRow[]> {
  const db = await getDb();
  return db.getAllAsync<ServizioRow>(
    `SELECT s.*, o.nome AS ospedale_nome, o.citta AS ospedale_citta
     FROM servizi s
     LEFT JOIN ospedali o ON o.id = s.ospedale_id
     WHERE s.turno_id = ?
     ORDER BY s.ordine ASC, s.created_at ASC`,
    [turnoId]
  );
}

/** Rinumera l'ordine dei servizi di un turno in 1..N (senza buchi). */
async function resequenceServizi(turnoId: string): Promise<void> {
  const db = await getDb();
  await db.runAsync(
    `UPDATE servizi SET ordine = (
       SELECT COUNT(*) FROM servizi s2
       WHERE s2.turno_id = servizi.turno_id
         AND (s2.ordine < servizi.ordine
              OR (s2.ordine = servizi.ordine AND s2.created_at <= servizi.created_at))
     )
     WHERE turno_id = ?`,
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
  ospedaleId: string | null,
  descrizione: string | null
): Promise<string> {
  const db = await getDb();
  const id = uuidv4();
  const ts = nowISO();
  const ordineRow = await db.getFirstAsync<{ n: number }>(
    'SELECT COALESCE(MAX(ordine), 0) + 1 AS n FROM servizi WHERE turno_id = ?',
    [turnoId]
  );
  const ordine = ordineRow?.n ?? 1;
  await db.runAsync(
    `INSERT INTO servizi (id, turno_id, codice_chiamata, codice_uscita, ospedale_id, descrizione, ordine, created_at, updated_at, is_synced)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0)`,
    [id, turnoId, codiceChiamata, codiceUscita, ospedaleId, descrizione, ordine, ts, ts]
  );
  await resequenceServizi(turnoId);
  await updateNumServizi(turnoId);
  return id;
}

/** Aggiorna i campi di un servizio esistente. */
export async function updateServizio(
  id: string,
  codiceChiamata: CodiceChiamata,
  codiceUscita: CodiceUscita,
  ospedaleId: string | null,
  descrizione: string | null
): Promise<void> {
  const db = await getDb();
  await db.runAsync(
    `UPDATE servizi SET codice_chiamata = ?, codice_uscita = ?, ospedale_id = ?, descrizione = ?,
       updated_at = ?, is_synced = 0
     WHERE id = ?`,
    [codiceChiamata, codiceUscita, ospedaleId, descrizione, nowISO(), id]
  );
}

/** Sposta un servizio su/giù scambiando il numero progressivo col vicino. */
export async function moveServizio(
  turnoId: string,
  id: string,
  direction: 'up' | 'down'
): Promise<void> {
  const db = await getDb();
  const rows = await getServiziByTurno(turnoId);
  const idx = rows.findIndex((r) => r.id === id);
  if (idx < 0) return;
  const swapIdx = direction === 'up' ? idx - 1 : idx + 1;
  if (swapIdx < 0 || swapIdx >= rows.length) return;

  const a = rows[idx];
  const b = rows[swapIdx];
  // Se per qualche motivo l'ordine coincide, forza valori distinti basati sulla posizione.
  const aOrdine = a.ordine === b.ordine ? idx + 1 : a.ordine;
  const bOrdine = a.ordine === b.ordine ? swapIdx + 1 : b.ordine;
  const ts = nowISO();
  await db.runAsync('UPDATE servizi SET ordine = ?, updated_at = ?, is_synced = 0 WHERE id = ?', [
    bOrdine,
    ts,
    a.id,
  ]);
  await db.runAsync('UPDATE servizi SET ordine = ?, updated_at = ?, is_synced = 0 WHERE id = ?', [
    aOrdine,
    ts,
    b.id,
  ]);
  await resequenceServizi(turnoId);
}

export async function deleteServizio(id: string, turnoId: string): Promise<void> {
  const db = await getDb();
  await db.runAsync('DELETE FROM servizi WHERE id = ?', [id]);
  await recordDeletion('servizi', id);
  await resequenceServizi(turnoId);
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
    await recomputeProgressiviAssistenze();
    return existing.id;
  }

  const id = input.id ?? uuidv4();
  await db.runAsync(
    `INSERT INTO assistenze (
      id, associazione_id, numero_progressivo, data, ore, descrizione, note,
      eq1_autista_id, eq1_cs_id, eq1_terzo_id, eq1_quarto_id, eq1_centralinista_id,
      eq2_autista_id, eq2_cs_id, eq2_terzo_id, eq2_quarto_id, eq2_centralinista_id,
      created_at, updated_at, is_synced
    ) VALUES (?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)`,
    [
      id,
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
      ts,
    ]
  );
  await recomputeProgressiviAssistenze();
  return id;
}

export async function deleteAssistenza(id: string): Promise<void> {
  const db = await getDb();
  await db.runAsync('DELETE FROM assistenze WHERE id = ?', [id]);
  await recordDeletion('assistenze', id);
  await recomputeProgressiviAssistenze();
}

// ---------------------------------------------------------------------------
// STATISTICHE
// ---------------------------------------------------------------------------

export interface Statistiche {
  turniTotali: number;
  serviziTotali: number;
  oreTurni: number;
  assistenzeTotali: number;
  oreAssistenze: number;
  oreTotali: number;
}

/**
 * Totali aggregati, opzionalmente filtrati per associazione (null = tutte).
 */
export async function getStatistiche(associazioneId: string | null): Promise<Statistiche> {
  const db = await getDb();
  const params: string[] = associazioneId ? [associazioneId] : [];

  const turniRow = await db.getFirstAsync<{ c: number; ore: number | null }>(
    `SELECT COUNT(*) AS c, COALESCE(SUM(ore), 0) AS ore FROM turni ${
      associazioneId ? 'WHERE associazione_id = ?' : ''
    }`,
    params
  );

  const serviziRow = await db.getFirstAsync<{ c: number }>(
    `SELECT COUNT(*) AS c FROM servizi s JOIN turni t ON t.id = s.turno_id ${
      associazioneId ? 'WHERE t.associazione_id = ?' : ''
    }`,
    params
  );

  const assistRow = await db.getFirstAsync<{ c: number; ore: number | null }>(
    `SELECT COUNT(*) AS c, COALESCE(SUM(ore), 0) AS ore FROM assistenze ${
      associazioneId ? 'WHERE associazione_id = ?' : ''
    }`,
    params
  );

  const oreTurni = turniRow?.ore ?? 0;
  const oreAssistenze = assistRow?.ore ?? 0;

  return {
    turniTotali: turniRow?.c ?? 0,
    serviziTotali: serviziRow?.c ?? 0,
    oreTurni,
    assistenzeTotali: assistRow?.c ?? 0,
    oreAssistenze,
    oreTotali: oreTurni + oreAssistenze,
  };
}
