package main

import (
	"context"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// OspedaleInput è il formato di una riga in ingresso per l'import massivo
// (POST /api/ospedali/import): stesso nome/via/citta/lat/lng/regione usato in
// esportOspedali/importOspedali lato client (db/backup.dart) — un file
// esportato dall'app si importa qui senza alcuna trasformazione.
type OspedaleInput struct {
	Nome    string   `json:"nome"`
	Via     *string  `json:"via"`
	Citta   *string  `json:"citta"`
	Lat     *float64 `json:"lat"`
	Lng     *float64 `json:"lng"`
	Regione *string  `json:"regione"`
}

// Ospedale rispecchia il formato nome/via/citta/lat/lng/regione già usato
// dall'export/import JSON dell'app Flutter (db/backup.dart): i client
// possono fare l'upsert per nome sulla risposta di GET /ospedali senza
// alcuna trasformazione.
type Ospedale struct {
	ID        string    `json:"id"`
	Nome      string    `json:"nome"`
	Via       *string   `json:"via"`
	Citta     *string   `json:"citta"`
	Lat       *float64  `json:"lat"`
	Lng       *float64  `json:"lng"`
	Regione   *string   `json:"regione"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

const colonneOspedale = "id, nome, via, citta, lat, lng, regione, created_at, updated_at"

// listOspedali restituisce l'elenco, filtrato (case-insensitive, match
// esatto) per città se [citta] non è vuota, altrimenti per regione se
// [regione] non è vuota; se entrambe sono vuote restituisce tutto.
// Città ha priorità su regione se per errore fossero passate insieme (un
// filtro più specifico che uno più ampio, non c'è un caso d'uso per l'AND).
func listOspedali(ctx context.Context, pool *pgxpool.Pool, citta, regione string) ([]Ospedale, error) {
	query := "SELECT " + colonneOspedale + " FROM ospedali ORDER BY citta ASC NULLS LAST, nome ASC"
	args := []any{}
	switch {
	case citta != "":
		query = "SELECT " + colonneOspedale + " FROM ospedali WHERE lower(citta) = lower($1) ORDER BY nome ASC"
		args = append(args, citta)
	case regione != "":
		query = "SELECT " + colonneOspedale + " FROM ospedali WHERE lower(regione) = lower($1) ORDER BY citta ASC NULLS LAST, nome ASC"
		args = append(args, regione)
	}
	rows, err := pool.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	lista := []Ospedale{}
	for rows.Next() {
		var o Ospedale
		if err := rows.Scan(&o.ID, &o.Nome, &o.Via, &o.Citta, &o.Lat, &o.Lng, &o.Regione, &o.CreatedAt, &o.UpdatedAt); err != nil {
			return nil, err
		}
		lista = append(lista, o)
	}
	return lista, rows.Err()
}

// listCitta restituisce le città distinte che hanno almeno un ospedale,
// ordinate alfabeticamente: il client la usa per mostrare un elenco
// selezionabile invece di far digitare alla cieca un nome città.
// DISTINCT ON (lower(citta)) invece di un semplice DISTINCT: senza,
// "Milano" e "milano" inserite con maiuscole diverse comparirebbero come due
// voci — qui listOspedali(citta=...) le tratta già come la stessa città
// (match case-insensitive), l'elenco deve rispecchiarlo.
func listCitta(ctx context.Context, pool *pgxpool.Pool) ([]string, error) {
	rows, err := pool.Query(ctx,
		`SELECT DISTINCT ON (lower(citta)) citta FROM ospedali
		 WHERE citta IS NOT NULL AND citta <> ''
		 ORDER BY lower(citta), citta`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	citta := []string{}
	for rows.Next() {
		var c string
		if err := rows.Scan(&c); err != nil {
			return nil, err
		}
		citta = append(citta, c)
	}
	return citta, rows.Err()
}

// listRegioni: stessa logica di listCitta ma sulla colonna regione — usata
// dal client per raggruppare la lista ospedali per regione e per popolare
// l'elenco selezionabile di "Scarica ospedali per regione".
func listRegioni(ctx context.Context, pool *pgxpool.Pool) ([]string, error) {
	rows, err := pool.Query(ctx,
		`SELECT DISTINCT ON (lower(regione)) regione FROM ospedali
		 WHERE regione IS NOT NULL AND regione <> ''
		 ORDER BY lower(regione), regione`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	regioni := []string{}
	for rows.Next() {
		var r string
		if err := rows.Scan(&r); err != nil {
			return nil, err
		}
		regioni = append(regioni, r)
	}
	return regioni, rows.Err()
}

// createOspedale inserisce un ospedale e restituisce la riga creata.
func createOspedale(ctx context.Context, pool *pgxpool.Pool, nome string, via, citta, regione *string, lat, lng *float64) (Ospedale, error) {
	var o Ospedale
	err := pool.QueryRow(ctx,
		"INSERT INTO ospedali (id, nome, via, citta, lat, lng, regione) VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING "+colonneOspedale,
		uuid.NewString(), nome, via, citta, lat, lng, regione,
	).Scan(&o.ID, &o.Nome, &o.Via, &o.Citta, &o.Lat, &o.Lng, &o.Regione, &o.CreatedAt, &o.UpdatedAt)
	return o, err
}

// updateOspedale sostituisce tutti i campi di un ospedale esistente e
// restituisce la riga aggiornata. Se [id] non esiste restituisce
// pgx.ErrNoRows (RETURNING su un UPDATE che non tocca righe non produce
// risultati, Scan lo riporta così) — il chiamante lo traduce in 404.
func updateOspedale(ctx context.Context, pool *pgxpool.Pool, id, nome string, via, citta, regione *string, lat, lng *float64) (Ospedale, error) {
	var o Ospedale
	err := pool.QueryRow(ctx,
		`UPDATE ospedali SET nome=$1, via=$2, citta=$3, lat=$4, lng=$5, regione=$6, updated_at=now()
		 WHERE id=$7 RETURNING `+colonneOspedale,
		nome, via, citta, lat, lng, regione, id,
	).Scan(&o.ID, &o.Nome, &o.Via, &o.Citta, &o.Lat, &o.Lng, &o.Regione, &o.CreatedAt, &o.UpdatedAt)
	return o, err
}

// upsertOspedali importa in blocco una lista di ospedali, upsert per nome
// (un ospedale già presente con lo stesso nome viene aggiornato, uno nuovo
// viene creato) dentro un'unica transazione — stessa logica, stesso scopo
// (bulk import) della funzione omonima lato client in db/helpers.dart,
// usata dalla pagina admin per l'import da file. `nome` non ha un vincolo
// UNIQUE nello schema (deciso così per restare semplice, l'unico scrittore
// finora era createOspedale una riga alla volta): l'upsert si fa quindi con
// una SELECT preliminare + INSERT/UPDATE, non con INSERT ... ON CONFLICT.
func upsertOspedali(ctx context.Context, pool *pgxpool.Pool, righe []OspedaleInput) (creati, aggiornati, scartati int, err error) {
	tx, err := pool.Begin(ctx)
	if err != nil {
		return 0, 0, 0, err
	}
	defer tx.Rollback(ctx)

	esistenti := map[string]string{} // nome -> id
	rows, err := tx.Query(ctx, "SELECT id, nome FROM ospedali")
	if err != nil {
		return 0, 0, 0, err
	}
	for rows.Next() {
		var id, nome string
		if err := rows.Scan(&id, &nome); err != nil {
			rows.Close()
			return 0, 0, 0, err
		}
		esistenti[nome] = id
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return 0, 0, 0, err
	}

	for _, r := range righe {
		nome := strings.TrimSpace(r.Nome)
		if nome == "" {
			scartati++
			continue
		}
		if id, ok := esistenti[nome]; ok {
			if _, err = tx.Exec(ctx,
				"UPDATE ospedali SET via=$1, citta=$2, lat=$3, lng=$4, regione=$5, updated_at=now() WHERE id=$6",
				r.Via, r.Citta, r.Lat, r.Lng, r.Regione, id,
			); err != nil {
				return 0, 0, 0, err
			}
			aggiornati++
		} else {
			id := uuid.NewString()
			if _, err = tx.Exec(ctx,
				"INSERT INTO ospedali (id, nome, via, citta, lat, lng, regione) VALUES ($1,$2,$3,$4,$5,$6,$7)",
				id, nome, r.Via, r.Citta, r.Lat, r.Lng, r.Regione,
			); err != nil {
				return 0, 0, 0, err
			}
			esistenti[nome] = id
			creati++
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return 0, 0, 0, err
	}
	return creati, aggiornati, scartati, nil
}

// deleteOspedale rimuove un ospedale per id. true se una riga è stata rimossa.
func deleteOspedale(ctx context.Context, pool *pgxpool.Pool, id string) (bool, error) {
	tag, err := pool.Exec(ctx, "DELETE FROM ospedali WHERE id = $1", id)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() > 0, nil
}
