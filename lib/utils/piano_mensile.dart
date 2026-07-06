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
//     di A/B della seconda riga (MATT/POM/SER/NOT), default mattina se scheda
//     diurna altrimenti sera. Un blocco ASSISTENZA/GETTONE senza descrizione
//     né nomi è un template inutilizzato e viene ignorato.
//   * CENTRALINO: 2 slot (mattina+pomeriggio) se diurno, 1 (sera) altrimenti.
//   * USCITA MEZZI: blocco fisso da saltare (6 righe).
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

  const SlotPiano({
    required this.giorno,
    required this.blocco,
    required this.macro,
    required this.ruolo,
    required this.fascia,
    required this.titolare,
    required this.sostituti,
  });

  bool get buco => titolare.isEmpty && sostituti.isEmpty;
  bool get assistenza => macro == 'ASSISTENZA' || macro == 'GETTONE';
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

  /// Slot del giorno nell'ordine del foglio, lista vuota se il giorno non ha
  /// una scheda (o non ha blocchi riconosciuti).
  List<SlotPiano> delGiorno(int giorno) => _perGiorno[giorno] ?? const [];

  /// Buchi del giorno, ignorando i ruoli in [ruoliEsclusi] (es. il Quarto,
  /// spesso scoperto per scelta e non un vero buco da coprire).
  List<SlotPiano> buchiDelGiorno(int giorno, {Set<RuoloPiano> ruoliEsclusi = const {}}) =>
      delGiorno(giorno)
          .where((s) => s.buco && !ruoliEsclusi.contains(s.ruolo))
          .toList();

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

  final slots = <SlotPiano>[];
  // Contatore dei blocchi unico per tutto il file, NON per scheda: un giorno
  // ha due schede (diurna e notturna) e con un contatore per scheda il blocco
  // 1 diurno e il blocco 1 notturno colliderebbero, mescolando due equipaggi
  // nel raggruppamento per blocco.
  var blocco = 0;
  for (final nome in fogli) {
    final giorno = _numeroGiorno(nome);
    if (giorno == null || giorno < 1 || giorno > 31) continue;
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
      if (diurno) {
        slots.add(SlotPiano(giorno: giorno, blocco: blocco, macro: 'H24',
            ruolo: RuoloPiano.centralino, fascia: FasciaPiano.mattina,
            titolare: titolare(r), sostituti: sostituti(r)));
        slots.add(SlotPiano(giorno: giorno, blocco: blocco, macro: 'H24',
            ruolo: RuoloPiano.centralino, fascia: FasciaPiano.pomeriggio,
            titolare: titolare(r + 1), sostituti: sostituti(r + 1)));
      } else {
        slots.add(SlotPiano(giorno: giorno, blocco: blocco, macro: 'H24',
            ruolo: RuoloPiano.centralino, fascia: FasciaPiano.sera,
            titolare: titolare(r), sostituti: sostituti(r)));
      }
      r += 3;
      continue;
    }

    // Blocco equipaggio a 4 ruoli (H12/H24/ASSISTENZA/GETTONE).
    // La descrizione della fascia condivide la riga del Cs (r+1), colonne A/B.
    final descrizione = '${testo(r + 1, 0)} ${testo(r + 1, 1)}'.toUpperCase();

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
          ruolo: ruoli[i], fascia: fascia,
          titolare: titolare(r + i), sostituti: sostituti(r + i)));
    }
    r += 4;
  }
  return blocco;
}
