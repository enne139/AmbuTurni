// Bootstrap del server: auth, API ospedali e pagina admin statica.
package main

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"regexp"
	"strings"

	"github.com/jackc/pgx/v5"
)

func main() {
	ctx := context.Background()

	pool, err := connectDB(ctx)
	if err != nil {
		log.Fatalf("[db] connessione fallita: %v", err)
	}
	defer pool.Close()

	if err := initSchema(ctx, pool); err != nil {
		log.Fatalf("[db] inizializzazione schema fallita: %v", err)
	}
	if err := seedAdmin(ctx, pool); err != nil {
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

	// Healthcheck (usato anche da docker-compose / monitoraggio).
	mux.HandleFunc("GET /api/health", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	// --- AUTENTICAZIONE (solo per la pagina admin) ---

	// Login: restituisce un token JWT da usare come Bearer per aggiungere/eliminare ospedali.
	mux.HandleFunc("POST /api/auth/login", func(w http.ResponseWriter, r *http.Request) {
		var body struct{ Username, Password string }
		if !readJSON(w, r, &body) {
			return
		}
		if body.Username == "" || body.Password == "" {
			writeError(w, http.StatusBadRequest, "username e password richiesti")
			return
		}
		token, err := login(ctx, pool, body.Username, body.Password)
		if err != nil {
			log.Printf("[auth] errore login: %v\n", err)
			writeError(w, http.StatusInternalServerError, "errore interno")
			return
		}
		if token == "" {
			writeError(w, http.StatusUnauthorized, "Credenziali non valide")
			return
		}
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
		if err := createUser(ctx, pool, body.Username, body.Password); err != nil {
			log.Printf("[auth] errore creazione utente: %v\n", err)
			writeError(w, http.StatusInternalServerError, "errore interno")
			return
		}
		writeJSON(w, http.StatusCreated, map[string]bool{"ok": true})
	}))

	// --- OSPEDALI ---

	// Pubblica: i client (app AmbuTurni) scaricano l'elenco per popolare Lista
	// ospedali, senza bisogno di credenziali. ?citta= o ?regione= filtrano
	// (case-insensitive, match esatto; citta ha priorità se entrambi passati);
	// senza parametri restituisce tutto l'elenco.
	mux.HandleFunc("GET /api/ospedali", func(w http.ResponseWriter, r *http.Request) {
		citta := strings.TrimSpace(r.URL.Query().Get("citta"))
		regione := strings.TrimSpace(r.URL.Query().Get("regione"))
		lista, err := listOspedali(ctx, pool, citta, regione)
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
		lista, err := listCitta(ctx, pool)
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
		lista, err := listRegioni(ctx, pool)
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
		creato, err := createOspedale(ctx, pool, body.Nome, body.Via, body.Citta, body.Regione, body.Lat, body.Lng)
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
		aggiornato, err := updateOspedale(ctx, pool, r.PathValue("id"), body.Nome, body.Via, body.Citta, body.Regione, body.Lat, body.Lng)
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
		rimosso, err := deleteOspedale(ctx, pool, r.PathValue("id"))
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
		defer r.Body.Close()
		raw, err := io.ReadAll(r.Body)
		if err != nil {
			writeError(w, http.StatusBadRequest, "corpo della richiesta non valido")
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
		creati, aggiornati, scartati, err := upsertOspedali(ctx, pool, righe)
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
		lista, err := listFogli(ctx, pool)
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
		if !regexp.MustCompile(`^\d{4}-\d{2}$`).MatchString(body.Chiave) {
			writeError(w, http.StatusBadRequest, `chiave deve avere formato "aaaa-mm"`)
			return
		}
		salvato, err := upsertFoglio(ctx, pool, body.Chiave, body.Url)
		if err != nil {
			log.Printf("[fogli] errore salvataggio: %v\n", err)
			writeError(w, http.StatusInternalServerError, "errore interno")
			return
		}
		writeJSON(w, http.StatusOK, salvato)
	}))

	mux.HandleFunc("DELETE /api/fogli/{chiave}", authMiddleware(func(w http.ResponseWriter, r *http.Request) {
		rimosso, err := deleteFoglio(ctx, pool, r.PathValue("chiave"))
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

	// --- MATERIALI ---
	// Catalogo condiviso dei nomi materiali (Tools → Materiali usati): stesso
	// schema pubblico-lettura/admin-scrittura degli ospedali, usato dal
	// client per popolare il catalogo locale su un device nuovo.

	mux.HandleFunc("GET /api/materiali", func(w http.ResponseWriter, r *http.Request) {
		lista, err := listMateriali(ctx, pool)
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
		creato, err := createMateriale(ctx, pool, body.Nome)
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
		aggiornato, err := updateMateriale(ctx, pool, r.PathValue("id"), body.Nome)
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
		rimosso, err := deleteMateriale(ctx, pool, r.PathValue("id"))
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
		defer r.Body.Close()
		raw, err := io.ReadAll(r.Body)
		if err != nil {
			writeError(w, http.StatusBadRequest, "corpo della richiesta non valido")
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
		creati, aggiornati, scartati, err := upsertMateriali(ctx, pool, righe)
		if err != nil {
			log.Printf("[materiali] errore import: %v\n", err)
			writeError(w, http.StatusInternalServerError, "errore interno")
			return
		}
		writeJSON(w, http.StatusOK, map[string]int{
			"creati": creati, "aggiornati": aggiornati, "scartati": scartati,
		})
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
