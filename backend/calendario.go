package main

import (
	"mime"
	"net/http"
	"regexp"
	"strings"
)

// Rimanda indietro come text/calendar il file .ics generato dall'app web del
// Piano turni, per i browser dei telefoni:
//   - iPhone/iPad: Safari propone "Aggiungi al calendario" soltanto per una
//     vera risposta HTTP con questo tipo — un download via Blob finisce in
//     File → Download senza importazione, e una navigazione a una data: URI
//     viene ignorata in silenzio (provato su device reale).
//   - Android: Chrome blocca i download automatici dopo il primo nella stessa
//     scheda, e l'app web non cambia mai pagina; aperto in una scheda nuova
//     (che Chrome chiude da sola) ogni download riparte da zero.
// L'app invia il file con un form POST (navigazione vera, nessun limite di
// lunghezza come in una query string), qui non si salva nulla.
//
// Pubblica come /api/ospedali: il contenuto è quello che il chiamante stesso
// ha appena inviato, senza alcun dato del server. Per non diventare un echo
// generico si accetta solo qualcosa che abbia la forma di un calendario, e
// nosniff impedisce al browser di interpretarlo come HTML.
func handleCalendarioEcho(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, maxBodyBytes)
	if err := r.ParseForm(); err != nil {
		writeError(w, http.StatusBadRequest, "richiesta non valida")
		return
	}
	ics := strings.TrimSpace(r.PostForm.Get("ics"))
	if !strings.HasPrefix(ics, "BEGIN:VCALENDAR") || !strings.HasSuffix(ics, "END:VCALENDAR") {
		writeError(w, http.StatusBadRequest, "il contenuto non è un calendario .ics")
		return
	}
	nome := r.PostForm.Get("nome")
	if !nomeIcsRe.MatchString(nome) {
		nome = "turni.ics"
	}
	// iOS vuole "inline" per mostrare "Aggiungi al calendario"; Android
	// (scarica=1) un vero download col nome giusto, che poi si apre dalla
	// notifica con l'app calendario.
	disposizione := "inline"
	if r.PostForm.Get("scarica") == "1" {
		disposizione = "attachment"
	}
	w.Header().Set("Content-Type", "text/calendar; charset=utf-8")
	w.Header().Set("Content-Disposition", mime.FormatMediaType(disposizione, map[string]string{"filename": nome}))
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Cache-Control", "no-store")
	_, _ = w.Write([]byte(ics + "\r\n"))
}

// Nome file generato dall'app (es. cvs_turni_2026_10.ics): niente di più
// libero, è solo un'etichetta.
var nomeIcsRe = regexp.MustCompile(`^[A-Za-z0-9_.-]{1,100}\.ics$`)
