package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"
)

var jwtSecret = []byte(envOr("JWT_SECRET", "cambia-questa-chiave"))

// tokenTTL legge TOKEN_TTL: accetta sia la sintassi Go ("720h") sia un
// numero di giorni con suffisso "d" (es. "30d", compatibilità con l'.env
// del vecchio backend Node) — time.ParseDuration da solo non capisce "d".
func tokenTTL() time.Duration {
	raw := envOr("TOKEN_TTL", "30d")
	if n, ok := strings.CutSuffix(raw, "d"); ok {
		if giorni, err := strconv.Atoi(n); err == nil {
			return time.Duration(giorni) * 24 * time.Hour
		}
	}
	if d, err := time.ParseDuration(raw); err == nil {
		return d
	}
	return 30 * 24 * time.Hour
}

// seedAdmin crea l'utente admin iniziale dalle variabili d'ambiente, se non esiste già.
func seedAdmin(ctx context.Context, pool *pgxpool.Pool) error {
	username := os.Getenv("ADMIN_USERNAME")
	password := os.Getenv("ADMIN_PASSWORD")
	if username == "" || password == "" {
		log.Println("[auth] ADMIN_USERNAME/ADMIN_PASSWORD non impostati: nessun utente creato.")
		return nil
	}
	var esiste int
	err := pool.QueryRow(ctx, "SELECT 1 FROM users WHERE username = $1", username).Scan(&esiste)
	if err == nil {
		return nil // già presente
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return err
	}
	if err := createUser(ctx, pool, username, password); err != nil {
		return err
	}
	log.Printf("[auth] utente admin '%s' creato.\n", username)
	return nil
}

// createUser inserisce (o ignora se esiste) un utente con password hashata.
func createUser(ctx context.Context, pool *pgxpool.Pool, username, password string) error {
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	if err != nil {
		return err
	}
	_, err = pool.Exec(ctx,
		`INSERT INTO users (username, password_hash) VALUES ($1, $2)
		 ON CONFLICT (username) DO NOTHING`,
		username, string(hash))
	return err
}

// login verifica le credenziali e restituisce un token JWT; stringa vuota
// (nessun errore) se le credenziali non sono valide.
func login(ctx context.Context, pool *pgxpool.Pool, username, password string) (string, error) {
	var hash string
	err := pool.QueryRow(ctx, "SELECT password_hash FROM users WHERE username = $1", username).Scan(&hash)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", nil
	}
	if err != nil {
		return "", err
	}
	if bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) != nil {
		return "", nil
	}
	claims := jwt.RegisteredClaims{
		Subject:   username,
		ExpiresAt: jwt.NewNumericDate(time.Now().Add(tokenTTL())),
	}
	return jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString(jwtSecret)
}

// authMiddleware avvolge un handler richiedendo un token JWT valido
// nell'header Authorization (Bearer).
func authMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		header := r.Header.Get("Authorization")
		token, haBearer := strings.CutPrefix(header, "Bearer ")
		if !haBearer || token == "" {
			writeError(w, http.StatusUnauthorized, "Token mancante")
			return
		}
		_, err := jwt.Parse(token, func(t *jwt.Token) (any, error) {
			return jwtSecret, nil
		})
		if err != nil {
			writeError(w, http.StatusUnauthorized, "Token non valido o scaduto")
			return
		}
		next(w, r)
	}
}
