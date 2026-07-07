// Test del parser del piano turni mensile (lib/utils/piano_mensile.dart).
// I file XLSX di prova vengono costruiti in memoria col package excel stesso:
// niente fixture binarie nel repo, e ogni test dichiara esattamente la
// struttura del foglio che sta verificando.
import 'package:flutter_test/flutter_test.dart';
import 'package:excel/excel.dart';
import 'package:ambu_turni/utils/piano_mensile.dart';

/// Scrive un testo nella cella (es. 'A6') della scheda [foglio], creandola.
void scrivi(Excel excel, String foglio, String cella, String testo) {
  excel[foglio].cell(CellIndex.indexByString(cella)).value = TextCellValue(testo);
}

/// Codifica il workbook e lo riparsa col parser sotto test.
PianoMensile parsa(Excel excel) => parsePianoMensile(excel.encode()!);

/// Workbook con una scheda giorno e la data del mese in B2.
Excel base(String nomeFoglio, {String dataB2 = '01/07/2026'}) {
  final excel = Excel.createExcel(); // contiene la scheda di default "Sheet1"
  scrivi(excel, nomeFoglio, 'B2', dataB2);
  return excel;
}

void main() {
  group('Data e struttura del file', () {
    test('mese e anno letti da B2 in formato testo gg/mm/aaaa', () {
      final piano = parsa(base('LUN 1'));
      expect(piano.anno, 2026);
      expect(piano.mese, 7);
      expect(piano.giorniNelMese, 31);
    });

    test('mese e anno letti da B2 come cella data', () {
      final excel = Excel.createExcel();
      excel['MAR 2'].cell(CellIndex.indexByString('B2')).value =
          const DateCellValue(year: 2026, month: 2, day: 1);
      final piano = parsa(excel);
      expect(piano.anno, 2026);
      expect(piano.mese, 2);
      expect(piano.giorniNelMese, 28);
    });

    test('file senza schede giorno rifiutato con FormatException', () {
      final excel = Excel.createExcel(); // solo "Sheet1"
      expect(() => parsePianoMensile(excel.encode()!), throwsFormatException);
    });

    test('numero del giorno dal nome scheda, anche con DIURNO', () {
      final excel = base('GIO DIURNO 5');
      scrivi(excel, 'GIO DIURNO 5', 'A6', 'H24');
      scrivi(excel, 'GIO DIURNO 5', 'C6', 'Rossi');
      final piano = parsa(excel);
      expect(piano.delGiorno(5), isNotEmpty);
    });
  });

  group('Blocchi equipaggio (H12/H24)', () {
    test('4 ruoli: titolare (C) e sostituti (D) separati, righe vuote come buchi', () {
      final excel = base('LUN 1');
      scrivi(excel, 'LUN 1', 'A6', 'H24');
      scrivi(excel, 'LUN 1', 'A7', 'MATTINA');
      scrivi(excel, 'LUN 1', 'C6', 'Rossi');
      scrivi(excel, 'LUN 1', 'D6', 'Verdi');
      scrivi(excel, 'LUN 1', 'C7', 'Bianchi');
      // Terzo e Quarto (righe 8-9) lasciati vuoti -> buchi.

      final slots = parsa(excel).delGiorno(1);
      expect(slots, hasLength(4));

      final autista = slots.firstWhere((s) => s.ruolo == RuoloPiano.autista);
      expect(autista.titolare, 'Rossi');
      expect(autista.sostituti, 'Verdi');
      expect(autista.buco, isFalse);
      expect(autista.fascia, FasciaPiano.mattina);
      expect(autista.macro, 'H24');

      final cs = slots.firstWhere((s) => s.ruolo == RuoloPiano.cs);
      expect(cs.titolare, 'Bianchi');
      expect(cs.sostituti, isEmpty);

      expect(slots.firstWhere((s) => s.ruolo == RuoloPiano.terzo).buco, isTrue);
      expect(slots.firstWhere((s) => s.ruolo == RuoloPiano.quarto).buco, isTrue);
    });

    test('solo sostituto (D) senza titolare (C) non è un buco', () {
      final excel = base('LUN 1');
      scrivi(excel, 'LUN 1', 'A6', 'H24');
      scrivi(excel, 'LUN 1', 'D6', 'Verdi');

      final autista =
          parsa(excel).delGiorno(1).firstWhere((s) => s.ruolo == RuoloPiano.autista);
      expect(autista.buco, isFalse);
      expect(autista.titolare, isEmpty);
      expect(autista.sostituti, 'Verdi');
    });

    test('fascia dalla descrizione (POMERIGGIO in A/B della seconda riga)', () {
      final excel = base('LUN 1');
      scrivi(excel, 'LUN 1', 'A6', 'H12');
      scrivi(excel, 'LUN 1', 'B7', 'TURNO POMERIGGIO');
      scrivi(excel, 'LUN 1', 'C6', 'Rossi');
      final slots = parsa(excel).delGiorno(1);
      expect(slots.first.fascia, FasciaPiano.pomeriggio);
      expect(slots.first.macro, 'H12');
    });

    test('default: mattina su scheda DIURNO, sera altrimenti', () {
      final diurno = base('LUN DIURNO 1');
      scrivi(diurno, 'LUN DIURNO 1', 'A6', 'H24');
      scrivi(diurno, 'LUN DIURNO 1', 'C6', 'Rossi');
      expect(parsa(diurno).delGiorno(1).first.fascia, FasciaPiano.mattina);

      final notturno = base('LUN 1');
      scrivi(notturno, 'LUN 1', 'A6', 'H24');
      scrivi(notturno, 'LUN 1', 'C6', 'Rossi');
      expect(parsa(notturno).delGiorno(1).first.fascia, FasciaPiano.sera);
    });

    test('schede diurna e notturna dello stesso giorno: blocchi distinti', () {
      // Regressione: il contatore dei blocchi era per scheda, quindi il primo
      // blocco della scheda diurna e il primo della notturna (stesso giorno)
      // collidevano, mescolando i due equipaggi nel raggruppamento per blocco.
      final excel = base('LUN DIURNO 1');
      scrivi(excel, 'LUN DIURNO 1', 'A6', 'H24');
      scrivi(excel, 'LUN DIURNO 1', 'C6', 'Rossi');
      scrivi(excel, 'LUN 1', 'A6', 'H24');
      scrivi(excel, 'LUN 1', 'C6', 'Neri');

      final slots = parsa(excel).delGiorno(1);
      expect(slots, hasLength(8));
      expect(slots.map((s) => s.blocco).toSet(), hasLength(2));
      // Gli slot dello stesso blocco devono condividere la fascia: se i
      // blocchi collidessero, mattina (diurna) e sera (notturna) si mischierebbero.
      final perBlocco = <int, Set<FasciaPiano>>{};
      for (final s in slots) {
        perBlocco.putIfAbsent(s.blocco, () => {}).add(s.fascia);
      }
      expect(perBlocco.values.every((fasce) => fasce.length == 1), isTrue);
    });

    test('due blocchi nello stesso giorno restano equipaggi distinti', () {
      final excel = base('LUN 1');
      scrivi(excel, 'LUN 1', 'A6', 'H24');
      scrivi(excel, 'LUN 1', 'A7', 'MATTINA');
      scrivi(excel, 'LUN 1', 'C6', 'Rossi');
      scrivi(excel, 'LUN 1', 'A10', 'H24');
      scrivi(excel, 'LUN 1', 'A11', 'NOTTE');
      scrivi(excel, 'LUN 1', 'C10', 'Neri');

      final slots = parsa(excel).delGiorno(1);
      expect(slots, hasLength(8));
      expect(slots.map((s) => s.blocco).toSet(), {1, 2});
      final notte = slots.where((s) => s.fascia == FasciaPiano.notte);
      expect(notte, hasLength(4));
    });
  });

  group('Centralino', () {
    test('scheda diurna: slot mattina e pomeriggio su due righe', () {
      final excel = base('LUN DIURNO 1');
      scrivi(excel, 'LUN DIURNO 1', 'A6', 'CENTRALINO');
      scrivi(excel, 'LUN DIURNO 1', 'C6', 'Neri');
      // Riga 7 (pomeriggio) vuota -> buco.

      final slots = parsa(excel).delGiorno(1);
      expect(slots, hasLength(2));
      expect(slots.every((s) => s.ruolo == RuoloPiano.centralino), isTrue);
      expect(slots.every((s) => s.macro == 'H24'), isTrue);

      final mattina = slots.firstWhere((s) => s.fascia == FasciaPiano.mattina);
      expect(mattina.titolare, 'Neri');
      final pomeriggio = slots.firstWhere((s) => s.fascia == FasciaPiano.pomeriggio);
      expect(pomeriggio.buco, isTrue);
    });

    test('scheda notturna: un solo slot di sera', () {
      final excel = base('LUN 1');
      scrivi(excel, 'LUN 1', 'A6', 'CENTRALINO');
      final slots = parsa(excel).delGiorno(1);
      expect(slots, hasLength(1));
      expect(slots.single.fascia, FasciaPiano.sera);
      expect(slots.single.buco, isTrue);
    });
  });

  group('Assistenze e gettoni', () {
    test('blocco template (senza descrizione né nomi) ignorato', () {
      final excel = base('LUN 1');
      scrivi(excel, 'LUN 1', 'A6', 'ASSISTENZA');
      expect(parsa(excel).delGiorno(1), isEmpty);
    });

    test('blocco compilato genera slot con flag assistenza', () {
      final excel = base('LUN 1');
      scrivi(excel, 'LUN 1', 'A6', 'GETTONE');
      scrivi(excel, 'LUN 1', 'A7', 'MATTINA');
      scrivi(excel, 'LUN 1', 'C8', 'Gialli'); // Terzo assegnato

      final slots = parsa(excel).delGiorno(1);
      expect(slots, hasLength(4));
      expect(slots.every((s) => s.assistenza), isTrue);
      final terzo = slots.firstWhere((s) => s.ruolo == RuoloPiano.terzo);
      expect(terzo.titolare, 'Gialli');
      expect(slots.where((s) => s.buco), hasLength(3));
    });

    test('blocco con soli nomi (senza descrizione fascia) non è un template', () {
      final excel = base('LUN 1');
      scrivi(excel, 'LUN 1', 'A6', 'ASSISTENZA');
      scrivi(excel, 'LUN 1', 'C6', 'Rossi');
      final slots = parsa(excel).delGiorno(1);
      expect(slots, hasLength(4));
    });
  });

  group('USCITA MEZZI e righe estranee', () {
    test('salta 6 righe e riprende dal blocco successivo', () {
      final excel = base('LUN 1');
      scrivi(excel, 'LUN 1', 'A6', 'USCITA MEZZI');
      // Righe 7-11: contenuto del blocco uscita mezzi, da ignorare anche se
      // una cella contiene per caso una parola chiave in colonna C.
      scrivi(excel, 'LUN 1', 'C7', 'Rossi');
      scrivi(excel, 'LUN 1', 'A12', 'H12');
      scrivi(excel, 'LUN 1', 'A13', 'SERA');
      scrivi(excel, 'LUN 1', 'C12', 'Blu');

      final slots = parsa(excel).delGiorno(1);
      expect(slots, hasLength(4));
      expect(slots.first.macro, 'H12');
      expect(slots.first.fascia, FasciaPiano.sera);
      expect(slots.first.titolare, 'Blu');
    });

    test('righe non riconosciute prima e in mezzo vengono ignorate', () {
      final excel = base('LUN 1');
      scrivi(excel, 'LUN 1', 'A6', 'NOTE VARIE');
      scrivi(excel, 'LUN 1', 'A8', 'H24');
      scrivi(excel, 'LUN 1', 'C8', 'Rossi');
      final slots = parsa(excel).delGiorno(1);
      expect(slots, hasLength(4));
      expect(slots.first.titolare, 'Rossi');
    });
  });

  group('cercaNome', () {
    Excel fixture() {
      final excel = base('LUN 1');
      scrivi(excel, 'LUN 1', 'A6', 'H24');
      scrivi(excel, 'LUN 1', 'C6', 'Rossi Mario');
      scrivi(excel, 'LUN 1', 'D7', 'De Rossi');
      scrivi(excel, 'MAR 2', 'A6', 'H12');
      scrivi(excel, 'MAR 2', 'C7', 'Bianchi');
      return excel;
    }

    test('trova per sottostringa case-insensitive in titolari e sostituti', () {
      final piano = parsa(fixture());
      // "rossi" compare come titolare (giorno 1) e come sostituto (giorno 1).
      final rossi = piano.cercaNome('rossi');
      expect(rossi, hasLength(2));
      expect(rossi.every((s) => s.giorno == 1), isTrue);

      final bianchi = piano.cercaNome('BIANCHI');
      expect(bianchi, hasLength(1));
      expect(bianchi.single.giorno, 2);
      expect(bianchi.single.ruolo, RuoloPiano.cs);
    });

    test('risultati in ordine cronologico e query vuota senza risultati', () {
      final excel = fixture();
      scrivi(excel, 'MER 3', 'A6', 'H24');
      scrivi(excel, 'MER 3', 'C6', 'Rossi');
      final piano = parsa(excel);

      final giorni = piano.cercaNome('rossi').map((s) => s.giorno).toList();
      expect(giorni, [1, 1, 3]);

      expect(piano.cercaNome(''), isEmpty);
      expect(piano.cercaNome('   '), isEmpty);
    });
  });

  group('Orario del blocco e intervalloEvento', () {
    test('orario letto dalla terza riga del blocco (colonna info)', () {
      final excel = base('LUN 1');
      scrivi(excel, 'LUN 1', 'A6', 'H24');
      scrivi(excel, 'LUN 1', 'A7', 'SERA');
      scrivi(excel, 'LUN 1', 'A8', '18:30 - 23:30');
      scrivi(excel, 'LUN 1', 'A9', '5,0'); // monte ore: ignorato
      scrivi(excel, 'LUN 1', 'C6', 'Rossi');

      final piano = parsa(excel);
      final slots = piano.delGiorno(1);
      // Tutti gli slot del blocco condividono lo stesso orario.
      expect(slots.map((s) => s.orario).toSet(), {'18:30 - 23:30'});

      final orario = slots.first.orarioParsed;
      expect(orario, isNotNull);
      expect((orario!.oraInizio, orario.minInizio), (18, 30));
      expect((orario.oraFine, orario.minFine), (23, 30));

      final (inizio, fine) = piano.intervalloEvento(slots.first)!;
      expect(inizio, DateTime(2026, 7, 1, 18, 30));
      expect(fine, DateTime(2026, 7, 1, 23, 30));
    });

    test('orario con punto come separatore e trattino lungo', () {
      final excel = base('LUN 1');
      scrivi(excel, 'LUN 1', 'A6', 'H12');
      scrivi(excel, 'LUN 1', 'A8', '7.30 – 13.30');
      scrivi(excel, 'LUN 1', 'C6', 'Rossi');

      final orario = parsa(excel).delGiorno(1).first.orarioParsed;
      expect(orario, isNotNull);
      expect((orario!.oraInizio, orario.minInizio), (7, 30));
      expect((orario.oraFine, orario.minFine), (13, 30));
    });

    test('turno a cavallo di mezzanotte: fine il giorno dopo, anche a fine mese', () {
      final excel = base('VEN 31');
      scrivi(excel, 'VEN 31', 'A6', 'H24');
      scrivi(excel, 'VEN 31', 'A7', 'NOTTE');
      scrivi(excel, 'VEN 31', 'A8', '23:30 - 7:00');
      scrivi(excel, 'VEN 31', 'C6', 'Rossi');

      final piano = parsa(excel);
      final (inizio, fine) = piano.intervalloEvento(piano.delGiorno(31).first)!;
      expect(inizio, DateTime(2026, 7, 31, 23, 30));
      expect(fine, DateTime(2026, 8, 1, 7, 0)); // rollover di mese
    });

    test('centralino diurno: i due intervalli separati da "/" divisi tra gli slot', () {
      final excel = base('LUN DIURNO 1');
      scrivi(excel, 'LUN DIURNO 1', 'A6', 'CENTRALINO');
      scrivi(excel, 'LUN DIURNO 1', 'A7', '8:30 - 13:30/13:30 - 18:30');
      scrivi(excel, 'LUN DIURNO 1', 'A8', '5,0'); // monte ore: ignorato
      scrivi(excel, 'LUN DIURNO 1', 'C6', 'Neri');

      final piano = parsa(excel);
      final slots = piano.delGiorno(1);
      final mattina = slots.firstWhere((s) => s.fascia == FasciaPiano.mattina);
      final pomeriggio = slots.firstWhere((s) => s.fascia == FasciaPiano.pomeriggio);
      expect(mattina.orario, '8:30 - 13:30');
      expect(pomeriggio.orario, '13:30 - 18:30');

      final (inizioM, fineM) = piano.intervalloEvento(mattina)!;
      expect(inizioM, DateTime(2026, 7, 1, 8, 30));
      expect(fineM, DateTime(2026, 7, 1, 13, 30));
      final (inizioP, fineP) = piano.intervalloEvento(pomeriggio)!;
      expect(inizioP, DateTime(2026, 7, 1, 13, 30));
      expect(fineP, DateTime(2026, 7, 1, 18, 30));
    });

    test('centralino serale: orario singolo sulla riga sotto il titolo', () {
      final excel = base('LUN 1');
      scrivi(excel, 'LUN 1', 'A6', 'CENTRALINO');
      scrivi(excel, 'LUN 1', 'A7', '18:30 - 23:30');
      scrivi(excel, 'LUN 1', 'C6', 'Neri');

      final piano = parsa(excel);
      final slot = piano.delGiorno(1).single;
      expect(slot.orario, '18:30 - 23:30');
      final (inizio, fine) = piano.intervalloEvento(slot)!;
      expect(inizio, DateTime(2026, 7, 1, 18, 30));
      expect(fine, DateTime(2026, 7, 1, 23, 30));
    });

    test('senza orario (o testo non riconoscibile) niente intervallo', () {
      final excel = base('LUN 1');
      scrivi(excel, 'LUN 1', 'A6', 'H24');
      scrivi(excel, 'LUN 1', 'A8', 'orario da definire');
      scrivi(excel, 'LUN 1', 'C6', 'Rossi');
      // Centralino: blocco senza riga orario.
      scrivi(excel, 'LUN 1', 'A10', 'CENTRALINO');
      scrivi(excel, 'LUN 1', 'C10', 'Neri');

      final piano = parsa(excel);
      final slots = piano.delGiorno(1);
      final h24 = slots.firstWhere((s) => s.macro == 'H24' && s.ruolo != RuoloPiano.centralino);
      expect(h24.orarioParsed, isNull);
      expect(piano.intervalloEvento(h24), isNull);

      final centralino = slots.firstWhere((s) => s.ruolo == RuoloPiano.centralino);
      expect(centralino.orario, isEmpty);
      expect(piano.intervalloEvento(centralino), isNull);
    });

    test('orario con valori fuori scala non riconosciuto', () {
      const slot = SlotPiano(
          giorno: 1, blocco: 1, macro: 'H24', ruolo: RuoloPiano.autista,
          fascia: FasciaPiano.sera, titolare: 'Rossi', sostituti: '',
          orario: '25:00 - 99:99');
      expect(slot.orarioParsed, isNull);
    });
  });

  group('giorniInServizio', () {
    test('titolare senza sostituto sì, titolare sostituito no, sostituto sì', () {
      final excel = base('LUN 1');
      // Giorno 1: Rossi titolare senza sostituto -> in servizio.
      scrivi(excel, 'LUN 1', 'A6', 'H24');
      scrivi(excel, 'LUN 1', 'C6', 'Rossi');
      // Giorno 2: Rossi titolare ma sostituito da Verdi -> NON in servizio;
      // Verdi (sostituto) sì.
      scrivi(excel, 'MAR 2', 'A6', 'H24');
      scrivi(excel, 'MAR 2', 'C6', 'Rossi');
      scrivi(excel, 'MAR 2', 'D6', 'Verdi');

      final piano = parsa(excel);
      expect(piano.giorniInServizio('rossi'), {1});
      expect(piano.giorniInServizio('verdi'), {2});
      // cercaNome invece elenca ogni comparsa: Rossi appare entrambi i giorni.
      expect(piano.cercaNome('rossi').map((s) => s.giorno).toSet(), {1, 2});
    });

    test('sostituito in uno slot ma sostituto in un altro dello stesso giorno', () {
      final excel = base('LUN 1');
      // Rossi cede il posto di autista a Verdi ma copre il Cs per Bianchi:
      // il giorno resta segnato (lavora comunque).
      scrivi(excel, 'LUN 1', 'A6', 'H24');
      scrivi(excel, 'LUN 1', 'C6', 'Rossi');
      scrivi(excel, 'LUN 1', 'D6', 'Verdi');
      scrivi(excel, 'LUN 1', 'C7', 'Bianchi');
      scrivi(excel, 'LUN 1', 'D7', 'Rossi');

      final piano = parsa(excel);
      expect(piano.giorniInServizio('rossi'), {1});
      expect(piano.giorniInServizio('bianchi'), isEmpty);
    });

    test('query vuota: nessun giorno', () {
      final excel = base('LUN 1');
      scrivi(excel, 'LUN 1', 'A6', 'H24');
      scrivi(excel, 'LUN 1', 'C6', 'Rossi');
      final piano = parsa(excel);
      expect(piano.giorniInServizio(''), isEmpty);
      expect(piano.giorniInServizio('   '), isEmpty);
    });
  });

  group('buchiDelGiorno con filtri ruolo', () {
    test('esclude i ruoli filtrati dal conteggio', () {
      final excel = base('LUN 1');
      scrivi(excel, 'LUN 1', 'A6', 'H24');
      scrivi(excel, 'LUN 1', 'C6', 'Rossi'); // solo autista coperto

      final piano = parsa(excel);
      expect(piano.buchiDelGiorno(1), hasLength(3)); // cs, terzo, quarto
      expect(
        piano.buchiDelGiorno(1, ruoliEsclusi: {RuoloPiano.quarto, RuoloPiano.terzo}),
        hasLength(1),
      );
    });
  });
}
