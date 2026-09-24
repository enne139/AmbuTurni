// Test di lib/utils/comunicati.dart (Tools → Archivio comunicati):
// parsing della data dal nome file e raggruppamento per mese.
import 'package:flutter_test/flutter_test.dart';
import 'package:ambu_turni/utils/comunicati.dart';

void main() {
  group('dataDaNomeFile', () {
    test('legge AAAAMMGG dai primi 8 caratteri', () {
      expect(dataDaNomeFile('20260115_003_verbale-assemblea.pdf'), DateTime(2026, 1, 15));
    });

    test('funziona anche senza suffisso dopo la data', () {
      expect(dataDaNomeFile('20261231'), DateTime(2026, 12, 31));
    });

    test('nome troppo corto restituisce null', () {
      expect(dataDaNomeFile('2026011'), isNull);
    });

    test('nome null restituisce null', () {
      expect(dataDaNomeFile(null), isNull);
    });

    test('prefisso non numerico restituisce null', () {
      expect(dataDaNomeFile('verbale_2026.pdf'), isNull);
    });

    test('mese fuori scala (13) restituisce null', () {
      expect(dataDaNomeFile('20261301_x.pdf'), isNull);
    });

    test('giorno inesistente (31 aprile) restituisce null, non normalizzato a maggio', () {
      // DateTime(2026, 4, 31) normalizzerebbe silenziosamente a 1 maggio:
      // il controllo day/month/year deve intercettarlo come "non una data".
      expect(dataDaNomeFile('20260431_x.pdf'), isNull);
    });

    test('29 febbraio in anno bisestile è valido', () {
      expect(dataDaNomeFile('20240229_x.pdf'), DateTime(2024, 2, 29));
    });

    test('29 febbraio in anno non bisestile restituisce null', () {
      expect(dataDaNomeFile('20260229_x.pdf'), isNull);
    });
  });

  group('dataComunicato', () {
    test('preferisce la data nel nome file a createdAt', () {
      final c = {'fileName': '20250301_001_x.pdf', 'createdAt': '2026-09-02T10:00:00Z'};
      expect(dataComunicato(c), DateTime(2025, 3, 1));
    });

    test('nome file non riconoscibile: usa createdAt', () {
      final c = {'fileName': 'verbale.pdf', 'createdAt': '2026-09-02T10:00:00Z'};
      expect(dataComunicato(c), DateTime.parse('2026-09-02T10:00:00Z'));
    });

    test('né nome file né createdAt validi: fallback fisso, comunicato non perso', () {
      final c = {'fileName': 'verbale.pdf', 'createdAt': null};
      expect(dataComunicato(c), DateTime(1970));
    });
  });

  group('raggruppaPerMese', () {
    test('un comunicato per mese, intestazioni dal più recente', () {
      final comunicati = [
        {'id': 'a', 'fileName': '20260115_001_x.pdf'},
        {'id': 'b', 'fileName': '20260810_002_x.pdf'},
        {'id': 'c', 'fileName': '20251220_003_x.pdf'},
      ];
      final gruppi = raggruppaPerMese(comunicati);
      expect(gruppi.keys.toList(), ['Agosto 2026', 'Gennaio 2026', 'Dicembre 2025']);
      expect(gruppi['Agosto 2026']!.single['id'], 'b');
    });

    test('più comunicati nello stesso mese finiscono nello stesso gruppo, ordinati per data decrescente', () {
      final comunicati = [
        {'id': 'vecchio', 'fileName': '20260105_001_x.pdf'},
        {'id': 'nuovo', 'fileName': '20260120_002_x.pdf'},
      ];
      final gruppi = raggruppaPerMese(comunicati);
      expect(gruppi.keys.toList(), ['Gennaio 2026']);
      expect(gruppi['Gennaio 2026']!.map((c) => c['id']), ['nuovo', 'vecchio']);
    });

    test('un comunicato senza data riconoscibile non sparisce dal raggruppamento', () {
      final comunicati = [
        {'id': 'senza_data', 'fileName': 'verbale.pdf', 'createdAt': null},
        {'id': 'con_data', 'fileName': '20260115_001_x.pdf'},
      ];
      final gruppi = raggruppaPerMese(comunicati);
      final totale = gruppi.values.fold<int>(0, (n, lista) => n + lista.length);
      expect(totale, 2);
    });
  });

  group('tagsDi', () {
    test('estrae i tag quando presenti', () {
      final c = {'id': 'a', 'tags': ['formazione', 'sicurezza']};
      expect(tagsDi(c), ['formazione', 'sicurezza']);
    });

    test('campo assente restituisce lista vuota', () {
      expect(tagsDi({'id': 'a'}), isEmpty);
    });

    test('campo di tipo inatteso (non una lista) restituisce lista vuota', () {
      expect(tagsDi({'id': 'a', 'tags': 'formazione'}), isEmpty);
    });

    test('elementi non stringa nella lista vengono scartati', () {
      final c = {'id': 'a', 'tags': ['formazione', 42, null]};
      expect(tagsDi(c), ['formazione']);
    });
  });

  group('tuttiTag', () {
    test('raccoglie i tag distinti da più comunicati, alfabetici', () {
      final comunicati = [
        {'id': 'a', 'tags': ['sicurezza', 'formazione']},
        {'id': 'b', 'tags': ['formazione', 'assemblea']},
        {'id': 'c', 'tags': []},
      ];
      expect(tuttiTag(comunicati), ['assemblea', 'formazione', 'sicurezza']);
    });

    test('nessun comunicato taggato restituisce lista vuota', () {
      expect(tuttiTag([{'id': 'a'}]), isEmpty);
    });
  });

  group('filtraComunicati', () {
    final comunicati = [
      {'id': 'a', 'fileName': '20260115_001_verbale-assemblea.pdf', 'titolo': null, 'tags': ['assemblea']},
      {'id': 'b', 'fileName': '20260210_002_corso-blsd.pdf', 'titolo': 'Corso BLSD', 'tags': ['formazione', 'sicurezza']},
      {'id': 'c', 'fileName': '20260305_003_avviso.pdf', 'titolo': null, 'tags': <String>[]},
    ];

    test('senza filtri restituisce tutto', () {
      expect(filtraComunicati(comunicati).length, 3);
    });

    test('ricerca per nome file (case-insensitive)', () {
      final risultato = filtraComunicati(comunicati, ricerca: 'BLSD');
      expect(risultato.map((c) => c['id']), ['b']);
    });

    test('ricerca per titolo quando il nome file non corrisponde', () {
      final risultato = filtraComunicati(comunicati, ricerca: 'corso');
      expect(risultato.map((c) => c['id']), ['b']);
    });

    test('filtro tag: un comunicato con ALMENO uno dei tag selezionati passa (OR)', () {
      final risultato = filtraComunicati(comunicati, tag: {'assemblea', 'sicurezza'});
      expect(risultato.map((c) => c['id']).toSet(), {'a', 'b'});
    });

    test('comunicati senza tag sono esclusi quando un tag è selezionato', () {
      final risultato = filtraComunicati(comunicati, tag: {'formazione'});
      expect(risultato.map((c) => c['id']), ['b']);
    });

    test('ricerca e tag insieme sono in AND', () {
      final risultato = filtraComunicati(comunicati, ricerca: 'blsd', tag: {'assemblea'});
      expect(risultato, isEmpty);
    });
  });
}
