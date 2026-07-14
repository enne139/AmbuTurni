package main

import (
	"context"
	"fmt"
	"os"

	"github.com/jackc/pgx/v5/pgxpool"
)

// connectDB apre il pool di connessioni a PostgreSQL. Usa DATABASE_URL
// (consigliato) oppure le variabili PG* standard, stesso fallback del
// backend precedente.
func connectDB(ctx context.Context) (*pgxpool.Pool, error) {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		dsn = fmt.Sprintf("postgres://%s:%s@%s:%s/%s",
			envOr("PGUSER", "ambulanza"),
			envOr("PGPASSWORD", "ambulanza"),
			envOr("PGHOST", "db"),
			envOr("PGPORT", "5432"),
			envOr("PGDATABASE", "ambulanza"),
		)
	}
	return pgxpool.New(ctx, dsn)
}

// initSchema crea le tabelle se non esistono.
//   - users: credenziali (password con hash bcrypt) per il login all'interfaccia admin.
//   - ospedali: elenco condiviso ospedali (nome, via, città, coordinate), lo
//     stesso formato nome/via/citta/lat/lng usato dall'export/import JSON
//     dell'app Flutter — i client lo scaricano filtrato per città.
func initSchema(ctx context.Context, pool *pgxpool.Pool) error {
	_, err := pool.Exec(ctx, `
		CREATE TABLE IF NOT EXISTS users (
			username TEXT PRIMARY KEY,
			password_hash TEXT NOT NULL,
			created_at TIMESTAMPTZ NOT NULL DEFAULT now()
		);

		CREATE TABLE IF NOT EXISTS ospedali (
			id TEXT PRIMARY KEY,
			nome TEXT NOT NULL,
			via TEXT,
			citta TEXT,
			lat DOUBLE PRECISION,
			lng DOUBLE PRECISION,
			created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
			updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
		);

		CREATE INDEX IF NOT EXISTS idx_ospedali_citta ON ospedali (citta);
	`)
	return err
}
