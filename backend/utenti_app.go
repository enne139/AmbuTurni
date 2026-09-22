package main

import (
	"context"
	"errors"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"
)

// UtenteAppInfo è la vista pubblica di un account utente-app (mai la
// password/hash) — usata dalla pagina admin per popolare la tabella
// "Utenti app". DeveCambiarePassword aiuta l'admin a vedere chi non ha
// ancora attivato l'account (password provvisoria mai cambiata).
type UtenteAppInfo struct {
	Username             string `json:"username"`
	CreatedAt            string `json:"createdAt"`
	DeveCambiarePassword bool   `json:"deveCambiarePassword"`
}

// errPasswordAttualeErrata distingue, nella risposta HTTP, "password attuale
// sbagliata" (colpa del chiamante, 400) da un vero errore interno (500).
var errPasswordAttualeErrata = errors.New("password attuale errata")

// createUtenteApp crea un account utente-app con una password provvisoria:
// deve_cambiare_password parte sempre true, l'app obbliga a impostarne una
// nuova al primo login (vedi cambiaPasswordUtenteApp). Chiamata SOLO dalla
// pagina admin (POST /api/utenti) — l'app Flutter non crea mai account,
// vedi CLAUDE.md.
func createUtenteApp(ctx context.Context, pool *pgxpool.Pool, username, password string) error {
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return err
	}
	_, err = pool.Exec(ctx,
		`INSERT INTO utenti_app (username, password_hash) VALUES ($1, $2)
		 ON CONFLICT (username) DO NOTHING`,
		username, string(hash))
	return err
}

// listUtentiApp elenca gli account utente-app, per la tabella della pagina
// admin. Chiamata SOLO da lì.
func listUtentiApp(ctx context.Context, pool *pgxpool.Pool) ([]UtenteAppInfo, error) {
	rows, err := pool.Query(ctx,
		"SELECT username, created_at, deve_cambiare_password FROM utenti_app ORDER BY username ASC")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	utenti := []UtenteAppInfo{}
	for rows.Next() {
		var u UtenteAppInfo
		var creato time.Time
		if err := rows.Scan(&u.Username, &creato, &u.DeveCambiarePassword); err != nil {
			return nil, err
		}
		u.CreatedAt = creato.UTC().Format(time.RFC3339)
		utenti = append(utenti, u)
	}
	return utenti, rows.Err()
}

// deleteUtenteApp elimina un account utente-app per username; restituisce
// false se non esisteva. A differenza di deleteUser (admin) nessun vincolo
// "non l'ultimo": zero utenti-app è uno stato legittimo, nessuna
// funzionalità dell'app ne dipende per esistere. Chiamata SOLO dalla pagina
// admin.
func deleteUtenteApp(ctx context.Context, pool *pgxpool.Pool, username string) (bool, error) {
	tag, err := pool.Exec(ctx, "DELETE FROM utenti_app WHERE username = $1", username)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() > 0, nil
}

// resetPasswordUtenteApp imposta una nuova password provvisoria per un
// account utente-app esistente (deve_cambiare_password torna a true, stessa
// semantica della password data alla creazione): restituisce false se lo
// username non esiste. Chiamata SOLO dalla pagina admin
// (PUT /api/utenti/:username/password, authMiddleware) — a differenza di
// cambiaPasswordUtenteApp (self-service dall'app, richiede la password
// attuale) qui è l'admin a resettarla per conto dell'utente, quindi nessuna
// verifica della password precedente: stesso livello di fiducia già in uso
// per creare/eliminare un account utente-app da questa pagina. Rivede la
// scelta precedente "niente reset da qui, si elimina e si ricrea" (vedi
// CLAUDE.md): un reset preserva lo username e lo storico dell'account invece
// di ricrearlo da zero.
func resetPasswordUtenteApp(ctx context.Context, pool *pgxpool.Pool, username, nuovaPassword string) (bool, error) {
	hash, err := bcrypt.GenerateFromPassword([]byte(nuovaPassword), bcrypt.DefaultCost)
	if err != nil {
		return false, err
	}
	tag, err := pool.Exec(ctx,
		"UPDATE utenti_app SET password_hash = $1, deve_cambiare_password = true WHERE username = $2",
		string(hash), username)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() > 0, nil
}

// loginUtenteApp verifica le credenziali di un account utente-app e
// restituisce un token JWT (Role: "utente") più deveCambiarePassword, così
// l'app sa se mostrare subito la schermata di cambio password obbligatorio.
// Token vuoto (nessun errore) se le credenziali non sono valide — stesso
// schema di login() in auth.go, incluso il dummyHash condiviso per un tempo
// di risposta costante indipendentemente dall'esistenza dello username.
func loginUtenteApp(ctx context.Context, pool *pgxpool.Pool, username, password string) (token string, deveCambiarePassword bool, err error) {
	var hash string
	err = pool.QueryRow(ctx,
		"SELECT password_hash, deve_cambiare_password FROM utenti_app WHERE username = $1", username).
		Scan(&hash, &deveCambiarePassword)
	utenteTrovato := true
	if errors.Is(err, pgx.ErrNoRows) {
		utenteTrovato = false
		hash = string(dummyHash)
		err = nil
	} else if err != nil {
		return "", false, err
	}
	credenzialiValide := bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) == nil
	if !utenteTrovato || !credenzialiValide {
		return "", false, nil
	}
	c := claims{
		Role: "utente",
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   username,
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(tokenTTL())),
		},
	}
	token, err = jwt.NewWithClaims(jwt.SigningMethodHS256, c).SignedString(jwtSecret)
	return token, deveCambiarePassword, err
}

