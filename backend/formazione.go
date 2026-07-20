package main

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// RepositoryFormazione è l'unico link condiviso ai materiali di formazione
// dell'associazione (es. una cartella Drive o un sito), aperto nel browser
// dal tool "Repository formazione" lato client. Un solo valore per tutta
// l'istanza, non una collezione come ospedali/fogli/materiali: non serve
// altro che "qual è il link attuale" e "quando è stato aggiornato l'ultima
// volta" — stesso schema di fiducia (lettura pubblica, scrittura solo
// admin) delle altre risorse condivise.
type RepositoryFormazione struct {
	Url       string    `json:"url"`
	UpdatedAt time.Time `json:"updated_at"`
}

// getRepositoryFormazione restituisce il link salvato, o un valore vuoto
// (Url == "") se non è mai stato impostato — non è un errore, è uno stato
// legittimo prima che un admin lo configuri la prima volta.
func getRepositoryFormazione(ctx context.Context, pool *pgxpool.Pool) (RepositoryFormazione, error) {
	var r RepositoryFormazione
	err := pool.QueryRow(ctx, "SELECT url, updated_at FROM repository_formazione WHERE id = 1").
		Scan(&r.Url, &r.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return RepositoryFormazione{}, nil
	}
	return r, err
}

// setRepositoryFormazione imposta o aggiorna l'unico link (upsert sulla
// riga singleton id=1, vedi CHECK in initSchema).
func setRepositoryFormazione(ctx context.Context, pool *pgxpool.Pool, url string) (RepositoryFormazione, error) {
	var r RepositoryFormazione
	err := pool.QueryRow(ctx,
		`INSERT INTO repository_formazione (id, url) VALUES (1, $1)
		 ON CONFLICT (id) DO UPDATE SET url = $1, updated_at = now()
		 RETURNING url, updated_at`,
		url,
	).Scan(&r.Url, &r.UpdatedAt)
	return r, err
}
