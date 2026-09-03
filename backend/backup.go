package main

import (
	"archive/zip"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// BackupCompleto è il formato dei metadati del backup/ripristino completo
// "con un click" della pagina admin — ospedali, fogli turni, materiali, il
// link di formazione, gli account utente-app e i comunicati. Richiesta
// esplicita dell'utente (2026-09-03): ospedali/fogli/materiali avevano già
// l'export/import a parte (2026-07-20) ma comunicati/utenti-app/formazione
// ne erano rimasti privi — un vero disaster-recovery deve coprire tutto,
// non solo l'anagrafica leggera, con un solo file invece di sei azioni.
//
// Il backup vero è uno ZIP (data.json + un file comunicati/<id>.pdf per
// comunicato), non un unico JSON con i PDF in base64: suggerimento
// dell'utente sulla prima versione, corretto — il base64 gonfia i byte del
// ~33%, e un archivio compresso è il formato naturale per un mix di testo
// e binari. Questo struct rappresenta solo il contenuto di data.json,
// quindi ComunicatoBackupMeta (sotto) non include mai i byte del PDF.
type BackupCompleto struct {
	Versione             int                    `json:"versione"`
	EsportatoIl          time.Time              `json:"esportatoIl"`
	Ospedali             []OspedaleInput        `json:"ospedali"`
	Fogli                []FoglioInput          `json:"fogli"`
	Materiali            []MaterialeInput       `json:"materiali"`
	RepositoryFormazione *string                `json:"repositoryFormazione"`
	UtentiApp            []UtenteAppBackup      `json:"utentiApp"`
	Comunicati           []ComunicatoBackupMeta `json:"comunicati"`
}

// ComunicatoBackupMeta è la riga comunicato dentro data.json: SOLO
// metadati — il PDF vive come file a parte nello zip, al percorso fisso
// restituito da percorsoZipComunicato(ID) (nessun campo url/path separato,
// l'id è già univoco e si presta da solo come nome file).
type ComunicatoBackupMeta struct {
	ID          string  `json:"id"`
	FileName    string  `json:"fileName"`
	Titolo      *string `json:"titolo"`
	Descrizione *string `json:"descrizione"`
}

func percorsoZipComunicato(id string) string {
	return "comunicati/" + id + ".pdf"
}

// RiepilogoRipristino conta creati/aggiornati/scartati per ciascuna
// sezione — stesso pattern già in uso per gli import massivi per-categoria,
// qui una volta per sezione invece di un totale unico: un ripristino tocca
// sei tabelle diverse, un totale solo nasconderebbe quale sezione ha
// eventualmente scartato delle righe.
type RiepilogoRipristino struct {
	Ospedali             ConteggioSezione `json:"ospedali"`
	Fogli                ConteggioSezione `json:"fogli"`
	Materiali            ConteggioSezione `json:"materiali"`
	FormazioneAggiornata bool             `json:"formazioneAggiornata"`
	UtentiApp            ConteggioSezione `json:"utentiApp"`
	Comunicati           ConteggioSezione `json:"comunicati"`
}

type ConteggioSezione struct {
	Creati     int `json:"creati"`
	Aggiornati int `json:"aggiornati"`
	Scartati   int `json:"scartati"`
}

// errBackupNonValido distingue, nella risposta HTTP, "il file caricato non
// è un backup riconoscibile" (colpa del chiamante, 400) da un vero errore
// interno (500) — stesso ruolo di errPasswordAttualeErrata in utenti_app.go.
var errBackupNonValido = errors.New("file non valido: non è un backup ZIP riconosciuto (manca data.json)")

// costruisciBackup legge tutte le tabelle condivise (PDF dei comunicati
// inclusi) in un colpo solo — un vero snapshot coerente (stesso momento
// per tutte le sezioni) — PRIMA di scrivere qualunque byte sulla risposta
// HTTP: se una query fallisce, il chiamante può ancora rispondere con uno
// status di errore pulito, cosa che scriviBackupZip non potrebbe più fare
// una volta iniziato lo streaming dello zip.
func costruisciBackup(ctx context.Context, pool *pgxpool.Pool) (BackupCompleto, []ComunicatoBackup, error) {
	b := BackupCompleto{Versione: 1, EsportatoIl: time.Now().UTC()}

	ospedali, err := listOspedali(ctx, pool, "", "")
	if err != nil {
		return b, nil, err
	}
	b.Ospedali = make([]OspedaleInput, 0, len(ospedali))
	for _, o := range ospedali {
		b.Ospedali = append(b.Ospedali, OspedaleInput{
			Nome: o.Nome, Via: o.Via, Citta: o.Citta, Lat: o.Lat, Lng: o.Lng, Regione: o.Regione,
		})
	}

	fogli, err := listFogli(ctx, pool)
	if err != nil {
		return b, nil, err
	}
	b.Fogli = make([]FoglioInput, 0, len(fogli))
	for _, f := range fogli {
		b.Fogli = append(b.Fogli, FoglioInput{Chiave: f.Chiave, Url: f.Url})
	}

	materiali, err := listMateriali(ctx, pool)
	if err != nil {
		return b, nil, err
	}
	b.Materiali = make([]MaterialeInput, 0, len(materiali))
	for _, m := range materiali {
		b.Materiali = append(b.Materiali, MaterialeInput{Nome: m.Nome})
	}

	rf, err := getRepositoryFormazione(ctx, pool)
	if err != nil {
		return b, nil, err
	}
	if rf.Url != "" {
		b.RepositoryFormazione = &rf.Url
	}

	utenti, err := listUtentiAppConHash(ctx, pool)
	if err != nil {
		return b, nil, err
	}
	b.UtentiApp = utenti

	comunicati, err := listComunicatiConFile(ctx, pool)
	if err != nil {
		return b, nil, err
	}
	b.Comunicati = make([]ComunicatoBackupMeta, 0, len(comunicati))
	for _, c := range comunicati {
		b.Comunicati = append(b.Comunicati, ComunicatoBackupMeta{
			ID: c.ID, FileName: c.FileName, Titolo: c.Titolo, Descrizione: c.Descrizione,
		})
	}

	return b, comunicati, nil
}

// scriviBackupZip scrive lo zip (data.json + comunicati/<id>.pdf) su [w] —
// scrittura diretta sulla risposta HTTP, niente buffer intermedio per
// l'intero archivio: più efficiente per un backup che può includere decine
// di MB di PDF. archive/zip supporta nativamente uno io.Writer non-seekable
// come http.ResponseWriter (usa i data descriptor del formato zip).
func scriviBackupZip(w io.Writer, meta BackupCompleto, comunicati []ComunicatoBackup) error {
	zw := zip.NewWriter(w)

	dataEntry, err := zw.Create("data.json")
	if err != nil {
		return err
	}
	enc := json.NewEncoder(dataEntry)
	enc.SetIndent("", "  ")
	if err := enc.Encode(meta); err != nil {
		return err
	}

	for _, c := range comunicati {
		entry, err := zw.Create(percorsoZipComunicato(c.ID))
		if err != nil {
			return err
		}
		if _, err := entry.Write(c.FileData); err != nil {
			return err
		}
	}

	return zw.Close()
}

// ripristinaBackup legge uno zip prodotto da scriviBackupZip ([]byte, già
// interamente in memoria: archive/zip.NewReader vuole un io.ReaderAt, non
// accetta uno stream) e applica ogni sezione come upsert — MAI una
// sostituzione distruttiva, stessa filosofia "niente cancellazioni
// automatiche" già seguita da upsertOspedali/upsertFogli/upsertMateriali:
// un dato non presente nel file semplicemente non viene toccato, non
// rimosso. Le sei sezioni restano indipendenti (ognuna ha già la propria
// transazione dentro il rispettivo upsert*/set*): se una fallisce dopo che
// altre sono già state applicate, quelle restano — un ripristino parziale
// riuscito è comunque meglio di uno scartato per intero per un errore in
// una sola sezione.
func ripristinaBackup(ctx context.Context, pool *pgxpool.Pool, raw []byte) (RiepilogoRipristino, error) {
	var r RiepilogoRipristino

	zr, err := zip.NewReader(bytes.NewReader(raw), int64(len(raw)))
	if err != nil {
		return r, errBackupNonValido
	}

	var meta BackupCompleto
	trovatoData := false
	pdf := map[string][]byte{} // id -> byte del PDF, dalle voci comunicati/<id>.pdf

	for _, f := range zr.File {
		switch {
		case f.Name == "data.json":
			rc, err := f.Open()
			if err != nil {
				return r, err
			}
			err = json.NewDecoder(rc).Decode(&meta)
			rc.Close()
			if err != nil {
				return r, errBackupNonValido
			}
			trovatoData = true
		case strings.HasPrefix(f.Name, "comunicati/") && strings.HasSuffix(f.Name, ".pdf"):
			id := strings.TrimSuffix(strings.TrimPrefix(f.Name, "comunicati/"), ".pdf")
			rc, err := f.Open()
			if err != nil {
				return r, err
			}
			data, err := io.ReadAll(rc)
			rc.Close()
			if err != nil {
				return r, err
			}
			pdf[id] = data
		}
	}
	if !trovatoData {
		return r, errBackupNonValido
	}

	co, ao, so, err := upsertOspedali(ctx, pool, meta.Ospedali)
	if err != nil {
		return r, err
	}
	r.Ospedali = ConteggioSezione{co, ao, so}

	cf, af, sf, err := upsertFogli(ctx, pool, meta.Fogli)
	if err != nil {
		return r, err
	}
	r.Fogli = ConteggioSezione{cf, af, sf}

	cm, am, sm, err := upsertMateriali(ctx, pool, meta.Materiali)
	if err != nil {
		return r, err
	}
	r.Materiali = ConteggioSezione{cm, am, sm}

	// Nessun URL nel backup (mai impostato sull'istanza di origine): non
	// tocca il valore già presente qui, coerente con "niente cancellazioni".
	if meta.RepositoryFormazione != nil {
		if url := strings.TrimSpace(*meta.RepositoryFormazione); url != "" {
			if _, err := setRepositoryFormazione(ctx, pool, url); err != nil {
				return r, err
			}
			r.FormazioneAggiornata = true
		}
	}

	cu, au, su, err := upsertUtentiAppConHash(ctx, pool, meta.UtentiApp)
	if err != nil {
		return r, err
	}
	r.UtentiApp = ConteggioSezione{cu, au, su}

	comunicati := make([]ComunicatoBackup, 0, len(meta.Comunicati))
	for _, cm := range meta.Comunicati {
		comunicati = append(comunicati, ComunicatoBackup{
			ID: cm.ID, FileName: cm.FileName, Titolo: cm.Titolo, Descrizione: cm.Descrizione,
			FileData: pdf[cm.ID], // nil (quindi scartato dalla validazione %PDF) se la voce manca nello zip
		})
	}
	cc, ac, sc, err := upsertComunicatiConFile(ctx, pool, comunicati)
	if err != nil {
		return r, err
	}
	r.Comunicati = ConteggioSezione{cc, ac, sc}

	return r, nil
}
