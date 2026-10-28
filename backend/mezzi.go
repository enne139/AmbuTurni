package main

import (
	"context"
	"regexp"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5/pgxpool"
)

// Mezzo: un'ambulanza dell'associazione, scelta nel selettore in alto del
// tool Materiali usati per sapere da quale mezzo è stato preso un
// materiale. Il nome è sempre un numero a due cifre (es. "07", "12"):
// richiesta esplicita dell'utente, validata qui invece di lasciarla al solo
// form della pagina admin — un "7" senza zero iniziale ordinerebbe male
// accanto a "12" e comparirebbe come un mezzo diverso da "07".
type Mezzo struct {
	ID        string    `json:"id"`
	Nome      string    `json:"nome"`
	CreatedAt time.Time `json:"created_at"`
}

// MezzoInput: riga del backup completo (solo il nome, l'id è interno).
type MezzoInput struct {
	Nome string `json:"nome"`
}

var reNomeMezzo = regexp.MustCompile(`^[0-9]{2}$`)

func nomeMezzoValido(nome string) bool {
	return reNomeMezzo.MatchString(nome)
}

// listMezzi: ordinati per nome — con due cifre fisse l'ordine alfabetico
// coincide con quello numerico, nessun cast necessario.
func listMezzi(ctx context.Context, pool *pgxpool.Pool) ([]Mezzo, error) {
	rows, err := pool.Query(ctx, "SELECT id, nome, created_at FROM mezzi ORDER BY nome ASC")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	lista := []Mezzo{}
	for rows.Next() {
		var m Mezzo
		if err := rows.Scan(&m.ID, &m.Nome, &m.CreatedAt); err != nil {
			return nil, err
		}
		lista = append(lista, m)
	}
	return lista, rows.Err()
}

// createMezzo: il chiamante ha già validato il nome. Un doppione fa fallire
// l'INSERT sul vincolo UNIQUE (a differenza di materiali/ospedali qui il
// vincolo c'è: tabella nuova, nessuno scrittore storico da rispettare) —
// l'handler lo traduce in un 409 leggibile.
func createMezzo(ctx context.Context, pool *pgxpool.Pool, nome string) (Mezzo, error) {
	var m Mezzo
	err := pool.QueryRow(ctx,
		"INSERT INTO mezzi (id, nome) VALUES ($1, $2) RETURNING id, nome, created_at",
		uuid.NewString(), nome,
	).Scan(&m.ID, &m.Nome, &m.CreatedAt)
	return m, err
}

func deleteMezzo(ctx context.Context, pool *pgxpool.Pool, id string) (bool, error) {
	tag, err := pool.Exec(ctx, "DELETE FROM mezzi WHERE id = $1", id)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() > 0, nil
}

// upsertMezzi: ripristino dal backup completo. Il nome è UNIQUE, quindi qui
// basta ON CONFLICT DO NOTHING — un mezzo ha solo il nome, non c'è altro da
// aggiornare. "aggiornati" conta i nomi già presenti, per un riepilogo
// coerente con le altre sezioni del ripristino.
func upsertMezzi(ctx context.Context, pool *pgxpool.Pool, righe []MezzoInput) (creati, aggiornati, scartati int, err error) {
	tx, err := pool.Begin(ctx)
	if err != nil {
		return 0, 0, 0, err
	}
	defer tx.Rollback(ctx)

	for _, r := range righe {
		nome := strings.TrimSpace(r.Nome)
		if !nomeMezzoValido(nome) {
			scartati++
			continue
		}
		tag, err := tx.Exec(ctx,
			"INSERT INTO mezzi (id, nome) VALUES ($1, $2) ON CONFLICT (nome) DO NOTHING",
			uuid.NewString(), nome)
		if err != nil {
			return 0, 0, 0, err
		}
		if tag.RowsAffected() > 0 {
			creati++
		} else {
			aggiornati++
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return 0, 0, 0, err
	}
	return creati, aggiornati, scartati, nil
}
