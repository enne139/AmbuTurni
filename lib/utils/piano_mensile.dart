// Parser del "piano turni" mensile dell'associazione: legge l'XLSX esportato
// dal foglio Google della pianificazione e ne estrae, per ogni giorno, gli
// slot di equipaggio (assegnati e buchi). Replica la logica del tool HTML
// preesistente basato su SheetJS — stessa struttura del foglio, stessi casi.
//
// Struttura attesa del foglio (una scheda per giorno):
// - schede "LUN 1", "MAR 2", ... eventualmente "GIO DIURNO 5": contano il
//   prefisso col giorno della settimana e il numero finale (giorno del mese);
//   "DIURNO" nel nome cambia i default di fascia e gli slot del centralino.
// - B2 della prima scheda: data di inizio mese (determina mese/anno).
// - Dalla riga 6 in giù, blocchi riconosciuti dalla colonna A:
//   * H12/H24/ASSISTENZA/GETTONE: 4 righe di ruoli (Autista, Cs, Terzo,
//     Quarto, a partire dalla riga del titolo); la fascia oraria è nel testo
//     in colonna A della seconda riga (MATT/POM/SER/NOT), default mattina se
//     scheda diurna altrimenti sera. Un blocco ASSISTENZA/GETTONE senza
//     descrizione né nomi è un template inutilizzato e viene ignorato.
//   * CENTRALINO: 2 slot (mattina+pomeriggio) se diurno, 1 (sera) altrimenti;
//     l'orario è nella riga sotto il titolo (diurno: i due intervalli
//     mattina/pomeriggio separati da "/", es. "8:30 - 13:30/13:30 - 18:30").
//   * USCITA MEZZI: blocco fisso da saltare (6 righe).
// - Colonna B su ogni riga: solo l'etichetta del ruolo (Autista/Cs/Terzo/
//   Quarto), non letta — il ruolo si ricava dalla posizione della riga.
// - Colonna C: chi è di turno (titolare); colonna D: possibili sostituti.
//   Entrambe vuote = buco.
//
// Nessun import Flutter: il file resta Dart puro, così è unit-testabile e
// parsePianoMensile può girare in un isolate via compute() (il decode di un
// XLSX con ~30 schede bloccherebbe la UI per centinaia di ms).
import 'package:excel/excel.dart';

/// Ruoli dell'equipaggio, nell'ordine delle righe del blocco nel foglio.
enum RuoloPiano {
  autista('Autista', 'AU'),
  cs('Cs', 'CS'),
  terzo('Terzo', 'TE'),
  quarto('Quarto', 'QU'),
  centralino('Centralino', 'CE');

  final String etichetta;
  final String sigla;
  const RuoloPiano(this.etichetta, this.sigla);
}

/// Fascia oraria di uno slot (nel foglio: MATT/POM/SER/NOT).
enum FasciaPiano {
  mattina('Mattina'),
  pomeriggio('Pomeriggio'),
  sera('Sera'),
  notte('Notte');

  final String etichetta;
  const FasciaPiano(this.etichetta);
}

/// Un singolo slot del piano: un ruolo, in una fascia, in un giorno.
/// [titolare] (colonna C) e [sostituti] (colonna D) restano separati perché
/// nel foglio hanno significati diversi: chi è di turno e chi può subentrare.
/// Buco = entrambe le colonne vuote (stessa regola del tool HTML: un giorno
/// con solo un sostituto non è considerato scoperto).
class SlotPiano {
  final int giorno;
  /// Progressivo del blocco all'interno del giorno: due blocchi con stessa
  /// macro e fascia (es. due ambulanze H12 al mattino) restano equipaggi
  /// distinti nel dettaglio, invece di mescolare i ruoli.
  final int blocco;
  final String macro; // H12 / H24 / ASSISTENZA / GETTONE
  final RuoloPiano ruolo;
  final FasciaPiano fascia;
  final String titolare;
  final String sostituti;
  /// Orario del blocco come compare nella colonna info del foglio (terza riga,
  /// es. "18:30 - 23:30"); vuoto se assente. Testo grezzo, non interpretato:
  /// serve per la visualizzazione e per [orarioParsed].
  final String orario;

  const SlotPiano({
    required this.giorno,
    required this.blocco,
    required this.macro,
    required this.ruolo,
    required this.fascia,
    required this.titolare,
    required this.sostituti,
    this.orario = '',
  });

