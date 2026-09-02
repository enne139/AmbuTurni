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
//   - ospedali: elenco condiviso ospedali (nome, via, città, coordinate,
//     regione), lo stesso formato usato dall'export/import JSON dell'app
//     Flutter — i client lo scaricano filtrato per città o per regione.
//   - fogli_turni: link ai fogli Google Sheets del piano turni mensile,
//     salvati sul backend così ogni client configurato su questa istanza può
//     scaricarli automaticamente invece di doverli conoscere a mano (vedi
//     CLAUDE.md, tool Piano turni).
//   - materiali: catalogo condiviso dei nomi materiali (Tools → Materiali
//     usati), scaricabile per popolare il catalogo locale su un device nuovo.
//   - repository_formazione: un solo link condiviso (non una collezione) ai
//     materiali di formazione dell'associazione, aperto nel browser dal
//     tool "Repository formazione". Riga singola forzata dal CHECK (id = 1).
//   - utenti_app: account (creati SOLO dalla pagina admin) che sbloccano i
//     contenuti riservati dell'app — Repository formazione e Comunicati.
//     Tabella separata da `users` apposta: un account-contenuto non deve
//     mai poter transitare per i controlli riservati agli admin. Vedi
//     auth.go (Role nei JWT) e utenti_app.go.
//   - comunicati: avvisi dell'associazione con un PDF allegato (tool
//     "Archivio comunicati", contenuto riservato: richiede login). Il PDF
//     vive dentro Postgres (file_data bytea), non su disco — nessun volume
//     dedicato da aggiungere al deploy, stesso volume `pgdata` già
//     persistito (scelta discussa con l'utente, vedi CLAUDE.md). Nessun
//     titolo/descrizione: il nome del file è ciò che viene mostrato in
//     app, i comunicati reali sono già nominati con una convenzione propria
//     (AAAAMMGG_NUMERO_...).
//
// `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` invece di un vero sistema di
// migrazioni (assente qui, a differenza del client Flutter): un solo campo
// aggiunto a una tabella già esistente non giustifica la complessità, e
// Postgres supporta nativamente la forma idempotente.
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
		ALTER TABLE ospedali ADD COLUMN IF NOT EXISTS regione TEXT;

		CREATE INDEX IF NOT EXISTS idx_ospedali_citta ON ospedali (citta);
		CREATE INDEX IF NOT EXISTS idx_ospedali_regione ON ospedali (regione);

		CREATE TABLE IF NOT EXISTS fogli_turni (
			chiave TEXT PRIMARY KEY,
			url TEXT NOT NULL,
			created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
			updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
		);

		CREATE TABLE IF NOT EXISTS materiali (
			id TEXT PRIMARY KEY,
			nome TEXT NOT NULL,
			created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
			updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
		);

		CREATE TABLE IF NOT EXISTS repository_formazione (
			id INTEGER PRIMARY KEY DEFAULT 1,
			url TEXT NOT NULL,
			updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
			CHECK (id = 1)
		);

		CREATE TABLE IF NOT EXISTS utenti_app (
			username TEXT PRIMARY KEY,
			password_hash TEXT NOT NULL,
			deve_cambiare_password BOOLEAN NOT NULL DEFAULT true,
			created_at TIMESTAMPTZ NOT NULL DEFAULT now()
		);

		CREATE TABLE IF NOT EXISTS comunicati (
			id TEXT PRIMARY KEY,
			file_name TEXT NOT NULL,
			file_data BYTEA NOT NULL,
			file_size BIGINT NOT NULL,
			created_at TIMESTAMPTZ NOT NULL DEFAULT now()
		);
		-- titolo/descrizione erano nella primissima versione di questa
		-- tabella (mai arrivata in produzione, solo su istanze di sviluppo):
		-- tolti via DROP COLUMN IF EXISTS invece di una vera migrazione,
		-- stesso idioma "niente sistema di migrazioni qui" già in uso per
		-- ospedali.regione.
		ALTER TABLE comunicati DROP COLUMN IF EXISTS titolo;
		ALTER TABLE comunicati DROP COLUMN IF EXISTS descrizione;
	`)
	return err
}
