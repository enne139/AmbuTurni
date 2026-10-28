package main

import (
	"context"
	"errors"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// MaterialeUsatoCondiviso: un materiale usato che un volontario ha scelto
// di condividere con tutti (interruttore "Condivisi" del tool Materiali
// usati), così chi ricarica il mezzo vede cosa manca anche se non l'ha
// usato lui. A differenza del resto del backend è scritto dall'APP, non
// dalla pagina admin: lettura e scrittura richiedono il login utente-app
// (contentAuthMiddleware), e l'autore viene sempre dal token, mai dal body.
//
// Il materiale è salvato per NOME, non per id: i cataloghi locali dei
// device hanno id diversi tra loro (si allineano solo per nome, vedi
// upsertMateriali lato client), e un nome creato al volo da un volontario
// non è detto che esista nel catalogo condiviso.
type MaterialeUsatoCondiviso struct {
	ID        string    `json:"id"`
	Materiale string    `json:"materiale"`
	Quantita  int       `json:"quantita"`
	Unita     *string   `json:"unita"`
	Posizione *string   `json:"posizione"`
	Mezzo     *string   `json:"mezzo"`
	Note      *string   `json:"note"`
	CreatoDa  string    `json:"creatoDa"`
	CreatedAt time.Time `json:"createdAt"`
	UpdatedAt time.Time `json:"updatedAt"`
}

// MaterialeUsatoCondivisoInput: i campi modificabili (creazione e modifica
// da form). Autore, id e date non sono mai accettati dal client.
type MaterialeUsatoCondivisoInput struct {
	Materiale string  `json:"materiale"`
	Quantita  int     `json:"quantita"`
	Unita     *string `json:"unita"`
	Posizione *string `json:"posizione"`
	Mezzo     *string `json:"mezzo"`
	Note      *string `json:"note"`
}

// Stessi valori del CHECK sulla tabella locale materiali_usati dell'app
// (posizioniMateriale in lib/db/models.dart).
var posizioniMateriale = map[string]bool{"AMBULANZA": true, "BOMBOLINO": true, "ZAINO": true}

// Limiti di lunghezza: qui scrive qualunque utente-app, non solo un admin
// fidato — un tetto per campo evita righe enormi mostrate a tutti.
const (
	maxLunghezzaNomeMateriale = 200
	maxLunghezzaNoteMateriale = 2000
)

// errMaterialeCondivisoNonValido: input rifiutato (400), distinto da un
// errore interno — stesso ruolo di errBackupNonValido.
type errMaterialeCondivisoNonValido struct{ motivo string }

func (e errMaterialeCondivisoNonValido) Error() string { return e.motivo }

// testoOpzionale: trim, stringa vuota → nil (il client manda "" per
// svuotare un campo, la colonna resta NULL come per i campi mai compilati).
func testoOpzionale(s *string) *string {
	if s == nil {
		return nil
	}
	t := strings.TrimSpace(*s)
	if t == "" {
		return nil
	}
	return &t
}

// normalizza valida l'input e restituisce la versione pulita da scrivere.
func (in MaterialeUsatoCondivisoInput) normalizza() (MaterialeUsatoCondivisoInput, error) {
	out := MaterialeUsatoCondivisoInput{
		Materiale: strings.TrimSpace(in.Materiale),
		Quantita:  in.Quantita,
		Unita:     testoOpzionale(in.Unita),
		Posizione: testoOpzionale(in.Posizione),
		Mezzo:     testoOpzionale(in.Mezzo),
		Note:      testoOpzionale(in.Note),
	}
	if out.Materiale == "" {
		return out, errMaterialeCondivisoNonValido{"materiale richiesto"}
	}
	if utf8.RuneCountInString(out.Materiale) > maxLunghezzaNomeMateriale ||
		(out.Unita != nil && utf8.RuneCountInString(*out.Unita) > maxLunghezzaNomeMateriale) {
		return out, errMaterialeCondivisoNonValido{"testo troppo lungo"}
	}
	if out.Note != nil && utf8.RuneCountInString(*out.Note) > maxLunghezzaNoteMateriale {
		return out, errMaterialeCondivisoNonValido{"note troppo lunghe"}
	}
	if out.Quantita < 1 {
		return out, errMaterialeCondivisoNonValido{"quantità non valida (minimo 1)"}
	}
	if out.Posizione != nil {
		p := strings.ToUpper(*out.Posizione)
		if !posizioniMateriale[p] {
			return out, errMaterialeCondivisoNonValido{"posizione non valida"}
		}
		out.Posizione = &p
	}
	// Il mezzo non è una FK verso la tabella mezzi: un mezzo eliminato dalla
	// pagina admin non deve far sparire (o rendere invalidi) i materiali già
	// segnalati su di lui. Si controlla solo il formato a due cifre.
	if out.Mezzo != nil && !nomeMezzoValido(*out.Mezzo) {
		return out, errMaterialeCondivisoNonValido{"mezzo non valido (atteso un numero a due cifre)"}
	}
	return out, nil
}

const colonneMaterialeCondiviso = `id, materiale, quantita, unita, posizione, mezzo, note, creato_da, created_at, updated_at`

func scanMaterialeCondiviso(row pgx.Row) (MaterialeUsatoCondiviso, error) {
	var m MaterialeUsatoCondiviso
	err := row.Scan(&m.ID, &m.Materiale, &m.Quantita, &m.Unita, &m.Posizione, &m.Mezzo,
		&m.Note, &m.CreatoDa, &m.CreatedAt, &m.UpdatedAt)
	return m, err
}

// listMaterialiCondivisi: tutti, dal più recente. Nessun filtro per mezzo
// lato server: la lista è piccola (solo ciò che manca adesso, le righe
// spariscono al ripristino) e il client la filtra già in memoria, stessa
// scelta della ricerca nell'Archivio comunicati.
func listMaterialiCondivisi(ctx context.Context, pool *pgxpool.Pool) ([]MaterialeUsatoCondiviso, error) {
	rows, err := pool.Query(ctx,
		"SELECT "+colonneMaterialeCondiviso+" FROM materiali_usati_condivisi ORDER BY created_at DESC")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	lista := []MaterialeUsatoCondiviso{}
	for rows.Next() {
		m, err := scanMaterialeCondiviso(rows)
		if err != nil {
			return nil, err
		}
		lista = append(lista, m)
	}
	return lista, rows.Err()
}

func createMaterialeCondiviso(ctx context.Context, pool *pgxpool.Pool, in MaterialeUsatoCondivisoInput, creatoDa string) (MaterialeUsatoCondiviso, error) {
	return scanMaterialeCondiviso(pool.QueryRow(ctx,
		`INSERT INTO materiali_usati_condivisi (id, materiale, quantita, unita, posizione, mezzo, note, creato_da)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		 RETURNING `+colonneMaterialeCondiviso,
		uuid.NewString(), in.Materiale, in.Quantita, in.Unita, in.Posizione, in.Mezzo, in.Note, creatoDa,
	))
}

// updateMaterialeCondiviso: modifica dal form, sovrascrive tutti i campi
// modificabili (non l'autore: chi corregge un errore altrui non diventa il
// "proprietario" della segnalazione). pgx.ErrNoRows se la riga non esiste
// più — tipicamente già ripristinata da un altro volontario.
func updateMaterialeCondiviso(ctx context.Context, pool *pgxpool.Pool, id string, in MaterialeUsatoCondivisoInput) (MaterialeUsatoCondiviso, error) {
	return scanMaterialeCondiviso(pool.QueryRow(ctx,
		`UPDATE materiali_usati_condivisi
		 SET materiale = $1, quantita = $2, unita = $3, posizione = $4, mezzo = $5, note = $6, updated_at = now()
		 WHERE id = $7
		 RETURNING `+colonneMaterialeCondiviso,
		in.Materiale, in.Quantita, in.Unita, in.Posizione, in.Mezzo, in.Note, id,
	))
}

// variaQuantitaMaterialeCondiviso applica un DELTA (i pulsanti +/- della
// lista), non un valore assoluto: due volontari che premono "+" insieme
// sullo stesso materiale devono sommare entrambi i tocchi, mentre con un
// valore assoluto l'ultimo a scrivere cancellerebbe l'altro. Il minimo 1
// è applicato nella stessa UPDATE (GREATEST), atomica rispetto ad altre
// variazioni concorrenti.
func variaQuantitaMaterialeCondiviso(ctx context.Context, pool *pgxpool.Pool, id string, delta int) (MaterialeUsatoCondiviso, error) {
	return scanMaterialeCondiviso(pool.QueryRow(ctx,
		`UPDATE materiali_usati_condivisi
		 SET quantita = GREATEST(1, quantita + $1), updated_at = now()
		 WHERE id = $2
		 RETURNING `+colonneMaterialeCondiviso,
		delta, id,
	))
}

// ripristinaMaterialiCondivisi elimina esattamente gli id ricevuti (il
// ripristino non tiene storico, come in locale). Per id e non per mezzo
// apposta: "Ripristina tutto" deve togliere solo ciò che il volontario
// aveva davanti, non una riga aggiunta da un altro un attimo prima e mai
// vista. Restituisce quante righe esistevano ancora.
func ripristinaMaterialiCondivisi(ctx context.Context, pool *pgxpool.Pool, ids []string) (int64, error) {
	if len(ids) == 0 {
		return 0, nil
	}
	tag, err := pool.Exec(ctx, "DELETE FROM materiali_usati_condivisi WHERE id = ANY($1)", ids)
	if err != nil {
		return 0, err
	}
	return tag.RowsAffected(), nil
}

// isNonValido: true se err è un rifiuto dell'input (→ 400).
func isNonValido(err error) bool {
	var e errMaterialeCondivisoNonValido
	return errors.As(err, &e)
}
