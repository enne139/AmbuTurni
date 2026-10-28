// Test di lib/utils/materiali_condivisi.dart: parsing tollerante delle
// righe del backend, corpo delle richieste, nomi dei mezzi e filtro per mezzo.
import 'package:flutter_test/flutter_test.dart';
import 'package:ambu_turni/utils/materiali_condivisi.dart';

void main() {
  group('MaterialeUsatoCondiviso.fromJson', () {
    test('legge tutti i campi', () {
      final mu = MaterialeUsatoCondiviso.fromJson({
        'id': 'a1',
        'materiale': 'Garze',
        'quantita': 3,
        'unita': 'confezioni',
        'posizione': 'ZAINO',
        'mezzo': '12',
        'note': 'sotto il sedile',
        'creatoDa': 'mario',
        'createdAt': '2026-10-28T10:15:00Z',
      })!;
      expect(mu.id, 'a1');
      expect(mu.materiale, 'Garze');
      expect(mu.quantita, 3);
      expect(mu.quantitaLabel, '3 confezioni');
      expect(mu.posizione, 'ZAINO');
      expect(mu.mezzo, '12');
      expect(mu.note, 'sotto il sedile');
      expect(mu.creatoDa, 'mario');
      expect(mu.createdAt!.toUtc(), DateTime.utc(2026, 10, 28, 10, 15));
    });

    test('senza id o materiale la riga è scartata (null)', () {
      expect(MaterialeUsatoCondiviso.fromJson({'materiale': 'Garze'}), isNull);
      expect(MaterialeUsatoCondiviso.fromJson({'id': 'a1'}), isNull);
      expect(MaterialeUsatoCondiviso.fromJson({'id': 'a1', 'materiale': ''}), isNull);
    });

    test('campi opzionali assenti, vuoti o di tipo sbagliato diventano null', () {
      final mu = MaterialeUsatoCondiviso.fromJson({
        'id': 'a1',
        'materiale': 'Garze',
        'unita': '',
        'posizione': 7,
        'mezzo': '  ',
        'createdAt': 'non una data',
      })!;
      expect(mu.unita, isNull);
      expect(mu.posizione, isNull);
      expect(mu.mezzo, isNull);
      expect(mu.note, isNull);
      expect(mu.creatoDa, '');
      expect(mu.createdAt, isNull);
      expect(mu.quantitaLabel, '1');
    });

    test('quantità assente o non valida vale 1', () {
      expect(MaterialeUsatoCondiviso.fromJson({'id': 'a', 'materiale': 'm'})!.quantita, 1);
      expect(MaterialeUsatoCondiviso.fromJson({'id': 'a', 'materiale': 'm', 'quantita': 0})!.quantita, 1);
      expect(MaterialeUsatoCondiviso.fromJson({'id': 'a', 'materiale': 'm', 'quantita': '5'})!.quantita, 1);
    });

    test('copyWith cambia solo la quantità', () {
      const mu = MaterialeUsatoCondiviso(id: 'a', materiale: 'm', quantita: 2, mezzo: '12', creatoDa: 'anna');
      final nuovo = mu.copyWith(quantita: 5);
      expect(nuovo.quantita, 5);
      expect(nuovo.mezzo, '12');
      expect(nuovo.creatoDa, 'anna');
    });
  });

  group('datiMaterialeCondiviso', () {
    test('ripulisce gli spazi e manda null per i campi vuoti', () {
      expect(
        datiMaterialeCondiviso(materiale: ' Garze ', quantita: 2, unita: '  ', posizione: null, mezzo: '12', note: ' ok '),
        {'materiale': 'Garze', 'quantita': 2, 'unita': null, 'posizione': null, 'mezzo': '12', 'note': 'ok'},
      );
    });
  });

  group('nomiMezzi', () {
    test('estrae i nomi a due cifre, senza doppioni, in ordine', () {
      expect(
        nomiMezzi([
          {'id': '1', 'nome': '12'},
          {'id': '2', 'nome': '07'},
          {'id': '3', 'nome': '12'},
        ]),
        ['07', '12'],
      );
    });

    test('accetta anche stringhe semplici (la cache locale)', () {
      expect(nomiMezzi(['21', '03']), ['03', '21']);
    });

    test('scarta nomi non validi', () {
      expect(nomiMezzi(['7', '123', 'AB', '', null, 5, {'nome': 9}, ' 08 ']), ['08']);
    });
  });

  group('nomeMezzoValido', () {
    test('solo due cifre', () {
      expect(nomeMezzoValido('07'), isTrue);
      expect(nomeMezzoValido('7'), isFalse);
      expect(nomeMezzoValido('007'), isFalse);
      expect(nomeMezzoValido('1a'), isFalse);
    });
  });

  group('filtraPerMezzo', () {
    const lista = [
      MaterialeUsatoCondiviso(id: 'a', materiale: 'Garze', mezzo: '12'),
      MaterialeUsatoCondiviso(id: 'b', materiale: 'Guanti', mezzo: '07'),
      MaterialeUsatoCondiviso(id: 'c', materiale: 'Bende'),
    ];

    test('null = tutti i mezzi, compresi quelli senza mezzo', () {
      expect(filtraPerMezzo(lista, null, (m) => m.mezzo).map((m) => m.id), ['a', 'b', 'c']);
    });

    test('un mezzo mostra solo le sue righe', () {
      expect(filtraPerMezzo(lista, '12', (m) => m.mezzo).map((m) => m.id), ['a']);
      expect(filtraPerMezzo(lista, '99', (m) => m.mezzo), isEmpty);
    });
  });
}
