// Bootstrap del server: auth, API ospedali e pagina admin statica.
package main

import (
	"context"
	"log"
	"net/http"
	"strings"
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
	// ospedali, senza bisogno di credenziali. ?citta= filtra (case-insensitive,
	// match esatto); senza il parametro restituisce tutto l'elenco.
	mux.HandleFunc("GET /api/ospedali", func(w http.ResponseWriter, r *http.Request) {
		citta := strings.TrimSpace(r.URL.Query().Get("citta"))
		lista, err := listOspedali(ctx, pool, citta)
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

	// Protette: solo dalla pagina admin, dopo login.
	mux.HandleFunc("POST /api/ospedali", authMiddleware(func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			Nome  string   `json:"nome"`
			Via   *string  `json:"via"`
			Citta *string  `json:"citta"`
			Lat   *float64 `json:"lat"`
			Lng   *float64 `json:"lng"`
		}
		if !readJSON(w, r, &body) {
			return
		}
		body.Nome = strings.TrimSpace(body.Nome)
		if body.Nome == "" {
			writeError(w, http.StatusBadRequest, "nome richiesto")
			return
		}
		creato, err := createOspedale(ctx, pool, body.Nome, body.Via, body.Citta, body.Lat, body.Lng)
		if err != nil {
			log.Printf("[ospedali] errore creazione: %v\n", err)
			writeError(w, http.StatusInternalServerError, "errore interno")
			return
		}
		writeJSON(w, http.StatusCreated, creato)
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