  bool get buco => titolare.isEmpty && sostituti.isEmpty;
  bool get assistenza => macro == 'ASSISTENZA' || macro == 'GETTONE';

  /// Serializzazione per la cache locale del Piano turni (JSON su file):
  /// riaprire un mese già scaricato non deve costare un nuovo download e
  /// una nuova decodifica dell'XLSX.
  Map<String, dynamic> toMap() => {
        'giorno': giorno,
        'blocco': blocco,
        'macro': macro,
        'ruolo': ruolo.name,
        'fascia': fascia.name,
        'titolare': titolare,
        'sostituti': sostituti,
        'orario': orario,
      };

  /// Inverso di [toMap]. Un valore inatteso (es. ruolo di una versione
  /// futura) fa lanciare: chi legge la cache tratta l'errore come cache
  /// assente e riscarica.
  factory SlotPiano.fromMap(Map<String, dynamic> map) => SlotPiano(
        giorno: map['giorno'] as int,
        blocco: map['blocco'] as int,
        macro: map['macro'] as String,
        ruolo: RuoloPiano.values.byName(map['ruolo'] as String),
        fascia: FasciaPiano.values.byName(map['fascia'] as String),
        titolare: map['titolare'] as String? ?? '',
        sostituti: map['sostituti'] as String? ?? '',
        orario: map['orario'] as String? ?? '',
      );

  /// Ore/minuti di inizio e fine estratti da [orario], null se il testo non
  /// contiene un intervallo riconoscibile. Accetta ":" o "." come separatore
  /// (nei fogli compaiono entrambi) e il trattino lungo di Google Sheets.
  ({int oraInizio, int minInizio, int oraFine, int minFine})? get orarioParsed {
    final m = RegExp(r'(\d{1,2})[:.](\d{2})\s*[-–]\s*(\d{1,2})[:.](\d{2})')
        .firstMatch(orario);
    if (m == null) return null;
    final valori = [for (var i = 1; i <= 4; i++) int.parse(m.group(i)!)];
    if (valori[0] > 23 || valori[2] > 23 || valori[1] > 59 || valori[3] > 59) {
      return null;
    }
    return (
      oraInizio: valori[0],
      minInizio: valori[1],
      oraFine: valori[2],
      minFine: valori[3],
    );
  }
}

/// Piano turni di un mese: slot raggruppati per giorno.
class PianoMensile {
  final int anno;
  final int mese; // 1..12
  final Map<int, List<SlotPiano>> _perGiorno;

  PianoMensile({required this.anno, required this.mese, required List<SlotPiano> slots})
      : _perGiorno = _raggruppaPerGiorno(slots);

  static Map<int, List<SlotPiano>> _raggruppaPerGiorno(List<SlotPiano> slots) {
    final mappa = <int, List<SlotPiano>>{};
    for (final s in slots) {
      mappa.putIfAbsent(s.giorno, () => []).add(s);
    }
    return mappa;
  }

  int get giorniNelMese => DateTime(anno, mese + 1, 0).day;

  /// Serializzazione per la cache locale (vedi SlotPiano.toMap). Gli slot
  /// escono raggruppati per giorno nell'ordine originale: il roundtrip
  /// preserva blocchi e sequenze del foglio.
  Map<String, dynamic> toMap() {
    final giorni = _perGiorno.keys.toList()..sort();
    return {
      'anno': anno,
      'mese': mese,
      'slots': [
        for (final g in giorni)
          for (final s in _perGiorno[g]!) s.toMap(),
      ],
    };
  }

  factory PianoMensile.fromMap(Map<String, dynamic> map) => PianoMensile(
        anno: map['anno'] as int,
        mese: map['mese'] as int,
        slots: [
          for (final s in map['slots'] as List)
            SlotPiano.fromMap(Map<String, dynamic>.from(s as Map)),
        ],
      );

  /// Slot del giorno nell'ordine del foglio, lista vuota se il giorno non ha
  /// una scheda (o non ha blocchi riconosciuti).
  List<SlotPiano> delGiorno(int giorno) => _perGiorno[giorno] ?? const [];