// UtenteAppBackup è la riga usata dal backup/ripristino completo
// (backup.go): include l'hash bcrypt della password, mai esposto da
// UtenteAppInfo/listUtentiApp (pensata per la tabella della pagina admin,
// mai deve mostrare l'hash) — sicuro da includere qui perché l'endpoint di
// backup è protetto come tutti gli altri (solo admin, authMiddleware) e un
// hash bcrypt non permette di risalire alla password in chiaro.
type UtenteAppBackup struct {
	Username             string `json:"username"`
	PasswordHash         string `json:"passwordHash"`
	DeveCambiarePassword bool   `json:"deveCambiarePassword"`
}

// listUtentiAppConHash elenca tutti gli account utente-app CON l'hash della
// password — usata SOLO dal backup completo, mai da un endpoint raggiunto
// dall'app o dalla tabella della pagina admin.
func listUtentiAppConHash(ctx context.Context, pool *pgxpool.Pool) ([]UtenteAppBackup, error) {
	rows, err := pool.Query(ctx,
		"SELECT username, password_hash, deve_cambiare_password FROM utenti_app ORDER BY username ASC")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	utenti := []UtenteAppBackup{}
	for rows.Next() {
		var u UtenteAppBackup
		if err := rows.Scan(&u.Username, &u.PasswordHash, &u.DeveCambiarePassword); err != nil {
			return nil, err
		}
		utenti = append(utenti, u)
	}
	return utenti, rows.Err()
}

// upsertUtentiAppConHash ripristina gli account da un backup: upsert per
// username, scrivendo l'hash così com'è — MAI ri-hashato, è già un hash
// bcrypt valido e ri-hasharlo lo renderebbe inutilizzabile per il login.
// Righe senza username o hash vengono scartate.
func upsertUtentiAppConHash(ctx context.Context, pool *pgxpool.Pool, righe []UtenteAppBackup) (creati, aggiornati, scartati int, err error) {
	tx, err := pool.Begin(ctx)
	if err != nil {
		return 0, 0, 0, err
	}
	defer tx.Rollback(ctx)

	esistenti := map[string]bool{}
	rows, err := tx.Query(ctx, "SELECT username FROM utenti_app")
	if err != nil {
		return 0, 0, 0, err
	}
	for rows.Next() {
		var u string
		if err := rows.Scan(&u); err != nil {
			rows.Close()
			return 0, 0, 0, err
		}
		esistenti[u] = true
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return 0, 0, 0, err
	}

	for _, r := range righe {
		username := strings.TrimSpace(r.Username)
		if username == "" || r.PasswordHash == "" {
			scartati++
			continue
		}
		if esistenti[username] {
			if _, err = tx.Exec(ctx,
				"UPDATE utenti_app SET password_hash=$1, deve_cambiare_password=$2 WHERE username=$3",
				r.PasswordHash, r.DeveCambiarePassword, username,
			); err != nil {
				return 0, 0, 0, err
			}
			aggiornati++
		} else {
			if _, err = tx.Exec(ctx,
				"INSERT INTO utenti_app (username, password_hash, deve_cambiare_password) VALUES ($1,$2,$3)",
				username, r.PasswordHash, r.DeveCambiarePassword,
			); err != nil {
				return 0, 0, 0, err
			}
			esistenti[username] = true
			creati++
		}
	}

	if err := tx.Commit(ctx); err != nil {
		return 0, 0, 0, err
	}
	return creati, aggiornati, scartati, nil
}

// cambiaPasswordUtenteApp verifica passwordAttuale e, se corretta, aggiorna
// l'hash e azzera deve_cambiare_password. username arriva sempre dal token
// già validato (context, vedi usernameFromContext in auth.go), mai dal body.
func cambiaPasswordUtenteApp(ctx context.Context, pool *pgxpool.Pool, username, passwordAttuale, passwordNuova string) error {
	var hash string
	if err := pool.QueryRow(ctx, "SELECT password_hash FROM utenti_app WHERE username = $1", username).Scan(&hash); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return errors.New("utente non trovato")
		}
		return err
	}
	if bcrypt.CompareHashAndPassword([]byte(hash), []byte(passwordAttuale)) != nil {
		return errPasswordAttualeErrata
	}
	nuovoHash, err := bcrypt.GenerateFromPassword([]byte(passwordNuova), bcrypt.DefaultCost)
	if err != nil {
		return err
	}
	_, err = pool.Exec(ctx,
		`UPDATE utenti_app SET password_hash = $1, deve_cambiare_password = false WHERE username = $2`,
		string(nuovoHash), username)
	return err
}
