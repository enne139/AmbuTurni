package main

import (
	"bytes"
	"context"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ComunicatoMeta è la vista usata dall'elenco (app + pagina admin): MAI il
// contenuto del PDF, che appesantirebbe inutilmente la risposta — il
// download è un endpoint a parte (getComunicatoFile). Titolo/descrizione
// OPZIONALI (*string, NULL se non compilati): il nome del file resta ciò
// che si mostra di default in app (i comunicati reali dell'associazione
// sono già nominati con una convenzione propria, AAAAMMGG_NUMERO_...), ma
// l'utente ha chiesto di poterli aggiungere quando servono, dopo il
// caricamento — vedi updateComunicato.
type ComunicatoMeta struct {
	ID          string    `json:"id"`
	FileName    string    `json:"fileName"`
	FileSize    int64     `json:"fileSize"`
	CreatedAt   time.Time `json:"createdAt"`
	Titolo      *string   `json:"titolo"`
	Descrizione *string   `json:"descrizione"`
}

// listComunicati elenca i metadati di tutti i comunicati, dal più recente.
// Chiamata sia dall'app (tool "Archivio comunicati") sia dalla pagina admin.
func listComunicati(ctx context.Context, pool *pgxpool.Pool) ([]ComunicatoMeta, error) {
	rows, err := pool.Query(ctx,
		"SELECT id, file_name, file_size, created_at, titolo, descrizione FROM comunicati ORDER BY created_at DESC")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	lista := []ComunicatoMeta{}
	for rows.Next() {
		var c ComunicatoMeta
		if err := rows.Scan(&c.ID, &c.FileName, &c.FileSize, &c.CreatedAt, &c.Titolo, &c.Descrizione); err != nil {
			return nil, err
		}
		lista = append(lista, c)
	}
	return lista, rows.Err()
}

// getComunicatoFile restituisce nome file + contenuto binario di un
// comunicato per il download (app e pagina admin) — pgx.ErrNoRows se l'id
// non esiste.
func getComunicatoFile(ctx context.Context, pool *pgxpool.Pool, id string) (fileName string, data []byte, err error) {
	err = pool.QueryRow(ctx, "SELECT file_name, file_data FROM comunicati WHERE id = $1", id).Scan(&fileName, &data)
	return fileName, data, err
}

// createComunicato salva un nuovo comunicato, PDF incluso (dentro Postgres:
// vedi CLAUDE.md sulla scelta bytea invece di un volume su disco dedicato).
// Chiamata SOLO dalla pagina admin, una volta per ciascun file di un
// upload multiplo (vedi POST /api/comunicati in main.go) — titolo/
// descrizione restano NULL alla creazione, si aggiungono dopo con
// updateComunicato: chiedere anche quelli ad ogni file di un upload
// multiplo non avrebbe un'interfaccia sensata (quale titolo per quale file?).
func createComunicato(ctx context.Context, pool *pgxpool.Pool, fileName string, data []byte) (ComunicatoMeta, error) {
	var c ComunicatoMeta
	err := pool.QueryRow(ctx,
		`INSERT INTO comunicati (id, file_name, file_data, file_size)
		 VALUES ($1, $2, $3, $4)
		 RETURNING id, file_name, file_size, created_at, titolo, descrizione`,
		uuid.NewString(), fileName, data, len(data),
	).Scan(&c.ID, &c.FileName, &c.FileSize, &c.CreatedAt, &c.Titolo, &c.Descrizione)
	return c, err
}

// updateComunicato aggiorna SOLO titolo/descrizione — mai il file: per
// sostituirlo si elimina il comunicato e se ne carica uno nuovo, niente
// endpoint dedicato a un caso d'uso che non si è mai presentato. pgx.ErrNoRows
// se l'id non esiste (RETURNING su un UPDATE che non tocca righe non produce
// risultati), tradotto in 404 dal chiamante — stesso pattern di updateOspedale.
// I puntatori arrivano già normalizzati a nil per "vuoto" da chi chiama
// (pagina admin: `.value.trim() || null`), quindi qui non serve altra logica:
// un campo svuotato torna NULL, l'app ricade sul nome file.
func updateComunicato(ctx context.Context, pool *pgxpool.Pool, id string, titolo, descrizione *string) (ComunicatoMeta, error) {
	var c ComunicatoMeta
	err := pool.QueryRow(ctx,
		`UPDATE comunicati SET titolo=$1, descrizione=$2 WHERE id=$3
		 RETURNING id, file_name, file_size, created_at, titolo, descrizione`,
		titolo, descrizione, id,
	).Scan(&c.ID, &c.FileName, &c.FileSize, &c.CreatedAt, &c.Titolo, &c.Descrizione)
	return c, err
}

// ComunicatoBackup è la riga usata dal backup/ripristino completo
// (backup.go): include il PDF come byte grezzi — a differenza di
// ComunicatoMeta (mai il file, pensata per l'elenco) qui serve tutto per
// poter ricreare la riga identica su un'altra istanza. Nessun tag JSON: il
// backup vero è uno ZIP (data.json coi soli metadati + un file .pdf per
// comunicato, vedi backup.go), questo struct non viene mai serializzato
// direttamente — è solo il tipo di trasporto tra query DB e voci dello zip.
type ComunicatoBackup struct {
	ID          string
	FileName    string
	Titolo      *string
	Descrizione *string
	FileData    []byte
}

// listComunicatiConFile elenca tutti i comunicati CON il PDF — usata SOLO
// dal backup completo, mai dall'elenco normale (appesantirebbe
// inutilmente ogni GET /api/comunicati, vedi ComunicatoMeta).
func listComunicatiConFile(ctx context.Context, pool *pgxpool.Pool) ([]ComunicatoBackup, error) {
	rows, err := pool.Query(ctx,
		"SELECT id, file_name, titolo, descrizione, file_data FROM comunicati ORDER BY created_at DESC")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	lista := []ComunicatoBackup{}
	for rows.Next() {
		var c ComunicatoBackup
		if err := rows.Scan(&c.ID, &c.FileName, &c.Titolo, &c.Descrizione, &c.FileData); err != nil {
			return nil, err
		}
		lista = append(lista, c)
	}
	return lista, rows.Err()
}

// upsertComunicatiConFile ripristina i comunicati da un backup: upsert per
// id (non per nome file, che non ha un vincolo di unicità reale) — preserva
// gli stessi id del backup, utile per un ripristino identico su un'altra
// istanza. Righe senza PDF (voce comunicati/<id>.pdf mancante nello zip,
// FileData nil) o che non superano la stessa validazione "%PDF" già in uso
// per l'upload normale (POST /api/comunicati) vengono scartate.
func upsertComunicatiConFile(ctx context.Context, pool *pgxpool.Pool, righe []ComunicatoBackup) (creati, aggiornati, scartati int, err error) {
	tx, err := pool.Begin(ctx)
	if err != nil {
		return 0, 0, 0, err
	}
	defer tx.Rollback(ctx)

	esistenti := map[string]bool{}
	rows, err := tx.Query(ctx, "SELECT id FROM comunicati")
	if err != nil {
		return 0, 0, 0, err
	}
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			rows.Close()
			return 0, 0, 0, err
		}
		esistenti[id] = true
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return 0, 0, 0, err
	}

	for _, r := range righe {
		id := strings.TrimSpace(r.ID)
		fileName := strings.TrimSpace(r.FileName)
		if id == "" || fileName == "" || !bytes.HasPrefix(r.FileData, []byte("%PDF")) {
			scartati++
			continue
		}
		if esistenti[id] {
			if _, err = tx.Exec(ctx,
				"UPDATE comunicati SET file_name=$1, titolo=$2, descrizione=$3, file_data=$4, file_size=$5 WHERE id=$6",
				fileName, r.Titolo, r.Descrizione, r.FileData, len(r.FileData), id,
			); err != nil {
				return 0, 0, 0, err
			}
			aggiornati++
		} else {
			if _, err = tx.Exec(ctx,
				"INSERT INTO comunicati (id, file_name, file_data, file_size, titolo, descrizione) VALUES ($1,$2,$3,$4,$5,$6)",
				id, fileName, r.FileData, len(r.FileData), r.Titolo, r.Descrizione,
			); err != nil {
				return 0, 0, 0, err
			}
			esistenti[id] = true
			creati++
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return 0, 0, 0, err
	}
	return creati, aggiornati, scartati, nil
}

// deleteComunicato elimina un comunicato per id; restituisce false se non
// esisteva. Chiamata SOLO dalla pagina admin.
func deleteComunicato(ctx context.Context, pool *pgxpool.Pool, id string) (bool, error) {
	tag, err := pool.Exec(ctx, "DELETE FROM comunicati WHERE id = $1", id)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() > 0, nil
}
