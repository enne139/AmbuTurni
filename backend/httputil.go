package main

import (
	"encoding/json"
	"net/http"
	"os"
)

// envOr legge una variabile d'ambiente con un default se assente/vuota.
func envOr(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

// readJSON decodifica il body JSON in v; scrive già la risposta 400 e
// restituisce false se il body non è JSON valido (i chiamanti ritornano
// subito in quel caso).
func readJSON(w http.ResponseWriter, r *http.Request, v any) bool {
	defer r.Body.Close()
	if err := json.NewDecoder(r.Body).Decode(v); err != nil {
		writeError(w, http.StatusBadRequest, "corpo della richiesta non valido")
		return false
	}
	return true
}

// corsMiddleware: l'app (web/native) chiama il backend da un'origine diversa.
// Dati pubblici in lettura (l'unica scrittura, /ospedali POST/DELETE, è
// comunque protetta da JWT), quindi un Allow-Origin permissivo è accettabile.
func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}
