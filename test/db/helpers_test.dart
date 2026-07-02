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

    test('getTurni con ricerca trova per descrizione, note o descrizione servizio', () async {
      final tDescr = newId();
      final tNota = newId();
      final tServizio = newId();
      final tAltro = newId();
      await saveTurno(Turno(id: tDescr, data: '2024-08-01', associazioneId: assocId, descrizione: 'Trasporto urgente Milano'));
      await saveTurno(Turno(id: tNota, data: '2024-08-02', associazioneId: assocId, note: 'Chiamare prima Milano'));
      await saveTurno(Turno(id: tServizio, data: '2024-08-03', associazioneId: assocId));
      await saveServizio(Servizio(id: newId(), turnoId: tServizio, descrizione: 'Consegna referti Milano'));
      await saveTurno(Turno(id: tAltro, data: '2024-08-04', associazioneId: assocId, descrizione: 'Nessuna corrispondenza'));

      final risultati = await getTurni(associazioneId: assocId, ricerca: 'Milano');
      final idsTrovati = risultati.map((t) => t.id).toSet();

      expect(idsTrovati, {tDescr, tNota, tServizio});
      expect(idsTrovati.contains(tAltro), isFalse);
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

  group('CRUD materiali usati', () {
    test('saveMaterialeUsato crea riga attiva, getMaterialiUsati la trova', () async {
      await saveMateriale('Garze sterili');
      final materiale =
          (await getMateriali()).firstWhere((m) => m.nome == 'Garze sterili');
      await saveMaterialeUsato(MaterialeUsato(
        id: newId(),
        materialeId: materiale.id,
        quantita: 2,
        unita: 'confezioni',
        posizione: 'ZAINO',
      ));
      final lista = await getMaterialiUsati();
      final riga = lista.firstWhere((m) => m.materialeId == materiale.id);
      expect(riga.materialeNome, 'Garze sterili');
      expect(riga.quantita, 2);
      expect(riga.quantitaLabel, '2 confezioni');
      expect(riga.posizione, 'ZAINO');
      expect(riga.ripristinato, isFalse);
    });

    test('segnaMaterialeRipristinato la rimuove dalla lista attiva', () async {
      await saveMateriale('Flaconi soluzione fisiologica');
      final materiale = (await getMateriali())
          .firstWhere((m) => m.nome == 'Flaconi soluzione fisiologica');
      final id = newId();
      await saveMaterialeUsato(MaterialeUsato(id: id, materialeId: materiale.id));
      await segnaMaterialeRipristinato(id);
      final attivi = await getMaterialiUsati();
      expect(attivi.where((m) => m.id == id), isEmpty);
      final tutti = await getMaterialiUsati(soloAttivi: false);
      expect(tutti.firstWhere((m) => m.id == id).ripristinato, isTrue);
    });

    test('deleteMaterialeUsato rimuove la riga definitivamente', () async {
      await saveMateriale('Cerotti');
      final materiale =
          (await getMateriali()).firstWhere((m) => m.nome == 'Cerotti');
      final id = newId();
      await saveMaterialeUsato(MaterialeUsato(id: id, materialeId: materiale.id, quantita: 1));
      await deleteMaterialeUsato(id);
      final tutti = await getMaterialiUsati(soloAttivi: false);
      expect(tutti.where((m) => m.id == id), isEmpty);
    });

    test('segnaTuttiMaterialiRipristinati svuota la lista attiva', () async {
      await saveMateriale('Siringhe');
      final materiale =
          (await getMateriali()).firstWhere((m) => m.nome == 'Siringhe');
      final id1 = newId();
      final id2 = newId();
      await saveMaterialeUsato(MaterialeUsato(id: id1, materialeId: materiale.id, quantita: 3));
      await saveMaterialeUsato(MaterialeUsato(id: id2, materialeId: materiale.id, quantita: 5));
      await segnaTuttiMaterialiRipristinati();
      final attivi = await getMaterialiUsati();
      expect(attivi.where((m) => m.id == id1 || m.id == id2), isEmpty);
    });

    test('aggiornaQuantitaMaterialeUsato modifica solo la quantità', () async {
      await saveMateriale('Bende');
      final materiale =
          (await getMateriali()).firstWhere((m) => m.nome == 'Bende');
      final id = newId();
      await saveMaterialeUsato(MaterialeUsato(id: id, materialeId: materiale.id, quantita: 1));
      await aggiornaQuantitaMaterialeUsato(id, 4);
      final riga = (await getMaterialiUsati()).firstWhere((m) => m.id == id);
      expect(riga.quantita, 4);
    });

    test('deleteMateriale in uso lancia un errore (foreign key)', () async {
      await saveMateriale('Collari cervicali');
      final materiale = (await getMateriali())
          .firstWhere((m) => m.nome == 'Collari cervicali');
      await saveMaterialeUsato(MaterialeUsato(id: newId(), materialeId: materiale.id));
      expect(() => deleteMateriale(materiale.id), throwsA(anything));
    });
  });
}
