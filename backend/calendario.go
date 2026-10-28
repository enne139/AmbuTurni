package main

import (
	"bytes"
	"compress/zlib"
	"encoding/base64"
	"io"
	"mime"
	"net/http"
	"regexp"
	"strings"
)

// Rimanda come text/calendar il file .ics che l'app web del Piano turni
// passa nell'indirizzo (parametro d: zlib + base64url, vedi
// urlCalendarioBackend in lib/utils/calendario_ics.dart), per i browser dei
// telefoni:
//   - iPhone/iPad: Safari propone "Aggiungi al calendario" soltanto per una
//     vera risposta HTTP con questo tipo — un download via Blob finisce in
//     File → Download senza importazione, e una navigazione a una data: URI
//     viene ignorata in silenzio (provato su device reale).
//   - Android: Chrome blocca i download automatici dopo il primo nella stessa
//     scheda, e l'app web non cambia mai pagina; aperto in una scheda nuova
//     (che Chrome chiude da sola) ogni download riparte da zero.
//
// GET e non POST: dalla web app aggiunta alla Home, iOS apre la finestra
// nuova in una vista Safari separata e il corpo di un POST va perso (la
// prima versione con un form POST mostrava lì una pagina di errore). Qui non
// si salva nulla.
//
// Pubblica come /api/ospedali: il contenuto è quello che il chiamante stesso
// ha appena inviato, senza alcun dato del server. Per non diventare un echo
// generico si accetta solo qualcosa che abbia la forma di un calendario, e
// nosniff impedisce al browser di interpretarlo come HTML.
func handleCalendarioEcho(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	ics, ok := decodificaIcs(q.Get("d"))
	if !ok {
		writeError(w, http.StatusBadRequest, "il contenuto non è un calendario .ics")
		return
	}
	nome := q.Get("nome")
	if !nomeIcsRe.MatchString(nome) {
		nome = "turni.ics"
	}
	// iOS vuole "inline" per mostrare "Aggiungi al calendario"; Android
	// (scarica=1) un vero download col nome giusto, che poi si apre dalla
	// notifica con l'app calendario.
	disposizione := "inline"
	if q.Get("scarica") == "1" {
		disposizione = "attachment"
	}
	w.Header().Set("Content-Type", "text/calendar; charset=utf-8")
	w.Header().Set("Content-Disposition", mime.FormatMediaType(disposizione, map[string]string{"filename": nome}))
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Cache-Control", "no-store")
	_, _ = w.Write([]byte(ics + "\r\n"))
}

// maxIcsParamLen: tetto sul parametro compresso, ben oltre quello che nginx
// lascia comunque passare (riga di richiesta da 8 KB) — solo una difesa in
// più se il backend gira da solo, senza nginx davanti.
const maxIcsParamLen = 64 << 10

// decodificaIcs inverte urlCalendarioBackend: base64url (padding tollerato)
// di un flusso zlib, poi la stessa forma minima di calendario richiesta
// prima. Il limite sul testo decompresso conta più di quello sul parametro:
// pochi KB compressi possono espandersi moltissimo.
func decodificaIcs(d string) (string, bool) {
	if d == "" || len(d) > maxIcsParamLen {
		return "", false
	}
	compresso, err := base64.RawURLEncoding.DecodeString(strings.TrimRight(d, "="))
	if err != nil {
		return "", false
	}
	zr, err := zlib.NewReader(bytes.NewReader(compresso))
	if err != nil {
		return "", false
	}
	defer zr.Close()
	dati, err := io.ReadAll(io.LimitReader(zr, maxBodyBytes+1))
	if err != nil || len(dati) > maxBodyBytes {
		return "", false
	}
	ics := strings.TrimSpace(string(dati))
	if !strings.HasPrefix(ics, "BEGIN:VCALENDAR") || !strings.HasSuffix(ics, "END:VCALENDAR") {
		return "", false
	}
	return ics, true
}

// Nome file generato dall'app (es. cvs_turni_2026_10.ics): niente di più
// libero, è solo un'etichetta.
var nomeIcsRe = regexp.MustCompile(`^[A-Za-z0-9_.-]{1,100}\.ics$`)