  /// Buchi del giorno, ignorando i ruoli in [ruoliEsclusi] (es. il Quarto,
  /// spesso scoperto per scelta e non un vero buco da coprire).
  List<SlotPiano> buchiDelGiorno(int giorno, {Set<RuoloPiano> ruoliEsclusi = const {}}) =>
      delGiorno(giorno)
          .where((s) => s.buco && !ruoliEsclusi.contains(s.ruolo))
          .toList();

  /// Inizio e fine assoluti di uno slot, combinando il giorno del piano con
  /// l'orario del blocco; null se lo slot non ha un orario riconoscibile.
  /// Un turno a cavallo di mezzanotte (fine <= inizio, es. "23:30 - 7:00")
  /// termina il giorno dopo — DateTime gestisce da sé il cambio di mese/anno.
  (DateTime, DateTime)? intervalloEvento(SlotPiano slot) {
    final orario = slot.orarioParsed;
    if (orario == null) return null;
    final inizio =
        DateTime(anno, mese, slot.giorno, orario.oraInizio, orario.minInizio);
    var fine =
        DateTime(anno, mese, slot.giorno, orario.oraFine, orario.minFine);
    // Giorno+1 via costruttore (non add(Duration)): DateTime normalizza il
    // fine mese da sé e l'orario resta quello "da orologio" anche nelle
    // notti di cambio ora legale, dove 24h esatte lo sposterebbero di un'ora.
    if (!fine.isAfter(inizio)) {
      fine = DateTime(
          anno, mese, slot.giorno + 1, orario.oraFine, orario.minFine);
    }
    return (inizio, fine);
  }

  /// Slot in cui compare [nome] (ricerca parziale, case-insensitive) come
  /// titolare o sostituto, in ordine cronologico. Query vuota = nessun
  /// risultato: cercare "" elencherebbe l'intero mese.
  List<SlotPiano> cercaNome(String nome) {
    final q = nome.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final giorni = _perGiorno.keys.toList()..sort();
    return [
      for (final g in giorni)
        ...(_perGiorno[g]!.where((s) =>
            s.titolare.toLowerCase().contains(q) ||
            s.sostituti.toLowerCase().contains(q))),
    ];
  }

  /// Giorni in cui [nome] è effettivamente in servizio: quando sostituisce
  /// qualcuno (colonna D), o quando è titolare senza nessun sostituto
  /// segnato. Un titolare con la colonna sostituti compilata è stato
  /// sostituito e quel giorno non lavora — diverso da [cercaNome], che
  /// elenca ogni comparsa del nome (utile in ricerca, fuorviante come
  /// segnalino "sei di turno" sul calendario).
  Set<int> giorniInServizio(String nome) {
    final q = nome.trim().toLowerCase();
    if (q.isEmpty) return const {};
    final giorni = <int>{};
    _perGiorno.forEach((giorno, slots) {
      for (final s in slots) {
        final sostituisce = s.sostituti.toLowerCase().contains(q);
        final titolareNonSostituito =
            s.titolare.toLowerCase().contains(q) && s.sostituti.isEmpty;
        if (sostituisce || titolareNonSostituito) {
          giorni.add(giorno);
          break;
        }
      }
    });
    return giorni;
  }
}

const _prefissiGiorno = {'LUN', 'MAR', 'MER', 'GIO', 'VEN', 'SAB', 'DOM'};
const _macroBlocchi = {'H12', 'H24', 'ASSISTENZA', 'GETTONE', 'CENTRALINO'};

