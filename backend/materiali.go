package main

import (
	"context"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// MaterialeInput/Materiale rispecchiano il catalogo materiali locale
// dell'app (tabella `materiali`, Tools → Materiali usati): qui solo il nome,
// nessuna quantità/posizione — quelle sono per-device (utilizzi attivi), il
// backend condivide solo l'elenco dei nomi per popolare il catalogo di un
// device nuovo, stesso scopo di /api/ospedali per l'anagrafica ospedali.
type MaterialeInput struct {
	Nome string `json:"nome"`
}

type Materiale struct {
	ID        string    `json:"id"`
	Nome      string    `json:"nome"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

func listMateriali(ctx context.Context, pool *pgxpool.Pool) ([]Materiale, error) {
	rows, err := pool.Query(ctx,
		"SELECT id, nome, created_at, updated_at FROM materiali ORDER BY nome ASC")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	lista := []Materiale{}
	for rows.Next() {
		var m Materiale
		if err := rows.Scan(&m.ID, &m.Nome, &m.CreatedAt, &m.UpdatedAt); err != nil {
			return nil, err
		}
		lista = append(lista, m)
	}
	return lista, rows.Err()
}

func createMateriale(ctx context.Context, pool *pgxpool.Pool, nome string) (Materiale, error) {
	var m Materiale
	err := pool.QueryRow(ctx,
		"INSERT INTO materiali (id, nome) VALUES ($1, $2) RETURNING id, nome, created_at, updated_at",
		uuid.NewString(), nome,
	).Scan(&m.ID, &m.Nome, &m.CreatedAt, &m.UpdatedAt)
	return m, err
}

func updateMateriale(ctx context.Context, pool *pgxpool.Pool, id, nome string) (Materiale, error) {
	var m Materiale
	err := pool.QueryRow(ctx,
		`UPDATE materiali SET nome = $1, updated_at = now() WHERE id = $2
		 RETURNING id, nome, created_at, updated_at`,
		nome, id,
	).Scan(&m.ID, &m.Nome, &m.CreatedAt, &m.UpdatedAt)
	return m, err
}

func deleteMateriale(ctx context.Context, pool *pgxpool.Pool, id string) (bool, error) {
	tag, err := pool.Exec(ctx, "DELETE FROM materiali WHERE id = $1", id)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() > 0, nil
}

// upsertMateriali: stessa logica di upsertOspedali (bulk import da file
// nella pagina admin), upsert per nome dentro un'unica transazione — `nome`
// non ha UNIQUE nello schema per lo stesso motivo (unico scrittore singolo
// finora), quindi SELECT preliminare + INSERT/UPDATE invece di ON CONFLICT.
func upsertMateriali(ctx context.Context, pool *pgxpool.Pool, righe []MaterialeInput) (creati, aggiornati, scartati int, err error) {
	tx, err := pool.Begin(ctx)
	if err != nil {
		return 0, 0, 0, err
	}
	defer tx.Rollback(ctx)

	esistenti := map[string]string{} // nome -> id
	rows, err := tx.Query(ctx, "SELECT id, nome FROM materiali")
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
			if _, err = tx.Exec(ctx, "UPDATE materiali SET updated_at = now() WHERE id = $1", id); err != nil {
				return 0, 0, 0, err
			}
			aggiornati++
		} else {
			id := uuid.NewString()
			if _, err = tx.Exec(ctx, "INSERT INTO materiali (id, nome) VALUES ($1, $2)", id, nome); err != nil {
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
