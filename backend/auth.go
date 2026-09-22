package main

import (
	"context"
	"errors"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"
)

const jwtSecretPlaceholder = "cambia-questa-chiave"

var jwtSecret = []byte(envOr("JWT_SECRET", jwtSecretPlaceholder))

// jwtSecretPlaceholders elenca tutti i valori di esempio presenti nei file
// del progetto (docker-compose.yml, .env.example) oltre al fallback Go qui
// sopra: se JWT_SECRET coincide con uno di questi, non è stato configurato
// davvero, anche se la variabile d'ambiente non è vuota.
var jwtSecretPlaceholders = map[string]bool{
	"":                                 true,
	jwtSecretPlaceholder:               true,
	"change_me_secret":                 true, // default in docker-compose.yml
	"metti-una-chiave-lunga-e-casuale": true, // valore di esempio in .env.example
}

// checkJwtSecret termina il processo se JWT_SECRET non è stato personalizzato:
// senza questo controllo il server parte comunque con un segreto noto
// pubblicamente (questo stesso repository), e chiunque lo conosca può
// firmarsi un JWT admin valido. Chiamata da main() prima di aprire qualunque
// connessione, così il fallimento è immediato e il motivo è chiaro nel log.
func checkJwtSecret() {
	if jwtSecretPlaceholders[os.Getenv("JWT_SECRET")] {
		log.Fatal("[auth] JWT_SECRET non configurato (assente o lasciato al valore di esempio): " +
			"impostalo a una stringa lunga e casuale prima di avviare il server, vedi .env.example.")
	}
}

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

