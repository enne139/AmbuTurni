// Test unitari per lib/db/helpers.dart e lib/db/models.dart.
// Usano sqflite_common_ffi con DB in-memory così non toccano il filesystem.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ambulanza_turni/db/database.dart';
import 'package:ambulanza_turni/db/helpers.dart';
import 'package:ambulanza_turni/db/models.dart';

void main() {
  setUpAll(() async {
    // Inizializza FFI e inietta il DB in-memory nel singleton di getDb().
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final db = await openTestDb();
    setDbForTesting(db);
  });

  // ---------------------------------------------------------------------------
  // Modelli — roundtrip fromMap / toMap
  // ---------------------------------------------------------------------------

  group('Modello Associazione', () {
    test('fromMap → toMap è identico', () {
      final map = {
        'id': 'a1',
        'nome': 'Croce Verde',
        'colore': null,
        'created_at': '2024-01-01T00:00:00Z',
        'updated_at': '2024-01-01T00:00:00Z',
        'is_synced': 0,
      };
      expect(Associazione.fromMap(map).toMap(), map);
    });
  });

  group('Modello Persona', () {
    test('nomeCompleto restituisce "Cognome Nome"', () {
      final p = Persona(id: 'p1', nome: 'Mario', cognome: 'Rossi');
      expect(p.nomeCompleto, 'Rossi Mario');
    });

    test('fromMap → toMap è identico', () {
      final map = {
        'id': 'p1',
        'nome': 'Mario',
        'cognome': 'Rossi',
        'created_at': null,
        'updated_at': null,
        'is_synced': 0,
      };
      expect(Persona.fromMap(map).toMap(), map);
    });
  });

  group('Modello TipologiaTurno', () {
    test('ordine default 0 quando assente nella map', () {
      final t = TipologiaTurno.fromMap({'id': 't1', 'nome': 'Ordinario'});
      expect(t.ordine, 0);
    });
  });

  group('Modello Turno', () {
    test('tipologieExtra deserializzate correttamente', () {
      final map = {
        'id': 'turno1',
        'data': '2024-06-01',
        'tipologie_extra': '["id1","id2"]',
        'num_servizi': 0,
        'is_synced': 0,
      };
      final t = Turno.fromMap(map);
      expect(t.tipologieExtra, ['id1', 'id2']);
    });

    test('tipologieExtra vuote con stringa []', () {
      final map = {'id': 'turno2', 'data': '2024-06-01', 'tipologie_extra': '[]'};
      final t = Turno.fromMap(map);
      expect(t.tipologieExtra, isEmpty);
    });

    test('cambioMeta serializzato come 0/1', () {
      final t = Turno(id: 't', data: '2024-01-01', cambioMeta: true);
      expect(t.toMap()['cambio_meta'], 1);
      final t2 = Turno(id: 't2', data: '2024-01-01');
      expect(t2.toMap()['cambio_meta'], 0);
    });
  });

  group('StatisticheData', () {
    test('oreTotali somma turni e assistenze', () {
      const s = StatisticheData(
        totTurni: 5,
        totServizi: 10,
        oreTurni: 40.5,
        totAssistenze: 3,
        oreAssistenze: 12.0,
      );
      expect(s.oreTotali, 52.5);
    });
  });

  // ---------------------------------------------------------------------------
  // CRUD anagrafiche — DB in-memory
  // ---------------------------------------------------------------------------

  group('CRUD associazioni', () {
    test('saveAssociazione crea nuova riga, getAssociazioni la restituisce', () async {
      await saveAssociazione('Test Associazione');
      final list = await getAssociazioni();
      expect(list.any((a) => a.nome == 'Test Associazione'), isTrue);
    });

    test('saveAssociazione con id aggiorna il nome', () async {
      await saveAssociazione('Originale');
      final before = await getAssociazioni();
      final a = before.firstWhere((x) => x.nome == 'Originale');
      await saveAssociazione('Aggiornata', id: a.id);
      final after = await getAssociazioni();
      expect(after.any((x) => x.nome == 'Aggiornata'), isTrue);
      expect(after.any((x) => x.nome == 'Originale'), isFalse);
    });

    test('deleteAssociazione rimuove la riga', () async {
      await saveAssociazione('DaEliminare');
      final before = await getAssociazioni();
      final a = before.firstWhere((x) => x.nome == 'DaEliminare');
      await deleteAssociazione(a.id);
      final after = await getAssociazioni();
      expect(after.any((x) => x.id == a.id), isFalse);
    });
  });

  group('CRUD persone', () {
    test('savePersona crea nuova riga', () async {
      await savePersona('Bianchi', 'Luca');
      final list = await getPersone();
      expect(list.any((p) => p.cognome == 'Bianchi' && p.nome == 'Luca'), isTrue);
    });

    test('deletePersona rimuove la riga', () async {
      await savePersona('Verdi', 'Anna');
      final before = await getPersone();
      final p = before.firstWhere((x) => x.cognome == 'Verdi');
      await deletePersona(p.id);
      final after = await getPersone();
      expect(after.any((x) => x.id == p.id), isFalse);
    });
  });

  group('CRUD turni', () {
    late String assocId;

    // setUpAll: una sola INSERT per il gruppo — il nome è UNIQUE nella tabella.
    setUpAll(() async {
      await saveAssociazione('Assoc Turni Test');
      final list = await getAssociazioni();
      assocId = list.firstWhere((a) => a.nome == 'Assoc Turni Test').id;
    });

    test('saveTurno INSERT, getTurni lo trova', () async {
      final t = Turno(id: newId(), data: '2024-07-01', associazioneId: assocId);
      await saveTurno(t);
      final list = await getTurni(associazioneId: assocId);
      expect(list.any((x) => x.id == t.id), isTrue);
    });

    test('saveTurno UPDATE non cancella i servizi', () async {
      // Crea turno e un servizio figlio.
      final tid = newId();
      final t = Turno(id: tid, data: '2024-07-02', associazioneId: assocId);
      await saveTurno(t);
      final s = Servizio(id: newId(), turnoId: tid);
      await saveServizio(s);

      // Modifica il turno (cambio data).
      await saveTurno(t.copyWith(data: '2024-07-03'));

      // Il servizio deve ancora esistere.
      final servizi = await getServizi(tid);
      expect(servizi.any((x) => x.id == s.id), isTrue);
    });

    test('deleteTurno cancella anche i servizi via CASCADE', () async {
      final tid = newId();
      final t = Turno(id: tid, data: '2024-07-04', associazioneId: assocId);
      await saveTurno(t);
      final s = Servizio(id: newId(), turnoId: tid);
      await saveServizio(s);
      await deleteTurno(tid);
      final servizi = await getServizi(tid);
      expect(servizi, isEmpty);
    });

    test('numerazione progressiva ricalcolata dopo insert', () async {
      final ids = [newId(), newId()];
      await saveTurno(Turno(id: ids[0], data: '2024-01-01', associazioneId: assocId));
      await saveTurno(Turno(id: ids[1], data: '2024-01-02', associazioneId: assocId));
      final list = await getTurni(associazioneId: assocId);
      // Ordinati per data DESC: il più recente è in testa ma ha numero progressivo maggiore.
      final nums = list.map((t) => t.numeroProgressivo).whereType<int>().toList();
      expect(nums.contains(1), isTrue);
      expect(nums.contains(2), isTrue);
    });
  });

  group('CRUD tipologie turno', () {
    test('saveTipologiaTurno crea e ordina', () async {
      await saveTipologiaTurno('Alfa');
      await saveTipologiaTurno('Beta');
      final list = await getTipologieTurno();
      final alfa = list.firstWhere((t) => t.nome == 'Alfa');
      final beta = list.firstWhere((t) => t.nome == 'Beta');
      expect(alfa.ordine < beta.ordine, isTrue);
    });

    test('spostaTipologia scambia ordine', () async {
      await saveTipologiaTurno('Prima');
      await saveTipologiaTurno('Seconda');
      final before = await getTipologieTurno();
      final idxPrima = before.indexWhere((t) => t.nome == 'Prima');
      final idxSeconda = before.indexWhere((t) => t.nome == 'Seconda');
      await spostaTipologia(idxPrima, idxSeconda);
      final after = await getTipologieTurno();
      expect(after.indexWhere((t) => t.nome == 'Prima'),
          greaterThan(after.indexWhere((t) => t.nome == 'Seconda')));
    });
  });
}
