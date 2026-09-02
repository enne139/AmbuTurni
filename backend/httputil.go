package main

import (
	"encoding/json"
	"io"
	"net"
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

// maxBodyBytes limita la dimensione di qualunque body accettato dall'API,
// incluso l'endpoint di login (non autenticato): senza un limite, un body
// enorme viene comunque bufferizzato/parsato per intero da json.Decode prima
// di fallire, un DoS a bassissimo costo che non richiede alcuna credenziale.
// 1 MiB è ampio rispetto al payload più grande atteso (import massivo di
// ospedali/materiali da file: centinaia di righe di testo breve).
const maxBodyBytes = 1 << 20

// readJSON decodifica il body JSON in v; scrive già la risposta 400 e
// restituisce false se il body non è JSON valido o supera maxBodyBytes (i
// chiamanti ritornano subito in quel caso).
func readJSON(w http.ResponseWriter, r *http.Request, v any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, maxBodyBytes)
	defer r.Body.Close()
	if err := json.NewDecoder(r.Body).Decode(v); err != nil {
		writeError(w, http.StatusBadRequest, "corpo della richiesta non valido o troppo grande")
		return false
	}
	return true
}

// maxImportBodyBytes: limite più ampio per gli endpoint di import massivo
// (ospedali/materiali da file JSON), che possono legittimamente contenere
// centinaia di righe — comunque un tetto, non un via libera.
const maxImportBodyBytes = 10 << 20

// maxComunicatoBytes: limite del corpo multipart di POST /api/comunicati
// (titolo + descrizione + PDF). 20 MiB è ampio per un PDF di comunicato
// associativo, comunque un tetto contro un upload sproporzionato — i PDF
// finiscono in una colonna bytea di Postgres (vedi CLAUDE.md), non su disco.
const maxComunicatoBytes = 20 << 20

// readBodyLimited legge l'intero body limitandone la dimensione; scrive già
// la risposta 400 e restituisce ok=false se la lettura fallisce (corpo
// malformato o oltre il limite).
func readBodyLimited(w http.ResponseWriter, r *http.Request, limit int64) (raw []byte, ok bool) {
	r.Body = http.MaxBytesReader(w, r.Body, limit)
	defer r.Body.Close()
	raw, err := io.ReadAll(r.Body)
	if err != nil {
		writeError(w, http.StatusBadRequest, "corpo della richiesta non valido o troppo grande")
		return nil, false
	}
	return raw, true
}

// clientIP risolve l'indirizzo del chiamante per il rate limit del login:
// X-Real-IP (impostato da nginx.conf in produzione) ha priorità, altrimenti
// si usa r.RemoteAddr — il caso del backend testato standalone (go run/docker
// compose) senza nginx davanti.
func clientIP(r *http.Request) string {
	if ip := r.Header.Get("X-Real-IP"); ip != "" {
		return ip
	}
	if ip, _, err := net.SplitHostPort(r.RemoteAddr); err == nil {
		return ip
	}
	return r.RemoteAddr
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