/// Estrae il piano mensile dai byte di un file XLSX.
/// Lancia [FormatException] (messaggio già mostrabile all'utente) se il file
/// non ha la struttura attesa. Top-level così è usabile con compute().
PianoMensile parsePianoMensile(List<int> bytes) {
  final Excel excel;
  try {
    excel = Excel.decodeBytes(bytes);
  } catch (_) {
    throw const FormatException('Il file scaricato non è un XLSX valido.');
  }

  final fogli = excel.tables.keys.where((nome) {
    final up = nome.trim().toUpperCase();
    return up.length >= 3 && _prefissiGiorno.contains(up.substring(0, 3));
  }).toList();
  if (fogli.isEmpty) {
    throw const FormatException(
        'Nessuna scheda giorno trovata (nomi tipo "LUN 1", "MAR 2"...): è il foglio dei turni?');
  }

  final (anno, mese) = _dataInizio(excel.tables[fogli.first]!);
  // Giorni reali del mese individuato da B2 (28-31): un giorno oltre questo
  // limite (es. un refuso nel nome scheda, "MAR 31" in un mese di 30 giorni)
  // va scartato qui, non solo nella griglia del calendario — altrimenti
  // resta comunque raggiungibile da cercaNome/giorniInServizio e
  // DateTime(anno, mese, giorno) si normalizza silenziosamente su un altro
  // giorno/mese.
  final giorniNelMese = DateTime(anno, mese + 1, 0).day;

  final slots = <SlotPiano>[];
  // Contatore dei blocchi unico per tutto il file, NON per scheda: un giorno
  // ha due schede (diurna e notturna) e con un contatore per scheda il blocco
  // 1 diurno e il blocco 1 notturno colliderebbero, mescolando due equipaggi
  // nel raggruppamento per blocco.
  var blocco = 0;
  for (final nome in fogli) {
    final giorno = _numeroGiorno(nome);
    if (giorno == null || giorno < 1 || giorno > giorniNelMese) continue;
    final diurno = nome.toUpperCase().contains('DIURNO');
    blocco = _parseFoglio(excel.tables[nome]!, giorno, diurno, blocco, slots);
  }

  return PianoMensile(anno: anno, mese: mese, slots: slots);
}

/// Numero del giorno dal nome della scheda: "LUN 12" → 12, "GIO DIURNO 5" → 5.
/// Il tool HTML usa substring(4) + replace('DIURNO '); il numero in coda è
/// equivalente ma tollera spazi extra e prefissi di lunghezza diversa.
int? _numeroGiorno(String nomeFoglio) {
  final match = RegExp(r'(\d+)\s*$').firstMatch(nomeFoglio.trim());
  return match == null ? null : int.tryParse(match.group(1)!);
}

/// Legge mese/anno dalla cella B2 della prima scheda. Gestisce i formati con
/// cui Google può esportare la data (cella data vera, testo "gg/mm/aaaa",
/// seriale Excel). Fallback: mese corrente, come il tool HTML.
(int, int) _dataInizio(Sheet foglio) {
  final righe = foglio.rows;
  CellValue? v;
  if (righe.length >= 2 && righe[1].length >= 2) v = righe[1][1]?.value;

  if (v is DateCellValue) return (v.year, v.month);
  if (v is DateTimeCellValue) return (v.year, v.month);
  if (v is IntCellValue) return _daSerialeExcel(v.value.toDouble());
  if (v is DoubleCellValue) return _daSerialeExcel(v.value);
  if (v is TextCellValue) {
    final parti = v.toString().trim().split('/');
    if (parti.length == 3) {
      final mese = int.tryParse(parti[1]);
      final anno = int.tryParse(parti[2]);
      if (mese != null && anno != null && mese >= 1 && mese <= 12) {
        return (anno, mese);
      }
    }
  }
  final adesso = DateTime.now();
  return (adesso.year, adesso.month);
}

/// Converte un seriale data Excel (giorni dal 30/12/1899) in (anno, mese).
(int, int) _daSerialeExcel(double seriale) {
  final data = DateTime(1899, 12, 30).add(Duration(days: seriale.round()));
  return (data.year, data.month);
}