// claims sono le informazioni portate da ogni JWT emesso da questo backend.
// Role distingue un account admin (pagina /admin/, accesso completo alle
// rotte di scrittura) da un account utente-app (solo lettura dei contenuti
// riservati in app + cambio della propria password, vedi
// contentAuthMiddleware/utenteAuthMiddleware in fondo al file): senza questo
// campo un token utente-app, firmato con lo stesso JWT_SECRET, varrebbe
// anche per le rotte admin.
type claims struct {
	Role string `json:"role"`
	jwt.RegisteredClaims
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

// dummyHash è un hash bcrypt precalcolato di una password fittizia, usato al
// posto di un vero hash quando lo username non esiste: senza, login
// impiegherebbe un tempo misurabilmente diverso (niente bcrypt eseguito) tra
// "utente inesistente" e "utente esistente, password sbagliata" — un
// side-channel per enumerare gli username validi prima di un bruteforce
// mirato. bcrypt.GenerateFromPassword su una stringa fissa non fallisce mai.
var dummyHash, _ = bcrypt.GenerateFromPassword([]byte("dummy-password-per-timing-costante"), bcrypt.DefaultCost)

// UserInfo è la vista pubblica di un utente admin (mai la password/hash).
type UserInfo struct {
	Username  string `json:"username"`
	CreatedAt string `json:"createdAt"`
}

// listUsers elenca gli utenti admin esistenti (senza hash), per la pagina
// admin: prima non c'era alcun modo di vedere/revocare un account creato,
// solo di crearne di nuovi.
func listUsers(ctx context.Context, pool *pgxpool.Pool) ([]UserInfo, error) {
	rows, err := pool.Query(ctx, "SELECT username, created_at FROM users ORDER BY username ASC")
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	utenti := []UserInfo{}
	for rows.Next() {
		var u UserInfo
		var creato time.Time
		if err := rows.Scan(&u.Username, &creato); err != nil {
			return nil, err
		}
		u.CreatedAt = creato.UTC().Format(time.RFC3339)
		utenti = append(utenti, u)
	}
	return utenti, rows.Err()
}

// changeUserPassword imposta una nuova password per un utente admin
// esistente; restituisce false se lo username non esiste. Chiamata SOLO
// dalla pagina admin (PUT /api/auth/users/:username/password,
// authMiddleware): qualunque admin può reimpostare la password di un altro
// senza conoscere quella attuale, stesso livello di fiducia già in uso per
// la creazione/eliminazione di un account admin — a differenza del cambio
// password lato utente-app (cambiaPasswordUtenteApp), qui non c'è un
// "proprietario" del token che deve dimostrare di conoscere la password
// attuale: è un reset amministrativo, non un self-service.
func changeUserPassword(ctx context.Context, pool *pgxpool.Pool, username, nuovaPassword string) (bool, error) {
	hash, err := bcrypt.GenerateFromPassword([]byte(nuovaPassword), bcrypt.DefaultCost)
	if err != nil {
		return false, err
	}
	tag, err := pool.Exec(ctx, "UPDATE users SET password_hash = $1 WHERE username = $2", string(hash), username)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() > 0, nil
}

// deleteUser elimina un utente admin per username; restituisce false se non
// esisteva. Impedisce di restare senza alcun account (l'unico modo per
// rientrare sarebbe ricreare l'utente dalle variabili d'ambiente al riavvio).
func deleteUser(ctx context.Context, pool *pgxpool.Pool, username string) (bool, error) {
	var totale int
	if err := pool.QueryRow(ctx, "SELECT COUNT(*) FROM users").Scan(&totale); err != nil {
		return false, err
	}
	if totale <= 1 {
		return false, errors.New("non è possibile eliminare l'unico utente admin rimasto")
	}
	tag, err := pool.Exec(ctx, "DELETE FROM users WHERE username = $1", username)
	if err != nil {
		return false, err
	}
	return tag.RowsAffected() > 0, nil
}

// login verifica le credenziali e restituisce un token JWT; stringa vuota
// (nessun errore) se le credenziali non sono valide.
func login(ctx context.Context, pool *pgxpool.Pool, username, password string) (string, error) {
	var hash string
	err := pool.QueryRow(ctx, "SELECT password_hash FROM users WHERE username = $1", username).Scan(&hash)
	utenteTrovato := true
	if errors.Is(err, pgx.ErrNoRows) {
		utenteTrovato = false
		hash = string(dummyHash)
	} else if err != nil {
		return "", err
	}
	// bcrypt gira sempre, anche per uno username inesistente (sul dummyHash):
	// il tempo di risposta non deve dipendere da quale dei due rami sopra è
	// stato preso.
	credenzialiValide := bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) == nil
	if !utenteTrovato || !credenzialiValide {
		return "", nil
	}
	c := claims{
		Role: "admin",
		RegisteredClaims: jwt.RegisteredClaims{
			Subject:   username,
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(tokenTTL())),
		},
	}
	return jwt.NewWithClaims(jwt.SigningMethodHS256, c).SignedString(jwtSecret)
}

// --- Rate limit sui tentativi di login falliti ---
//
// In-memory, per chiave (IP del chiamante): non condiviso tra repliche, ma
// questo backend gira a istanza singola (vedi CLAUDE.md, nessuno scoping
// multi-istanza) — sufficiente a fermare un bruteforce automatizzato della
// password admin, che prima non aveva alcun freno.

type tentativiLogin struct {
	conteggio int
	scadenza  time.Time
}

var (
	loginRateMu    sync.Mutex
	loginRateStato = map[string]*tentativiLogin{}
)

const (
	loginRateMax      = 5
	loginRateFinestra = 5 * time.Minute
)

// loginRateLimitato controlla se [chiave] ha già esaurito i tentativi
// consentiti nella finestra corrente, senza consumarne uno.
func loginRateLimitato(chiave string) bool {
	loginRateMu.Lock()
	defer loginRateMu.Unlock()
	t, ok := loginRateStato[chiave]
	if !ok || time.Now().After(t.scadenza) {
		return false
	}
	return t.conteggio >= loginRateMax
}

