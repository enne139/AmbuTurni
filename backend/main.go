// Bootstrap del server: auth, API ospedali e pagina admin statica.
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"log"
	"mime"
	"net/http"
	"regexp"
	"strconv"
	"strings"

	"github.com/jackc/pgx/v5"
)

func main() {
	// Va prima di qualunque altra cosa: un server che parte con un JWT_SECRET
	// non configurato firmerebbe token admin con un segreto noto pubblicamente
	// (questo stesso repository).
	checkJwtSecret()

	startupCtx := context.Background()

	pool, err := connectDB(startupCtx)
	if err != nil {
		log.Fatalf("[db] connessione fallita: %v", err)
	}
	defer pool.Close()

	if err := initSchema(startupCtx, pool); err != nil {
		log.Fatalf("[db] inizializzazione schema fallita: %v", err)
	}
	if err := seedAdmin(startupCtx, pool); err != nil {
		log.Fatalf("[auth] seed admin fallito: %v", err)
	}

	mux := http.NewServeMux()

	// Tutte le rotte API vivono sotto /api/, PERMANENTEMENTE (non solo dietro
	// nginx in produzione): il client Flutter (utils/backend_api.dart) chiama
	// sempre $baseUrl/api/..., quindi il backend deve rispondere lì anche
	// quando lo si testa standalone (go run/docker compose in backend/,
	// senza nginx davanti) — altrimenti funziona solo in produzione e mai in
	// locale, indipendentemente dall'indirizzo configurato nell'app (bug
	// reale scoperto testando in locale: verificaConnessione falliva sempre
	// perché nessuna rotta rispondeva su /api/health). nginx.conf fa un
	// semplice pass-through di /api/ (nessun prefisso da togliere).
	//
	// Ogni handler usa r.Context() (non uno startupCtx catturato): senza,
	// una richiesta lenta o un client disconnesso non annullerebbe mai la
	// query, con il rischio di esaurire il pool di connessioni sotto carico.

	// Healthcheck (usato anche da docker-compose / monitoraggio).
	mux.HandleFunc("GET /api/health", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	// --- AUTENTICAZIONE (solo per la pagina admin) ---

	// Login: restituisce un token JWT da usare come Bearer per aggiungere/eliminare ospedali.
	// Rate-limited per IP (loginRateLimitato/loginRegistraFallito in auth.go):
	// senza, un bruteforce della password admin non aveva alcun freno.
	mux.HandleFunc("POST /api/auth/login", func(w http.ResponseWriter, r *http.Request) {
		chiave := clientIP(r)
		if loginRateLimitato(chiave) {
			writeError(w, http.StatusTooManyRequests, "troppi tentativi falliti, riprova tra qualche minuto")
			return
		}
		var body struct{ Username, Password string }
		if !readJSON(w, r, &body) {
			return
		}
		if body.Username == "" || body.Password == "" {
			writeError(w, http.StatusBadRequest, "username e password richiesti")
			return
		}
		token, err := login(r.Context(), pool, body.Username, body.Password)
		if err != nil {
			log.Printf("[auth] errore login: %v\n", err)
			writeError(w, http.StatusInternalServerError, "errore interno")
			return
		}
		if token == "" {
			loginRegistraFallito(chiave)
			writeError(w, http.StatusUnauthorized, "Credenziali non valide")
			return
		}
		loginResettaTentativi(chiave)
		writeJSON(w, http.StatusOK, map[string]string{"token": token})
	})

	// Creazione di nuovi utenti admin: protetta (solo chi è già autenticato può aggiungere account).
	mux.HandleFunc("POST /api/auth/users", authMiddleware(func(w http.ResponseWriter, r *http.Request) {
		var body struct{ Username, Password string }
		if !readJSON(w, r, &body) {
			return
		}
		if body.Username == "" || body.Password == "" {
			writeError(w, http.StatusBadRequest, "username e password richiesti")
			return
		}
		if err := createUser(r.Context(), pool, body.Username, body.Password); err != nil {
			log.Printf("[auth] errore creazione utente: %v\n", err)
			writeError(w, http.StatusInternalServerError, "errore interno")
			return
		}
		writeJSON(w, http.StatusCreated, map[string]bool{"ok": true})
	}))

	// Elenco e revoca degli utenti admin: prima si potevano solo creare, mai
	// vedere o eliminare (un account compromesso o non più usato restava
	// valido per sempre, l'unico modo per "spegnerlo" era ruotare JWT_SECRET,
	// disconnettendo anche gli admin legittimi).
	mux.HandleFunc("GET /api/auth/users", authMiddleware(func(w http.ResponseWriter, r *http.Request) {
		utenti, err := listUsers(r.Context(), pool)
		if err != nil {
			log.Printf("[auth] errore lista utenti: %v\n", err)
			writeError(w, http.StatusInternalServerError, "errore interno")
			return
		}
		writeJSON(w, http.StatusOK, utenti)
	}))

	mux.HandleFunc("DELETE /api/auth/users/{username}", authMiddleware(func(w http.ResponseWriter, r *http.Request) {
		rimosso, err := deleteUser(r.Context(), pool, r.PathValue("username"))
		if err != nil {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		if !rimosso {
			writeError(w, http.StatusNotFound, "Utente non trovato")
			return
		}
		writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
	}))

	// --- UTENTI APP ---
	// Account che sbloccano i contenuti riservati dell'app (Repository
	// formazione, Comunicati): creati SOLO dalla pagina admin — l'app
	// Flutter non li crea/elenca/elimina mai, chiama solo login e cambio
	// password (vedi CLAUDE.md, confine esplicito voluto dall'utente).

	// Login: come /api/auth/login ma per gli account utente-app (Role:
	// "utente" nel JWT, tabella utenti_app separata da users). Stesso
	// rate-limiter dell'admin (budget condiviso per IP): comunque
	// sufficiente a fermare un bruteforce automatizzato.
	mux.HandleFunc("POST /api/utenti/login", func(w http.ResponseWriter, r *http.Request) {
		chiave := clientIP(r)
		if loginRateLimitato(chiave) {
			writeError(w, http.StatusTooManyRequests, "troppi tentativi falliti, riprova tra qualche minuto")
			return
		}
		var body struct{ Username, Password string }
		if !readJSON(w, r, &body) {
			return
		}
		if body.Username == "" || body.Password == "" {
			writeError(w, http.StatusBadRequest, "username e password richiesti")
			return
		}
		token, deveCambiarePassword, err := loginUtenteApp(r.Context(), pool, body.Username, body.Password)
		if err != nil {
			log.Printf("[utenti] errore login: %v\n", err)
			writeError(w, http.StatusInternalServerError, "errore interno")
			return
		}
		if token == "" {
			loginRegistraFallito(chiave)
			writeError(w, http.StatusUnauthorized, "Credenziali non valide")
			return
		}
		loginResettaTentativi(chiave)
		writeJSON(w, http.StatusOK, map[string]any{
			"token": token, "deveCambiarePassword": deveCambiarePassword,
		})
	})

	// Cambio password: protetta da utenteAuthMiddleware (solo un token
	// Role="utente", un admin non è ammesso). Lo username viene dal token
	// (usernameFromContext), mai dal body.
	mux.HandleFunc("PUT /api/utenti/password", utenteAuthMiddleware(func(w http.ResponseWriter, r *http.Request) {
		var body struct{ PasswordAttuale, PasswordNuova string }
		if !readJSON(w, r, &body) {
			return
		}
		if len(body.PasswordNuova) < 8 {
			writeError(w, http.StatusBadRequest, "la nuova password deve avere almeno 8 caratteri")
			return
		}
		err := cambiaPasswordUtenteApp(r.Context(), pool, usernameFromContext(r), body.PasswordAttuale, body.PasswordNuova)
		if errors.Is(err, errPasswordAttualeErrata) {
			writeError(w, http.StatusBadRequest, "password attuale errata")
			return
		}
		if err != nil {
			log.Printf("[utenti] errore cambio password: %v\n", err)
			writeError(w, http.StatusInternalServerError, "errore interno")
			return
		}
		writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
	}))

	// Creazione, elenco e revoca: protette da authMiddleware (solo admin).
	// Chiamate SOLO dalla pagina admin (tab "Utenti app").
	mux.HandleFunc("POST /api/utenti", authMiddleware(func(w http.ResponseWriter, r *http.Request) {
		var body struct{ Username, Password string }
		if !readJSON(w, r, &body) {
			return
		}
		if body.Username == "" || body.Password == "" {
			writeError(w, http.StatusBadRequest, "username e password richiesti")
			return
		}
		if err := createUtenteApp(r.Context(), pool, body.Username, body.Password); err != nil {
			log.Printf("[utenti] errore creazione: %v\n", err)
			writeError(w, http.StatusInternalServerError, "errore interno")
			return
		}
		writeJSON(w, http.StatusCreated, map[string]bool{"ok": true})
	}))

	mux.HandleFunc("GET /api/utenti", authMiddleware(func(w http.ResponseWriter, r *http.Request) {
		utenti, err := listUtentiApp(r.Context(), pool)
		if err != nil {
			log.Printf("[utenti] errore lista: %v\n", err)
			writeError(w, http.StatusInternalServerError, "errore interno")
			return
		}
		writeJSON(w, http.StatusOK, utenti)
	}))

	mux.HandleFunc("DELETE /api/utenti/{username}", authMiddleware(func(w http.ResponseWriter, r *http.Request) {
		rimosso, err := deleteUtenteApp(r.Context(), pool, r.PathValue("username"))
		if err != nil {
			log.Printf("[utenti] errore eliminazione: %v\n", err)
			writeError(w, http.StatusInternalServerError, "errore interno")
			return
		}
		if !rimosso {
			writeError(w, http.StatusNotFound, "Utente non trovato")
			return
		}
		writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
	}))

	// --- OSPEDALI ---

	// Pubblica: i client (app AmbuTurni) scaricano l'elenco per popolare Lista
	// ospedali, senza bisogno di credenziali. ?citta= o ?regione= filtrano
	// (case-insensitive, match esatto; citta ha priorità se entrambi passati);
	// senza parametri restituisce tutto l'elenco.
	mux.HandleFunc("GET /api/ospedali", func(w http.ResponseWriter, r *http.Request) {
		citta := strings.TrimSpace(r.URL.Query().Get("citta"))
		regione := strings.TrimSpace(r.URL.Query().Get("regione"))
		lista, err := listOspedali(r.Context(), pool, citta, regione)
		if err != nil {
			log.Printf("[ospedali] errore lista: %v\n", err)
			writeError(w, http.StatusInternalServerError, "errore interno")
			return
		}
		writeJSON(w, http.StatusOK, lista)
	})

	// Pubblica: le città che hanno almeno un ospedale, per popolare un
	// elenco selezionabile lato client invece di far digitare alla cieca.
	mux.HandleFunc("GET /api/citta", func(w http.ResponseWriter, r *http.Request) {
		lista, err := listCitta(r.Context(), pool)
		if err != nil {
			log.Printf("[ospedali] errore lista città: %v\n", err)
			writeError(w, http.StatusInternalServerError, "errore interno")
			return
		}
		writeJSON(w, http.StatusOK, lista)
	})

	// Pubblica: le regioni che hanno almeno un ospedale, stesso scopo di
	// /api/citta ma per il raggruppamento/download per regione lato client.
	mux.HandleFunc("GET /api/regioni", func(w http.ResponseWriter, r *http.Request) {
		lista, err := listRegioni(r.Context(), pool)
		if err != nil {
			log.Printf("[ospedali] errore lista regioni: %v\n", err)
			writeError(w, http.StatusInternalServerError, "errore interno")
			return
		}
		writeJSON(w, http.StatusOK, lista)
	})

	// Protette: solo dalla pagina admin, dopo login.
	mux.HandleFunc("POST /api/ospedali", authMiddleware(func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			Nome    string   `json:"nome"`
			Via     *string  `json:"via"`
			Citta   *string  `json:"citta"`
			Lat     *float64 `json:"lat"`
			Lng     *float64 `json:"lng"`
			Regione *string  `json:"regione"`
		}
		if !readJSON(w, r, &body) {
			return
		}
		body.Nome = strings.TrimSpace(body.Nome)
		if body.Nome == "" {
			writeError(w, http.StatusBadRequest, "nome richiesto")
			return
		}
		creato, err := createOspedale(r.Context(), pool, body.Nome, body.Via, body.Citta, body.Regione, body.Lat, body.Lng)
		if err != nil {
			log.Printf("[ospedali] errore creazione: %v\n", err)
			writeError(w, http.StatusInternalServerError, "errore interno")
			return
		}
		writeJSON(w, http.StatusCreated, creato)
	}))

	// Modifica: usata dal pulsante "Modifica" della pagina admin (riusa lo
	// stesso form dell'aggiunta). Sostituisce tutti i campi, come il POST.
	mux.HandleFunc("PUT /api/ospedali/{id}", authMiddleware(func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			Nome    string   `json:"nome"`
			Via     *string  `json:"via"`
			Citta   *string  `json:"citta"`
			Lat     *float64 `json:"lat"`
			Lng     *float64 `json:"lng"`
			Regione *string  `json:"regione"`
		}
		if !readJSON(w, r, &body) {
			return
		}
		body.Nome = strings.TrimSpace(body.Nome)
		if body.Nome == "" {
			writeError(w, http.StatusBadRequest, "nome richiesto")
			return
		}
		aggiornato, err := updateOspedale(r.Context(), pool, r.PathValue("id"), body.Nome, body.Via, body.Citta, body.Regione, body.Lat, body.Lng)
		if errors.Is(err, pgx.ErrNoRows) {
			writeError(w, http.StatusNotFound, "Ospedale non trovato")
			return
		}
		if err != nil {
			log.Printf("[ospedali] errore aggiornamento: %v\n", err)
			writeError(w, http.StatusInternalServerError, "errore interno")
			return
		}
		writeJSON(w, http.StatusOK, aggiornato)
	}))

	mux.HandleFunc("DELETE /api/ospedali/{id}", authMiddleware(func(w http.ResponseWriter, r *http.Request) {
		rimosso, err := deleteOspedale(r.Context(), pool, r.PathValue("id"))
		if err != nil {
			log.Printf("[ospedali] errore eliminazione: %v\n", err)
			writeError(w, http.StatusInternalServerError, "errore interno")
			return
		}
		if !rimosso {
			writeError(w, http.StatusNotFound, "Ospedale non trovato")
			return
		}
		writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
	}))

	// Import massivo: usata dal pulsante "Importa file" della pagina admin
	// per caricare in un colpo solo un elenco intero invece di aggiungere un
	// ospedale alla volta col form. Accetta sia un array puro sia
	// {"ospedali": [...]} — lo stesso formato che l'app esporta da
	// Impostazioni → Ospedali → Esporta, importabile qui senza trasformazioni.
	mux.HandleFunc("POST /api/ospedali/import", authMiddleware(func(w http.ResponseWriter, r *http.Request) {
		raw, ok := readBodyLimited(w, r, maxImportBodyBytes)
		if !ok {
			return
		}
		var righe []OspedaleInput
		if err := json.Unmarshal(raw, &righe); err != nil {
			var wrapper struct {
				Ospedali []OspedaleInput `json:"ospedali"`
			}
			if err2 := json.Unmarshal(raw, &wrapper); err2 != nil || wrapper.Ospedali == nil {
				writeError(w, http.StatusBadRequest,
					`formato non valido: atteso un elenco di ospedali o {"ospedali": [...]}`)
				return
			}
			righe = wrapper.Ospedali
		}
		creati, aggiornati, scartati, err := upsertOspedali(r.Context(), pool, righe)
		if err != nil {
			log.Printf("[ospedali] errore import: %v\n", err)
			writeError(w, http.StatusInternalServerError, "errore interno")
			return
		}
		writeJSON(w, http.StatusOK, map[string]int{
			"creati": creati, "aggiornati": aggiornati, "scartati": scartati,
		})
	}))

	// --- FOGLI TURNI ---
	// Link ai fogli Google Sheets del piano turni mensile (tool "Piano
	// turni"): lettura pubblica (il client li scarica automaticamente se
	// l'impostazione "Sincronizza fogli turni" è attiva, di default sì),
	// scrittura solo da admin — stesso schema di fiducia di /api/ospedali,
	// niente scrittura lato client (che non ha alcun login).

	mux.HandleFunc("GET /api/fogli", func(w http.ResponseWriter, r *http.Request) {
		lista, err := listFogli(r.Context(), pool)
		if err != nil {
			log.Printf("[fogli] errore lista: %v\n", err)
			writeError(w, http.StatusInternalServerError, "errore interno")
			return
		}
		writeJSON(w, http.StatusOK, lista)
	})

	mux.HandleFunc("POST /api/fogli", authMiddleware(func(w http.ResponseWriter, r *http.Request) {
		var body struct{ Chiave, Url string }
		if !readJSON(w, r, &body) {
			return
		}
		body.Chiave = strings.TrimSpace(body.Chiave)
		body.Url = strings.TrimSpace(body.Url)
		if body.Chiave == "" || body.Url == "" {
			writeError(w, http.StatusBadRequest, "chiave e url richiesti")
			return
		}
		if !chiaveMeseValida(body.Chiave) {
			writeError(w, http.StatusBadRequest, `chiave deve avere formato "aaaa-mm" con mm tra 01 e 12`)
			return
		}
		// Solo http(s): la pagina admin inserisce questo URL come href di un
		// link cliccabile senza validarne lo schema — uno schema diverso
		// (es. "javascript:") sarebbe un self-XSS eseguito al click.
		if !strings.HasPrefix(body.Url, "http://") && !strings.HasPrefix(body.Url, "https://") {
			writeError(w, http.StatusBadRequest, "url deve iniziare con http:// o https://")
			return
		}
		salvato, err := upsertFoglio(r.Context(), pool, body.Chiave, body.Url)
		if err != nil {
			log.Printf("[fogli] errore salvataggio: %v\n", err)
			writeError(w, http.StatusInternalServerError, "errore interno")
			return
		}
		writeJSON(w, http.StatusOK, salvato)
	}))

	mux.HandleFunc("DELETE /api/fogli/{chiave}", authMiddleware(func(w http.ResponseWriter, r *http.Request) {
		rimosso, err := deleteFoglio(r.Context(), pool, r.PathValue("chiave"))
		if err != nil {
			log.Printf("[fogli] errore eliminazione: %v\n", err)
			writeError(w, http.StatusInternalServerError, "errore interno")
			return
		}
		if !rimosso {
			writeError(w, http.StatusNotFound, "Foglio non trovato")
			return
		}
		writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
	}))

	// Import massivo: stessa logica di /api/ospedali/import, upsert per chiave.
	mux.HandleFunc("POST /api/fogli/import", authMiddleware(func(w http.ResponseWriter, r *http.Request) {
		raw, ok := readBodyLimited(w, r, maxImportBodyBytes)
		if !ok {
			return
		}
		var righe []FoglioInput
		if err := json.Unmarshal(raw, &righe); err != nil {
			var wrapper struct {
				Fogli []FoglioInput `json:"fogli"`
			}
			if err2 := json.Unmarshal(raw, &wrapper); err2 != nil || wrapper.Fogli == nil {
				writeError(w, http.StatusBadRequest,
					`formato non valido: atteso un elenco di fogli o {"fogli": [...]}`)
				return
			}
			righe = wrapper.Fogli
		}
		creati, aggiornati, scartati, err := upsertFogli(r.Context(), pool, righe)
		if err != nil {
			log.Printf("[fogli] errore import: %v\n", err)
			writeError(w, http.StatusInternalServerError, "errore interno")
			return
		}
		writeJSON(w, http.StatusOK, map[string]int{
			"creati": creati, "aggiornati": aggiornati, "scartati": scartati,
		})
	}))

	// --- MATERIALI ---
	// Catalogo condiviso dei nomi materiali (Tools → Materiali usati): stesso
	// schema pubblico-lettura/admin-scrittura degli ospedali, usato dal
	// client per popolare il catalogo locale su un device nuovo.

	mux.HandleFunc("GET /api/materiali", func(w http.ResponseWriter, r *http.Request) {
		lista, err := listMateriali(r.Context(), pool)
		if err != nil {
			log.Printf("[materiali] errore lista: %v\n", err)
			writeError(w, http.StatusInternalServerError, "errore interno")
			return
		}
		writeJSON(w, http.StatusOK, lista)
	})

	mux.HandleFunc("POST /api/materiali", authMiddleware(func(w http.ResponseWriter, r *http.Request) {
		var body struct{ Nome string }
		if !readJSON(w, r, &body) {
			return
		}
		body.Nome = strings.TrimSpace(body.Nome)
		if body.Nome == "" {
			writeError(w, http.StatusBadRequest, "nome richiesto")
			return
		}
		creato, err := createMateriale(r.Context(), pool, body.Nome)
		if err != nil {
			log.Printf("[materiali] errore creazione: %v\n", err)
			writeError(w, http.StatusInternalServerError, "errore interno")
			return
		}
		writeJSON(w, http.StatusCreated, creato)
	}))

	mux.HandleFunc("PUT /api/materiali/{id}", authMiddleware(func(w http.ResponseWriter, r *http.Request) {
		var body struct{ Nome string }
		if !readJSON(w, r, &body) {
			return
		}
		body.Nome = strings.TrimSpace(body.Nome)
		if body.Nome == "" {
			writeError(w, http.StatusBadRequest, "nome richiesto")
			return
		}
		aggiornato, err := updateMateriale(r.Context(), pool, r.PathValue("id"), body.Nome)
		if errors.Is(err, pgx.ErrNoRows) {
			writeError(w, http.StatusNotFound, "Materiale non trovato")
			return
		}
		if err != nil {
			log.Printf("[materiali] errore aggiornamento: %v\n", err)
			writeError(w, http.StatusInternalServerError, "errore interno")
			return
		}
		writeJSON(w, http.StatusOK, aggiornato)
	}))

	mux.HandleFunc("DELETE /api/materiali/{id}", authMiddleware(func(w http.ResponseWriter, r *http.Request) {
		rimosso, err := deleteMateriale(r.Context(), pool, r.PathValue("id"))
		if err != nil {
			log.Printf("[materiali] errore eliminazione: %v\n", err)
			writeError(w, http.StatusInternalServerError, "errore interno")
			return
		}
		if !rimosso {
			writeError(w, http.StatusNotFound, "Materiale non trovato")
			return
		}
		writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
	}))

	// Import massivo: stessa logica di /api/ospedali/import, upsert per nome.
	mux.HandleFunc("POST /api/materiali/import", authMiddleware(func(w http.ResponseWriter, r *http.Request) {
		raw, ok := readBodyLimited(w, r, maxImportBodyBytes)
		if !ok {
			return
		}
		var righe []MaterialeInput
		if err := json.Unmarshal(raw, &righe); err != nil {
			var wrapper struct {
				Materiali []MaterialeInput `json:"materiali"`
			}
			if err2 := json.Unmarshal(raw, &wrapper); err2 != nil || wrapper.Materiali == nil {
				writeError(w, http.StatusBadRequest,
					`formato non valido: atteso un elenco di materiali o {"materiali": [...]}`)
				return
			}
			righe = wrapper.Materiali
		}
		creati, aggiornati, scartati, err := upsertMateriali(r.Context(), pool, righe)
		if err != nil {
			log.Printf("[materiali] errore import: %v\n", err)
			writeError(w, http.StatusInternalServerError, "errore interno")
			return
		}
		writeJSON(w, http.StatusOK, map[string]int{
			"creati": creati, "aggiornati": aggiornati, "scartati": scartati,
		})
	}))

	// --- REPOSITORY FORMAZIONE ---
	// Un solo link condiviso (non una collezione): scrittura solo admin,
	// come ospedali/fogli/materiali, ma la lettura è un CONTENUTO RISERVATO
	// (contentAuthMiddleware, non più pubblica): richiede login in app come
	// utente-app o admin. Vedi CLAUDE.md per il perché di questo cambio.

	mux.HandleFunc("GET /api/repository-formazione", contentAuthMiddleware(func(w http.ResponseWriter, r *http.Request) {
		rf, err := getRepositoryFormazione(r.Context(), pool)
		if err != nil {
			log.Printf("[formazione] errore lettura: %v\n", err)
			writeError(w, http.StatusInternalServerError, "errore interno")
			return
		}
		writeJSON(w, http.StatusOK, rf)
	}))

	mux.HandleFunc("POST /api/repository-formazione", authMiddleware(func(w http.ResponseWriter, r *http.Request) {
		var body struct{ Url string }
		if !readJSON(w, r, &body) {
			return
		}
		body.Url = strings.TrimSpace(body.Url)
		if body.Url == "" {
			writeError(w, http.StatusBadRequest, "url richiesto")
			return
		}
		if !strings.HasPrefix(body.Url, "http://") && !strings.HasPrefix(body.Url, "https://") {
			writeError(w, http.StatusBadRequest, "url deve iniziare con http:// o https://")
			return
		}
		rf, err := setRepositoryFormazione(r.Context(), pool, body.Url)
		if err != nil {
			log.Printf("[formazione] errore salvataggio: %v\n", err)
			writeError(w, http.StatusInternalServerError, "errore interno")
			return
		}
		writeJSON(w, http.StatusOK, rf)
	}))

	// --- COMUNICATI ---
	// Avvisi con un PDF allegato (tool "Archivio comunicati"): CONTENUTO
	// RISERVATO come repository-formazione (lettura solo con login), upload/
	// eliminazione SOLO dalla pagina admin. Il PDF vive in Postgres (bytea),
	// vedi CLAUDE.md.

	// Elenco metadati (mai il PDF, vedi listComunicati).
	mux.HandleFunc("GET /api/comunicati", contentAuthMiddleware(func(w http.ResponseWriter, r *http.Request) {
		lista, err := listComunicati(r.Context(), pool)
		if err != nil {
			log.Printf("[comunicati] errore lista: %v\n", err)
			writeError(w, http.StatusInternalServerError, "errore interno")
			return
		}
		writeJSON(w, http.StatusOK, lista)
	}))

	// Download del PDF. Content-Disposition costruito con mime.FormatMediaType
	// (escaping corretto del filename) invece di concatenare la stringa a
	// mano, per non rischiare un header injection da un nome file malevolo.
	mux.HandleFunc("GET /api/comunicati/{id}/file", contentAuthMiddleware(func(w http.ResponseWriter, r *http.Request) {
		fileName, data, err := getComunicatoFile(r.Context(), pool, r.PathValue("id"))
		if errors.Is(err, pgx.ErrNoRows) {
			writeError(w, http.StatusNotFound, "Comunicato non trovato")
			return
		}
		if err != nil {
			log.Printf("[comunicati] errore download: %v\n", err)
			writeError(w, http.StatusInternalServerError, "errore interno")
			return
		}
		w.Header().Set("Content-Type", "application/pdf")
		w.Header().Set("Content-Disposition", mime.FormatMediaType("attachment", map[string]string{"filename": fileName}))
		w.Write(data)
	}))

	// Upload: multipart, non JSON (readJSON non si applica qui). Uno o più
	// file sotto lo stesso campo "file" (upload multiplo, richiesta esplicita
	// dell'utente: carica in un colpo solo tutti i PDF di un mese) — senza
	// titolo/descrizione qui (il nome del file è ciò che si mostra di
	// default in app): opzionali, si aggiungono dopo per il singolo
	// comunicato con PUT /api/comunicati/{id}, vedi sotto.
	// Ogni file è validato per contenuto (primi 4 byte "%PDF": un file
	// rinominato a caso non basta a farlo passare per un comunicato); un file
	// non valido nel gruppo viene scartato e contato, non blocca gli altri —
	// stesso pattern "creati/scartati" già in uso per gli import massivi di
	// ospedali/materiali/fogli. La dimensione totale della richiesta è
	// limitata da MaxBytesReader prima di ParseMultipartForm.
	mux.HandleFunc("POST /api/comunicati", authMiddleware(func(w http.ResponseWriter, r *http.Request) {
		r.Body = http.MaxBytesReader(w, r.Body, maxComunicatoBytes)
		if err := r.ParseMultipartForm(10 << 20); err != nil {
			writeError(w, http.StatusBadRequest, "file troppo grandi o corpo della richiesta non valido (max 50 MB totali)")
			return
		}
		files := r.MultipartForm.File["file"]
		if len(files) == 0 {
			writeError(w, http.StatusBadRequest, "almeno un file PDF richiesto")
			return
		}
		creati, scartati := 0, 0
		for _, header := range files {
			ok := func() bool {
				file, err := header.Open()
				if err != nil {
					return false
				}
				defer file.Close()
				data, err := io.ReadAll(file)
				if err != nil || !bytes.HasPrefix(data, []byte("%PDF")) {
					return false
				}
				if _, err := createComunicato(r.Context(), pool, header.Filename, data); err != nil {
					log.Printf("[comunicati] errore creazione %q: %v\n", header.Filename, err)
					return false
				}
				return true
			}()
			if ok {
				creati++
			} else {
				scartati++
			}
		}
		writeJSON(w, http.StatusOK, map[string]int{"creati": creati, "scartati": scartati})
	}))

	// Modifica: solo titolo/descrizione (opzionali), mai il file — usata dal
	// pulsante "Modifica" della pagina admin per aggiungerli dopo il
	// caricamento, quando servono (l'upload multiplo sopra non li chiede).
	mux.HandleFunc("PUT /api/comunicati/{id}", authMiddleware(func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			Titolo      *string `json:"titolo"`
			Descrizione *string `json:"descrizione"`
		}
		if !readJSON(w, r, &body) {
			return
		}
		aggiornato, err := updateComunicato(r.Context(), pool, r.PathValue("id"), body.Titolo, body.Descrizione)
		if errors.Is(err, pgx.ErrNoRows) {
			writeError(w, http.StatusNotFound, "Comunicato non trovato")
			return
		}
		if err != nil {
			log.Printf("[comunicati] errore aggiornamento: %v\n", err)
			writeError(w, http.StatusInternalServerError, "errore interno")
			return
		}
		writeJSON(w, http.StatusOK, aggiornato)
	}))

	mux.HandleFunc("DELETE /api/comunicati/{id}", authMiddleware(func(w http.ResponseWriter, r *http.Request) {
		rimosso, err := deleteComunicato(r.Context(), pool, r.PathValue("id"))
		if err != nil {
			log.Printf("[comunicati] errore eliminazione: %v\n", err)
			writeError(w, http.StatusInternalServerError, "errore interno")
			return
		}
		if !rimosso {
			writeError(w, http.StatusNotFound, "Comunicato non trovato")
			return
		}
		writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
	}))

	// --- BACKUP COMPLETO ---
	// Scarica/ripristina in un solo file (zip) tutto ciò che il backend
	// conosce (ospedali, fogli, materiali, link formazione, utenti app,
	// comunicati coi PDF) — richiesta esplicita dell'utente per un vero
	// disaster recovery: le tre entità "catalogo" avevano già l'export/
	// import a parte (2026-07-20) ma comunicati/utenti-app/formazione ne
	// erano rimasti privi. Solo admin (authMiddleware), come ogni endpoint
	// di scrittura — il download stesso è "sola lettura" ma espone hash
	// delle password e PDF riservati, quindi protetto comunque.
	mux.HandleFunc("GET /api/admin/backup", authMiddleware(func(w http.ResponseWriter, r *http.Request) {
		// costruisciBackup legge tutto PRIMA di scrivere qualunque byte
		// sulla risposta: se fallisce possiamo ancora rispondere 500 pulito,
		// cosa non più possibile una volta iniziato lo streaming dello zip.
		meta, comunicati, err := costruisciBackup(r.Context(), pool)
		if err != nil {
			log.Printf("[backup] errore costruzione: %v\n", err)
			writeError(w, http.StatusInternalServerError, "errore interno")
			return
		}
		nomeFile := "ambuturni_backup_" + meta.EsportatoIl.Format("20060102_150405") + ".zip"
		w.Header().Set("Content-Type", "application/zip")
		w.Header().Set("Content-Disposition", mime.FormatMediaType("attachment", map[string]string{"filename": nomeFile}))
		if err := scriviBackupZip(w, meta, comunicati); err != nil {
			// Qui non si può più cambiare lo status code (header/parte del
			// body già scritti in streaming): solo log, il client riceverà
			// un download troncato — evento raro (solo un errore di rete
			// verso il chiamante durante lo streaming, i dati sono già letti).
			log.Printf("[backup] errore scrittura zip: %v\n", err)
		}
	}))

	// Ripristino: upsert per ogni sezione (mai distruttivo, vedi
	// ripristinaBackup), stesso principio degli import per-categoria. Limite
	// più ampio degli altri import (maxBackupBytes): un archivio zip con
	// tutti i PDF dei comunicati.
	mux.HandleFunc("POST /api/admin/restore", authMiddleware(func(w http.ResponseWriter, r *http.Request) {
		raw, ok := readBodyLimited(w, r, maxBackupBytes)
		if !ok {
			return
		}
		riepilogo, err := ripristinaBackup(r.Context(), pool, raw)
		if errors.Is(err, errBackupNonValido) {
			writeError(w, http.StatusBadRequest, err.Error())
			return
		}
		if err != nil {
			log.Printf("[backup] errore ripristino: %v\n", err)
			writeError(w, http.StatusInternalServerError, "errore interno")
			return
		}
		writeJSON(w, http.StatusOK, riepilogo)
	}))

	// --- PAGINA ADMIN ---
	// Pagina statica (HTML+JS vanilla, nessun framework) per login e gestione
	// ospedali: chiama le API sopra da browser. Serve al gestore del server,
	// non ai client dell'app.
	mux.Handle("/admin/", http.StripPrefix("/admin/", http.FileServer(http.Dir("public/admin"))))

	port := envOr("PORT", "3000")
	log.Printf("[api] in ascolto sulla porta %s\n", port)
	if err := http.ListenAndServe(":"+port, corsMiddleware(mux)); err != nil {
		log.Fatalf("[api] avvio fallito: %v", err)
	}
}

var chiaveMeseRe = regexp.MustCompile(`^(\d{4})-(\d{2})$`)

// chiaveMeseValida controlla il formato "aaaa-mm" E che mm sia un mese
// reale (01-12): la sola regex `^\d{4}-\d{2}$` accettava anche valori come
// "2026-13", salvati senza errori e poi confusi nell'archivio lato client.
func chiaveMeseValida(chiave string) bool {
	m := chiaveMeseRe.FindStringSubmatch(chiave)
	if m == nil {
		return false
	}
	mese, err := strconv.Atoi(m[2])
	return err == nil && mese >= 1 && mese <= 12
}