/// Scansiona una scheda giorno e accoda gli slot trovati a [slots].
/// Riceve e restituisce il contatore dei blocchi (v. parsePianoMensile).
int _parseFoglio(
    Sheet foglio, int giorno, bool diurno, int bloccoIniziale, List<SlotPiano> slots) {
  final righe = foglio.rows;
  final maxRiga = righe.length;
  var blocco = bloccoIniziale;

  // Riga 1-based come nel foglio (riga 6 = prima riga utile), colonna 0-based.
  String testo(int riga, int colonna) {
    if (riga < 1 || riga > righe.length) return '';
    final r = righe[riga - 1];
    if (colonna >= r.length) return '';
    final v = r[colonna]?.value;
    return v == null ? '' : v.toString().trim();
  }

  // Colonne della riga ruolo: C = titolare di turno, D = possibili sostituti.
  String titolare(int riga) => testo(riga, 2);
  String sostituti(int riga) => testo(riga, 3);
  bool rigaVuota(int riga) => titolare(riga).isEmpty && sostituti(riga).isEmpty;

  var r = 6;
  while (r <= maxRiga) {
    final valA = testo(r, 0).toUpperCase();

    if (valA == 'USCITA MEZZI') {
      r += 6;
      continue;
    }
    if (!_macroBlocchi.contains(valA)) {
      r++;
      continue;
    }

    if (valA == 'CENTRALINO') {
      // Il tool HTML presenta il centralino con macro H24; qui il ruolo
      // centralino basta a distinguerlo, ma la macro resta uguale per
      // coerenza con l'output a cui l'utente è abituato.
      blocco++;
      // L'orario del centralino è sulla riga sotto il titolo (r+1), non
      // sulla terza come nei blocchi a 4 ruoli; nella scheda diurna la cella
      // contiene i due intervalli mattina/pomeriggio separati da "/", che
      // vanno divisi tra i due slot ("/" non compare mai negli orari). Solo
      // colonna A: la B in questa riga non è testo dell'orario, è
      // l'etichetta del ruolo di quella riga (vedi sotto).
      final orari = testo(r + 1, 0).trim().split('/');
      if (diurno) {
        slots.add(SlotPiano(giorno: giorno, blocco: blocco, macro: 'H24',
            ruolo: RuoloPiano.centralino, fascia: FasciaPiano.mattina,
            orario: orari.first.trim(),
            titolare: titolare(r), sostituti: sostituti(r)));
        slots.add(SlotPiano(giorno: giorno, blocco: blocco, macro: 'H24',
            ruolo: RuoloPiano.centralino, fascia: FasciaPiano.pomeriggio,
            orario: orari.length > 1 ? orari[1].trim() : '',
            titolare: titolare(r + 1), sostituti: sostituti(r + 1)));
      } else {
        slots.add(SlotPiano(giorno: giorno, blocco: blocco, macro: 'H24',
            ruolo: RuoloPiano.centralino, fascia: FasciaPiano.sera,
            orario: orari.first.trim(),
            titolare: titolare(r), sostituti: sostituti(r)));
      }
      r += 3;
      continue;
    }

    // Blocco equipaggio a 4 ruoli (H12/H24/ASSISTENZA/GETTONE). Ogni riga ha
    // colonna A col contenuto informativo (titolo blocco sulla riga r,
    // descrizione della fascia sulla riga del Cs r+1, orario del blocco
    // sulla riga del Terzo r+2, monte ore sulla riga del Quarto r+3, che non
    // serve), colonna B col nome del ruolo di quella riga (Autista/Cs/Terzo/
    // Quarto, solo etichetta — non letta, il ruolo si ricava dalla
    // posizione), colonna C il titolare e D i sostituti.
    final descrizione = testo(r + 1, 0).toUpperCase();
    final orario = testo(r + 2, 0);

    if (valA == 'ASSISTENZA' || valA == 'GETTONE') {
      // Blocco template mai compilato (né descrizione né nomi): non è un
      // buco da segnalare, è solo spazio predisposto nel foglio.
      final descrizioneVuota =
          descrizione.replaceAll(RegExp('[^A-Z0-9]'), '').isEmpty;
      final nessunNome = [r, r + 1, r + 2, r + 3].every(rigaVuota);
      if (descrizioneVuota && nessunNome) {
        r += 4;
        continue;
      }
    }

    var fascia = diurno ? FasciaPiano.mattina : FasciaPiano.sera;
    if (descrizione.contains('MATT')) {
      fascia = FasciaPiano.mattina;
    } else if (descrizione.contains('POM')) {
      fascia = FasciaPiano.pomeriggio;
    } else if (descrizione.contains('SER')) {
      fascia = FasciaPiano.sera;
    } else if (descrizione.contains('NOT')) {
      fascia = FasciaPiano.notte;
    }

    blocco++;
    const ruoli = [RuoloPiano.autista, RuoloPiano.cs, RuoloPiano.terzo, RuoloPiano.quarto];
    for (var i = 0; i < ruoli.length; i++) {
      slots.add(SlotPiano(giorno: giorno, blocco: blocco, macro: valA,
          ruolo: ruoli[i], fascia: fascia, orario: orario,
          titolare: titolare(r + i), sostituti: sostituti(r + i)));
    }
    r += 4;
  }
  return blocco;
}
