package main

import (
	"context"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// FoglioTurni è un link al foglio Google Sheets del piano turni mensile di
// un'associazione (tool "Piano turni" lato client), identificato dalla
// stessa chiave "aaaa-mm" usata nell'archivio locale (kPrefPianoTurniFogli).
// Salvato sul backend così un client configurato su questa istanza scarica
// automaticamente i fogli invece di doverli conoscere/incollare a mano su
// ogni device — vedi CLAUDE.md per la scelta "scrittura solo da admin,
// lettura pubblica" (stesso schema di fiducia di /api/ospedali).
type FoglioTurni struct {
	Chiave    string    `json:"chiave"`
	Url       string    `json:"url"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// listFogli restituisce tutti i fogli salvati, dal più recente (chiave
// "aaaa-mm" ordina correttamente come stringa): stesso ordine con cui il
// client presenta il proprio archivio locale (_fogliOrdinati).
func listFogli(ctx context.Context, pool *pgxpool.Pool) ([]FoglioTurni, error) {
	rows, err := pool.Query(ctx,
		"SELECT chiave, url, created_at, updated_at FROM fogli_turni ORDER BY chiave DESC")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	lista := []FoglioTurni{}
	for rows.Next() {
		var f FoglioTurni
		if err := rows.Scan(&f.Chiave, &f.Url, &f.CreatedAt, &f.UpdatedAt); err != nil {
			return nil, err
		}
		lista = append(lista, f)
	}
	return lista, rows.Err()
}

// upsertFoglio inserisce o aggiorna il link per [chiave] (usata dalla pagina
// admin: un solo form, come per gli ospedali).
func upsertFoglio(ctx context.Context, pool *pgxpool.Pool, chiave, url string) (FoglioTurni, error) {
	var f FoglioTurni
	err := pool.QueryRow(ctx,
		`INSERT INTO fogli_turni (chiave, url) VALUES ($1, $2)
		 ON CONFLICT (chiave) DO UPDATE SET url = $2, updated_at = now()
		 RETURNING chiave, url, created_at, updated_at`,
		chiave, url,
	).Scan(&f.Chiave, &f.Url, &f.CreatedAt, &f.UpdatedAt)
	return f, err
}

// deleteFoglio rimuove un foglio per chiave. true se una riga è stata rimossa.
func deleteFoglio(ctx context.Context, pool *pgxpool.Pool, chiave string) (bool, error) {
	tag, err := pool.Exec(ctx, "DELETE FROM fogli_turni WHERE chiave = $1", chiave)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() > 0, nil
}
