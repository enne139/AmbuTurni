package main

import (
	"context"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// ComunicatoMeta è la vista usata dall'elenco (app + pagina admin): MAI il
// contenuto del PDF, che appesantirebbe inutilmente la risposta — il
// download è un endpoint a parte (getComunicatoFile). Nessun titolo/
// descrizione (richiesta esplicita dell'utente): il nome del file stesso è
// ciò che viene mostrato in app, i comunicati reali dell'associazione sono
// già nominati con una convenzione propria (AAAAMMGG_NUMERO_...), un
// titolo separato da compilare ad ogni caricamento sarebbe stato solo un
// campo in più senza reale valore aggiunto.
type ComunicatoMeta struct {
	ID        string    `json:"id"`
	FileName  string    `json:"fileName"`
	FileSize  int64     `json:"fileSize"`
	CreatedAt time.Time `json:"createdAt"`
}

// listComunicati elenca i metadati di tutti i comunicati, dal più recente.
// Chiamata sia dall'app (tool "Archivio comunicati") sia dalla pagina admin.
func listComunicati(ctx context.Context, pool *pgxpool.Pool) ([]ComunicatoMeta, error) {
	rows, err := pool.Query(ctx,
		"SELECT id, file_name, file_size, created_at FROM comunicati ORDER BY created_at DESC")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	lista := []ComunicatoMeta{}
	for rows.Next() {
		var c ComunicatoMeta
		if err := rows.Scan(&c.ID, &c.FileName, &c.FileSize, &c.CreatedAt); err != nil {
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
// upload multiplo (vedi POST /api/comunicati in main.go).
func createComunicato(ctx context.Context, pool *pgxpool.Pool, fileName string, data []byte) (ComunicatoMeta, error) {
	var c ComunicatoMeta
	err := pool.QueryRow(ctx,
		`INSERT INTO comunicati (id, file_name, file_data, file_size)
		 VALUES ($1, $2, $3, $4)
		 RETURNING id, file_name, file_size, created_at`,
		uuid.NewString(), fileName, data, len(data),
	).Scan(&c.ID, &c.FileName, &c.FileSize, &c.CreatedAt)
	return c, err
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