// loginRegistraFallito conta un tentativo fallito per [chiave], aprendo una
// nuova finestra se quella corrente è scaduta o non esiste.
func loginRegistraFallito(chiave string) {
	loginRateMu.Lock()
	defer loginRateMu.Unlock()
	t, ok := loginRateStato[chiave]
	if !ok || time.Now().After(t.scadenza) {
		t = &tentativiLogin{scadenza: time.Now().Add(loginRateFinestra)}
		loginRateStato[chiave] = t
	}
	t.conteggio++
}

// loginResettaTentativi azzera il contatore di [chiave] dopo un login riuscito.
func loginResettaTentativi(chiave string) {
	loginRateMu.Lock()
	defer loginRateMu.Unlock()
	delete(loginRateStato, chiave)
}

// parseToken valida il JWT nell'header Authorization (Bearer) e ne
// restituisce le claims; errore per token mancante/malformato/scaduto.
func parseToken(r *http.Request) (*claims, error) {
	header := r.Header.Get("Authorization")
	tokenStr, haBearer := strings.CutPrefix(header, "Bearer ")
	if !haBearer || tokenStr == "" {
		return nil, errors.New("token mancante")
	}
	var c claims
	if _, err := jwt.ParseWithClaims(tokenStr, &c, func(t *jwt.Token) (any, error) {
		return jwtSecret, nil
	}); err != nil {
		return nil, err
	}
	return &c, nil
}

// ctxKey evita collisioni con altre chiavi di context.Context eventualmente
// usate altrove (tipo privato, non un semplice string).
type ctxKey int

const ctxKeyUsername ctxKey = iota

// usernameFromContext restituisce lo username (claims.Subject) del titolare
// del token già validato da uno dei middleware sotto — mai passato a mano
// dal chiamante (es. nel body): un handler come il cambio password deve
// sapere CHI sta scrivendo senza fidarsi di un username arbitrario, altrimenti
// un utente-app potrebbe cambiare la password di un altro semplicemente
// indovinandone lo username.
func usernameFromContext(r *http.Request) string {
	u, _ := r.Context().Value(ctxKeyUsername).(string)
	return u
}

// roleMiddleware avvolge un handler richiedendo un JWT valido il cui Role sia
// tra quelli ammessi; mette lo username autenticato nel context della
// richiesta (vedi usernameFromContext). Base comune di authMiddleware
// (solo admin), utenteAuthMiddleware (solo utente-app) e
// contentAuthMiddleware (admin o utente-app, per la sola lettura dei
// contenuti riservati).
func roleMiddleware(next http.HandlerFunc, ruoliAmmessi ...string) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		c, err := parseToken(r)
		if err != nil {
			writeError(w, http.StatusUnauthorized, "Token mancante o non valido")
			return
		}
		ammesso := false
		for _, ruolo := range ruoliAmmessi {
			if c.Role == ruolo {
				ammesso = true
				break
			}
		}
		if !ammesso {
			writeError(w, http.StatusUnauthorized, "Token non valido o scaduto")
			return
		}
		next(w, r.WithContext(context.WithValue(r.Context(), ctxKeyUsername, c.Subject)))
	}
}

// authMiddleware: rotte riservate alla pagina admin (gestione ospedali,
// fogli, materiali, utenti-app, comunicati...).
func authMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return roleMiddleware(next, "admin")
}

// utenteAuthMiddleware: rotte che un account utente-app scrive su se stesso
// (oggi solo il cambio password) — un token admin non è ammesso, non deve
// poter agire "per conto" di un utente-app.
func utenteAuthMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return roleMiddleware(next, "utente")
}

// contentAuthMiddleware: lettura dei contenuti riservati dell'app
// (comunicati, repository-formazione) — sia un utente-app sia un admin
// possono leggerli.
func contentAuthMiddleware(next http.HandlerFunc) http.HandlerFunc {
	return roleMiddleware(next, "admin", "utente")
}
