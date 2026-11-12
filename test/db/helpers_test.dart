// Test unitari per lib/db/helpers.dart e lib/db/models.dart.
// Usano sqflite_common_ffi con DB in-memory così non toccano il filesystem.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:ambu_turni/db/database.dart';
import 'package:ambu_turni/db/helpers.dart';
import 'package:ambu_turni/db/models.dart';

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

  group('Modello Ospedale', () {
    test('fromMap → toMap è identico', () {
      final map = {
        'id': 'o1',
        'nome': 'Ospedale Test',
        'citta': 'Milano',
        'via': 'Via Roma 1',
        'lat': 45.4642,
        'lng': 9.19,
        'regione': 'Lombardia',
        'created_at': null,
        'updated_at': null,
        'is_synced': 0,
      };
      expect(Ospedale.fromMap(map).toMap(), map);
    });

    test('haCoordinate falso finché lat/lng non sono valorizzate', () {
      const o = Ospedale(id: 'o1', nome: 'X', via: 'Via Y');
      expect(o.haCoordinate, isFalse);
    });
  });

  group('Modello TipologiaTurno', () {
    test('ordine default 0 quando assente nella map', () {
      final t = TipologiaTurno.fromMap({'id': 't1', 'nome': 'Ordinario'});
      expect(t.ordine, 0);
    });
  });

  group('Modello Turno', () {
    test('tipologie deserializzate correttamente', () {
      final map = {
        'id': 'turno1',
        'data': '2024-06-01',
        'tipologie': '["id1","id2"]',
        'num_servizi': 0,
        'is_synced': 0,
      };
      final t = Turno.fromMap(map);
      expect(t.tipologie, ['id1', 'id2']);
    });

    test('tipologie vuote con stringa []', () {
      final map = {'id': 'turno2', 'data': '2024-06-01', 'tipologie': '[]'};
      final t = Turno.fromMap(map);
      expect(t.tipologie, isEmpty);
    });

    test('cambioMeta serializzato come 0/1', () {
      final t = Turno(id: 't', data: '2024-01-01', cambioMeta: true);
      expect(t.toMap()['cambio_meta'], 1);
      final t2 = Turno(id: 't2', data: '2024-01-01');
      expect(t2.toMap()['cambio_meta'], 0);
    });
  });

  group('Modello CampoServizio', () {
    const sesso = CampoServizio(id: 'sesso', nome: 'Sesso', tipo: kCampoTendina, opzioni: [
      OpzioneCampo(id: 'm', nome: 'M'),
      OpzioneCampo(id: 'f', nome: 'F'),
    ]);

    test('fromMap → toMap è identico, opzioni e visibilità comprese', () {
      final map = {
        'id': 'c1',
        'nome': 'Colore invio',
        'tipo': kCampoColori,
        'opzioni': '[{"id":"verde","nome":"Verde","colore":"#43A047"}]',
        'visibile': 0,
        'ordine': 2,
        'created_at': '2026-11-12T00:00:00Z',
        'updated_at': '2026-11-12T00:00:00Z',
      };
      final c = CampoServizio.fromMap(map);
      expect(c.visibile, isFalse);
      expect(c.opzioni.single.colore, '#43A047');
      expect(c.toMap(), map);
    });

    test('opzioni rovinate: il campo si legge lo stesso, senza valori', () {
      final c = CampoServizio.fromMap({'id': 'c', 'nome': 'X', 'tipo': kCampoTendina, 'opzioni': '{non json'});
      expect(c.opzioni, isEmpty);
      expect(c.visibile, isTrue);
    });

    test('valoreValido ed etichetta per ogni tipo', () {
      expect(sesso.etichetta('f'), 'F');
      expect(sesso.valoreValido('x'), isFalse); // opzione che non c'è più
      expect(sesso.etichetta('x'), isNull);
      const eta = CampoServizio(id: 'eta', nome: 'Età', tipo: kCampoNumero);
      expect(eta.etichetta(45), '45');
      expect(eta.etichetta(37.5), '37,5');
      expect(eta.valoreValido('45'), isFalse); // un testo non è un numero
      const nota = CampoServizio(id: 'n', nome: 'Nota', tipo: kCampoTesto);
      expect(nota.etichetta('ok'), 'ok');
      expect(nota.valoreValido(''), isFalse);
      expect(nota.valoreValido(3), isFalse);
    });

    test('parseNumeroCampo e formatNumeroCampo', () {
      expect(parseNumeroCampo(' 45 '), 45);
      expect(parseNumeroCampo('37,5'), 37.5);
      expect(parseNumeroCampo('37.5'), 37.5);
      expect(parseNumeroCampo('abc'), isNull);
      expect(parseNumeroCampo(''), isNull);
      expect(formatNumeroCampo(45.0), '45');
      expect(formatNumeroCampo(12), '12');
    });

    test('campo speciale sesso ed età: tiene la parte buona del valore', () {
      const speciale = CampoServizio(id: kIdCampoSessoEta, nome: 'Sesso ed età', tipo: kCampoSessoEta, opzioni: [
        OpzioneCampo(id: 'm', nome: 'M'),
        OpzioneCampo(id: 'f', nome: 'F'),
      ]);
      expect(speciale.speciale, isTrue);
      expect(speciale.etichetta({'sesso': 'f', 'eta': 45}), 'F · 45 anni');
      expect(speciale.etichetta({'eta': 7}), '7 anni');
      // Sesso non più tra i valori: resta l'età.
      expect(speciale.pulisci({'sesso': 'x', 'eta': 45}), {'eta': 45});
      expect(speciale.pulisci({'sesso': 'x'}), isNull);
      expect(speciale.pulisci('f'), isNull); // non è una mappa
      expect(speciale.sessoDi({'sesso': 'm'})!.nome, 'M');
      expect(speciale.etaDi({'eta': 37.5}), 37.5);
      expect(stessoValoreCampo({'eta': 1, 'sesso': 'm'}, {'sesso': 'm', 'eta': 1}), isTrue);
      expect(stessoValoreCampo({'eta': 1}, {'sesso': 'm', 'eta': 1}), isFalse);
    });

    test('decodificaCampi: vuoto, rovinato o assente diventa una mappa vuota', () {
      expect(decodificaCampi('{"eta":45,"sesso":"m"}'), {'eta': 45, 'sesso': 'm'});
      expect(decodificaCampi(null), isEmpty);
      expect(decodificaCampi(''), isEmpty);
      expect(decodificaCampi('[1,2]'), isEmpty);
      expect(decodificaCampi('{rotto'), isEmpty);
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

    test('savePersona restituisce l\'id giusto anche con omonimi', () async {
      // Due persone con lo stesso nome: l'id restituito deve identificare
      // la riga appena creata, non la prima trovata per nome.
      final id1 = await savePersona('Omonimo', 'Test');
      final id2 = await savePersona('Omonimo', 'Test');
      expect(id1, isNot(id2));
      final list = await getPersone();
      expect(list.where((p) => p.cognome == 'Omonimo').length, 2);
      expect(list.any((p) => p.id == id2), isTrue);
      // In modalità update l'id restituito è quello passato.
      expect(await savePersona('Omonimo', 'Rinominato', id: id1), id1);
    });
  });

  group('CRUD ospedali', () {
    test('saveOspedale salva via, getOspedali la restituisce', () async {
      await saveOspedale('Ospedale Test', 'Milano', via: 'Via Roma 1');
      final list = await getOspedali();
      final o = list.firstWhere((x) => x.nome == 'Ospedale Test');
      expect(o.via, 'Via Roma 1');
      expect(o.citta, 'Milano');
      expect(o.haCoordinate, isFalse);
    });

    test('saveOspedale in modifica non tocca lat/lng già geocodificate',
        () async {
      final id = await saveOspedale('Ospedale Coord', 'Roma', via: 'Via A');
      await aggiornaGeocodingOspedale(id, lat: 41.9, lng: 12.5);
      // Modifica che non cambia l'indirizzo (es. solo il nome).
      await saveOspedale('Ospedale Coord Rinominato', 'Roma', id: id, via: 'Via A');
      final o = (await getOspedali()).firstWhere((x) => x.id == id);
      expect(o.nome, 'Ospedale Coord Rinominato');
      expect(o.lat, 41.9);
      expect(o.lng, 12.5);
    });

    test('aggiornaGeocodingOspedale imposta lat/lng', () async {
      final id = await saveOspedale('Ospedale Geo', null, via: 'Via B');
      await aggiornaGeocodingOspedale(id, lat: 45.46, lng: 9.19);
      final o = (await getOspedali()).firstWhere((x) => x.id == id);
      expect(o.haCoordinate, isTrue);
      expect(o.lat, 45.46);
      expect(o.lng, 9.19);
    });

    test('aggiornaGeocodingOspedale imposta la regione senza toccare lat/lng esistenti', () async {
      final id = await saveOspedale('Ospedale Regione', 'Bologna', via: 'Via C');
      await aggiornaGeocodingOspedale(id, lat: 44.49, lng: 11.34);
      await aggiornaGeocodingOspedale(id, regione: 'Emilia-Romagna');
      final o = (await getOspedali()).firstWhere((x) => x.id == id);
      expect(o.regione, 'Emilia-Romagna');
      expect(o.lat, 44.49);
      expect(o.lng, 11.34);
    });

    test('deleteOspedale rimuove la riga', () async {
      final id = await saveOspedale('Ospedale Da Eliminare', null);
      await deleteOspedale(id);
      final after = await getOspedali();
      expect(after.any((x) => x.id == id), isFalse);
    });
  });

  group('upsertOspedali', () {
    test('crea le righe nuove (per nome) e conta creati/aggiornati/scartati', () async {
      final esito = await upsertOspedali([
        {'nome': 'Upsert Nuovo 1', 'citta': 'Milano', 'via': 'Via A', 'lat': 45.1, 'lng': 9.1},
        {'nome': 'Upsert Nuovo 2', 'citta': 'Roma'},
      ]);
      expect(esito.creati, 2);
      expect(esito.aggiornati, 0);
      expect(esito.scartati, 0);
      final lista = await getOspedali();
      final o = lista.firstWhere((x) => x.nome == 'Upsert Nuovo 1');
      expect(o.citta, 'Milano');
      expect(o.via, 'Via A');
      expect(o.lat, 45.1);
      expect(o.lng, 9.1);
    });

    test('aggiorna una riga già esistente con lo stesso nome, non ne crea una seconda', () async {
      await saveOspedale('Upsert Esistente', 'Torino', via: 'Via Vecchia');
      final esito = await upsertOspedali([
        {'nome': 'Upsert Esistente', 'citta': 'Torino', 'via': 'Via Nuova', 'lat': 45.0, 'lng': 7.6},
      ]);
      expect(esito.creati, 0);
      expect(esito.aggiornati, 1);
      final lista = await getOspedali();
      expect(lista.where((x) => x.nome == 'Upsert Esistente').length, 1);
      final o = lista.firstWhere((x) => x.nome == 'Upsert Esistente');
      expect(o.via, 'Via Nuova');
      expect(o.lat, 45.0);
    });

    test('righe senza nome, o non mappe, vengono scartate senza interrompere le altre', () async {
      final esito = await upsertOspedali([
        {'nome': '', 'citta': 'Milano'},
        {'citta': 'Milano'},
        'stringa non valida',
        {'nome': 'Upsert Valido', 'citta': 'Milano'},
      ]);
      expect(esito.creati, 1);
      expect(esito.scartati, 3);
      final lista = await getOspedali();
      expect(lista.any((x) => x.nome == 'Upsert Valido'), isTrue);
    });

    test('senza lat/lng nella riga non tocca eventuali coordinate esistenti', () async {
      final id = await saveOspedale('Upsert Coord', 'Napoli', via: 'Via X');
      await aggiornaGeocodingOspedale(id, lat: 40.85, lng: 14.27);
      await upsertOspedali([
        {'nome': 'Upsert Coord', 'citta': 'Napoli', 'via': 'Via X'},
      ]);
      final o = (await getOspedali()).firstWhere((x) => x.id == id);
      expect(o.lat, 40.85);
      expect(o.lng, 14.27);
    });

    test('scrive la regione dalla riga se presente', () async {
      final esito = await upsertOspedali([
        {'nome': 'Upsert Regione', 'citta': 'Bologna', 'regione': 'Emilia-Romagna'},
      ]);
      expect(esito.creati, 1);
      final o = (await getOspedali()).firstWhere((x) => x.nome == 'Upsert Regione');
      expect(o.regione, 'Emilia-Romagna');
    });
  });

  group('upsertMateriali', () {
    test('crea i materiali nuovi (per nome) e conta creati/scartati', () async {
      final esito = await upsertMateriali(['Upsert Garze', 'Upsert Guanti', '']);
      expect(esito.creati, 2);
      expect(esito.scartati, 1);
      final lista = await getMateriali();
      expect(lista.map((m) => m.nome), containsAll(['Upsert Garze', 'Upsert Guanti']));
    });

    test('un materiale già in catalogo (case-insensitive) non viene duplicato', () async {
      await saveMateriale('Upsert Bende');
      final esito = await upsertMateriali(['upsert bende', 'Upsert Cerotti']);
      expect(esito.creati, 1);
      final lista = await getMateriali();
      expect(lista.where((m) => m.nome.toLowerCase() == 'upsert bende').length, 1);
    });

    test('accetta anche righe in formato mappa {"nome": ...}', () async {
      final esito = await upsertMateriali([
        {'nome': 'Upsert Siringhe'},
        {'citta': 'senza nome'},
      ]);
      expect(esito.creati, 1);
      expect(esito.scartati, 1);
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

    test('cambiare associazione rinumera anche quella di provenienza', () async {
      // Associazioni dedicate per non interferire con gli altri test del gruppo.
      await saveAssociazione('Assoc Sposta A');
      await saveAssociazione('Assoc Sposta B');
      final assocs = await getAssociazioni();
      final idA = assocs.firstWhere((a) => a.nome == 'Assoc Sposta A').id;
      final idB = assocs.firstWhere((a) => a.nome == 'Assoc Sposta B').id;

      final t1 = Turno(id: newId(), data: '2025-01-01', associazioneId: idA);
      final t2 = Turno(id: newId(), data: '2025-01-02', associazioneId: idA);
      await saveTurno(t1);
      await saveTurno(t2);

      // Sposta il turno più vecchio (numero 1) sull'associazione B: il turno
      // rimasto in A deve scalare da 2 a 1, non restare con un buco.
      await saveTurno(t1.copyWith(associazioneId: idB));

      final turniA = await getTurni(associazioneId: idA);
      final turniB = await getTurni(associazioneId: idB);
      expect(turniA.single.numeroProgressivo, 1);
      expect(turniB.single.numeroProgressivo, 1);
    });

    test('getTurni con ricerca trova per orario, note o descrizione servizio', () async {
      final tOrario = newId();
      final tNota = newId();
      final tServizio = newId();
      final tAltro = newId();
      await saveTurno(Turno(id: tOrario, data: '2024-08-01', associazioneId: assocId, orario: '14:00 - 20:00'));
      await saveTurno(Turno(id: tNota, data: '2024-08-02', associazioneId: assocId, note: 'Rientro alle 20:00'));
      await saveTurno(Turno(id: tServizio, data: '2024-08-03', associazioneId: assocId));
      await saveServizio(Servizio(id: newId(), turnoId: tServizio, descrizione: 'Dimesso alle 20:00'));
      await saveTurno(Turno(id: tAltro, data: '2024-08-04', associazioneId: assocId, orario: '08:00 - 14:00'));

      final risultati = await getTurni(associazioneId: assocId, ricerca: '20:00');
      final idsTrovati = risultati.map((t) => t.id).toSet();

      expect(idsTrovati, {tOrario, tNota, tServizio});
      expect(idsTrovati.contains(tAltro), isFalse);
    });

    test('saveTurno salva e rilegge l\'orario', () async {
      final id = newId();
      await saveTurno(Turno(id: id, data: '2024-08-05', associazioneId: assocId, orario: '12:00 - 18:00'));
      expect((await getTurnoById(id))!.orario, '12:00 - 18:00');
    });
  });

  group('CRUD assistenze', () {
    late String assocId;

    setUpAll(() async {
      await saveAssociazione('Assoc Assistenze Test', colore: '#43A047');
      final list = await getAssociazioni();
      assocId = list.firstWhere((a) => a.nome == 'Assoc Assistenze Test').id;
    });

    test('getAssistenze con ricerca trova per orario o note', () async {
      final aOrario = newId();
      final aNota = newId();
      final aAltra = newId();
      await saveAssistenza(Assistenza(
          id: aOrario, data: '2024-09-01', associazioneId: assocId,
          orario: '14:00 - 19:00'));
      await saveAssistenza(Assistenza(
          id: aNota, data: '2024-09-02', associazioneId: assocId,
          note: 'Ritrovo allo stadio alle 14:00'));
      await saveAssistenza(Assistenza(
          id: aAltra, data: '2024-09-03', associazioneId: assocId,
          orario: '20:00 - 23:00'));

      final risultati = await getAssistenze(associazioneId: assocId, ricerca: '14:00');
      expect(risultati.map((a) => a.id).toSet(), {aOrario, aNota});
      expect((await getAssistenzaById(aOrario))!.orario, '14:00 - 19:00');

      // Ricerca di soli spazi = nessun filtro: restano tutte.
      final tutte = await getAssistenze(associazioneId: assocId, ricerca: '  ');
      expect(tutte.map((a) => a.id).toSet(), {aOrario, aNota, aAltra});
    });

    test('getAssistenze espone il colore dell\'associazione (pallini calendario)', () async {
      final assistenze = await getAssistenze(associazioneId: assocId);
      expect(assistenze, isNotEmpty);
      expect(assistenze.first.associazioneColore, '#43A047');
    });
  });

  group('Campi personalizzati dei servizi', () {
    late String turnoId;

    setUpAll(() async {
      turnoId = newId();
      await saveTurno(Turno(id: turnoId, data: '2026-11-10'));
    });

    /// Crea un servizio del turno di prova coi valori [campi] e ne restituisce l'id.
    Future<String> servizioCon(Map<String, dynamic> campi) async {
      final id = newId();
      await saveServizio(Servizio(id: id, turnoId: turnoId, campi: campi));
      return id;
    }

    Future<Map<String, dynamic>> campiDi(String servizioId) async =>
        (await getServizi(turnoId)).firstWhere((s) => s.id == servizioId).campi;

    test('un DB nuovo parte con Sesso ed età (speciale) e Colore invio', () async {
      final campi = await getCampiServizio();
      expect(campi.take(2).map((c) => c.nome), ['Sesso ed età', 'Colore invio']);
      final sessoEta = campi[0], colore = campi[1];
      expect(sessoEta.id, kIdCampoSessoEta);
      expect(sessoEta.tipo, kCampoSessoEta);
      expect(sessoEta.opzioni.map((o) => o.nome), ['M', 'F', 'A']);
      expect(colore.tipo, kCampoColori);
      expect(colore.opzioni.map((o) => o.nome), ['Verde', 'Giallo', 'Rosso']);
      expect(colore.opzioni.every((o) => o.colore != null), isTrue);
      expect(campi.take(2).every((c) => c.visibile), isTrue);
    });

    test('i valori si salvano e si rileggono col servizio', () async {
      final id = await servizioCon({kIdCampoSessoEta: {'sesso': 'f', 'eta': 45}, 'colore_invio': 'giallo'});
      expect(await campiDi(id), {kIdCampoSessoEta: {'sesso': 'f', 'eta': 45}, 'colore_invio': 'giallo'});
    });

    test('il campo speciale non si elimina; togliere un sesso tiene l\'età', () async {
      final speciale = (await getCampiServizio()).firstWhere((c) => c.speciale);
      final senzaF = speciale.copyWith(opzioni: speciale.opzioni.where((o) => o.id != 'f').toList());
      // Il DB dei test è condiviso: conta anche i servizi dei test precedenti.
      final giaPrima = await contaValoriNonPiuValidi(senzaF);
      final conF = await servizioCon({kIdCampoSessoEta: {'sesso': 'f', 'eta': 30}});
      final soloF = await servizioCon({kIdCampoSessoEta: {'sesso': 'f'}});
      final conM = await servizioCon({kIdCampoSessoEta: {'sesso': 'm', 'eta': 60}});

      await expectLater(deleteCampoServizio(speciale.id), throwsStateError);
      expect((await getCampiServizio()).any((c) => c.id == speciale.id), isTrue);

      expect(await contaValoriNonPiuValidi(senzaF), giaPrima + 2);
      await saveCampoServizio(senzaF);
      expect(await campiDi(conF), {kIdCampoSessoEta: {'eta': 30}});
      expect(await campiDi(soloF), isEmpty);
      expect(await campiDi(conM), {kIdCampoSessoEta: {'sesso': 'm', 'eta': 60}});
      await saveCampoServizio(speciale); // rimette F per gli altri test
    });

    test('un campo nuovo va in fondo; rinominare un valore non tocca i servizi', () async {
      final campo = CampoServizio(id: newId(), nome: 'Mezzo', tipo: kCampoTendina, opzioni: const [
        OpzioneCampo(id: 'o1', nome: 'Ambulanza'),
        OpzioneCampo(id: 'o2', nome: 'Auto medica'),
      ]);
      await saveCampoServizio(campo);
      expect((await getCampiServizio()).last.id, campo.id);

      final servizio = await servizioCon({campo.id: 'o2'});
      final rinominato = campo.copyWith(opzioni: const [
        OpzioneCampo(id: 'o1', nome: 'Ambulanza'),
        OpzioneCampo(id: 'o2', nome: 'Automedica'),
      ]);
      expect(await contaValoriNonPiuValidi(rinominato), 0);
      await saveCampoServizio(rinominato);
      final salvato = (await getCampiServizio()).firstWhere((c) => c.id == campo.id);
      expect(salvato.etichetta((await campiDi(servizio))[campo.id]), 'Automedica');
    });

    test('togliere un valore dall\'elenco lo toglie solo dai servizi che lo usavano', () async {
      final campo = CampoServizio(id: newId(), nome: 'Esito', tipo: kCampoTendina, opzioni: const [
        OpzioneCampo(id: 'a', nome: 'Trasportato'),
        OpzioneCampo(id: 'b', nome: 'Rifiuto'),
      ]);
      await saveCampoServizio(campo);
      final conA = await servizioCon({campo.id: 'a', 'eta': 30});
      final conB = await servizioCon({campo.id: 'b'});

      final senzaB = campo.copyWith(opzioni: const [OpzioneCampo(id: 'a', nome: 'Trasportato')]);
      expect(await contaValoriNonPiuValidi(senzaB), 1);
      await saveCampoServizio(senzaB);

      expect(await campiDi(conA), {campo.id: 'a', 'eta': 30});
      expect(await campiDi(conB), isEmpty);
    });

    test('da tendina a colori i valori restano, da testo a numero vengono tolti', () async {
      final scelta = CampoServizio(id: newId(), nome: 'Priorità', tipo: kCampoTendina, opzioni: const [
        OpzioneCampo(id: 'alta', nome: 'Alta'),
      ]);
      final testo = CampoServizio(id: newId(), nome: 'Peso', tipo: kCampoTesto);
      await saveCampoServizio(scelta);
      await saveCampoServizio(testo);
      final id = await servizioCon({scelta.id: 'alta', testo.id: 'circa 80'});

      final aColori = scelta.copyWith(tipo: kCampoColori, opzioni: const [
        OpzioneCampo(id: 'alta', nome: 'Alta', colore: '#E53935'),
      ]);
      expect(await contaValoriNonPiuValidi(aColori), 0);
      await saveCampoServizio(aColori);

      final aNumero = testo.copyWith(tipo: kCampoNumero);
      expect(await contaValoriNonPiuValidi(aNumero), 1);
      await saveCampoServizio(aNumero);

      expect(await campiDi(id), {scelta.id: 'alta'});
    });

    test('nascondere un campo tiene i valori, eliminarlo li toglie', () async {
      final campo = CampoServizio(id: newId(), nome: 'Note paziente', tipo: kCampoTesto);
      await saveCampoServizio(campo);
      final id = await servizioCon({campo.id: 'allergico', 'eta': 70});

      await setCampoServizioVisibile(campo.id, false);
      expect((await getCampiServizio()).firstWhere((c) => c.id == campo.id).visibile, isFalse);
      expect((await campiDi(id))[campo.id], 'allergico');

      expect(await contaServiziConCampo(campo.id), 1);
      await deleteCampoServizio(campo.id);
      expect((await getCampiServizio()).any((c) => c.id == campo.id), isFalse);
      expect(await campiDi(id), {'eta': 70});
      expect(await contaServiziConCampo(campo.id), 0);
    });

    test('spostaCampoServizio scambia due campi vicini', () async {
      final prima = await getCampiServizio();
      await spostaCampoServizio(0, 1);
      final dopo = await getCampiServizio();
      expect(dopo[0].id, prima[1].id);
      expect(dopo[1].id, prima[0].id);
      expect(dopo.skip(2).map((c) => c.id), prima.skip(2).map((c) => c.id));
      await spostaCampoServizio(0, 1); // rimette com'era per gli altri test
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
    });

    test('segnaMaterialeRipristinato elimina la riga (nessuno storico)', () async {
      await saveMateriale('Flaconi soluzione fisiologica');
      final materiale = (await getMateriali())
          .firstWhere((m) => m.nome == 'Flaconi soluzione fisiologica');
      final id = newId();
      await saveMaterialeUsato(MaterialeUsato(id: id, materialeId: materiale.id));
      await segnaMaterialeRipristinato(id);
      final tutti = await getMaterialiUsati();
      expect(tutti.where((m) => m.id == id), isEmpty);
    });

    test('deleteMaterialeUsato rimuove la riga definitivamente', () async {
      await saveMateriale('Cerotti');
      final materiale =
          (await getMateriali()).firstWhere((m) => m.nome == 'Cerotti');
      final id = newId();
      await saveMaterialeUsato(MaterialeUsato(id: id, materialeId: materiale.id, quantita: 1));
      await deleteMaterialeUsato(id);
      final tutti = await getMaterialiUsati();
      expect(tutti.where((m) => m.id == id), isEmpty);
    });

    test('segnaMaterialiRipristinati elimina solo gli id indicati', () async {
      // "Ripristina tutto" con un mezzo scelto deve togliere solo i
      // materiali di quel mezzo, non quelli degli altri.
      await saveMateriale('Siringhe');
      final materiale =
          (await getMateriali()).firstWhere((m) => m.nome == 'Siringhe');
      final id1 = newId();
      final id2 = newId();
      final idAltroMezzo = newId();
      await saveMaterialeUsato(MaterialeUsato(id: id1, materialeId: materiale.id, quantita: 3, mezzo: '12'));
      await saveMaterialeUsato(MaterialeUsato(id: id2, materialeId: materiale.id, quantita: 5, mezzo: '12'));
      await saveMaterialeUsato(MaterialeUsato(id: idAltroMezzo, materialeId: materiale.id, mezzo: '07'));
      await segnaMaterialiRipristinati([id1, id2]);
      final attivi = await getMaterialiUsati();
      expect(attivi.where((m) => m.id == id1 || m.id == id2), isEmpty);
      expect(attivi.where((m) => m.id == idAltroMezzo), hasLength(1));
    });

    test('segnaMaterialiRipristinati con lista vuota non tocca nulla', () async {
      await saveMateriale('Mascherine');
      final materiale =
          (await getMateriali()).firstWhere((m) => m.nome == 'Mascherine');
      final id = newId();
      await saveMaterialeUsato(MaterialeUsato(id: id, materialeId: materiale.id));
      await segnaMaterialiRipristinati([]);
      expect((await getMaterialiUsati()).where((m) => m.id == id), hasLength(1));
    });

    test('mezzo salvato e riletto, modificabile e azzerabile', () async {
      await saveMateriale('Lacci emostatici');
      final materiale =
          (await getMateriali()).firstWhere((m) => m.nome == 'Lacci emostatici');
      final id = newId();
      await saveMaterialeUsato(MaterialeUsato(id: id, materialeId: materiale.id, mezzo: '12'));
      var riga = (await getMaterialiUsati()).firstWhere((m) => m.id == id);
      expect(riga.mezzo, '12');
      await saveMaterialeUsato(MaterialeUsato(id: id, materialeId: materiale.id, mezzo: '07', createdAt: riga.createdAt));
      riga = (await getMaterialiUsati()).firstWhere((m) => m.id == id);
      expect(riga.mezzo, '07');
      await saveMaterialeUsato(MaterialeUsato(id: id, materialeId: materiale.id, createdAt: riga.createdAt));
      riga = (await getMaterialiUsati()).firstWhere((m) => m.id == id);
      expect(riga.mezzo, isNull);
    });

    test('un materiale nuovo riceve created_at, che la modifica conserva', () async {
      await saveMateriale('Teli isotermici');
      final materiale =
          (await getMateriali()).firstWhere((m) => m.nome == 'Teli isotermici');
      final id = newId();
      await saveMaterialeUsato(MaterialeUsato(id: id, materialeId: materiale.id));
      final creato = (await getMaterialiUsati()).firstWhere((m) => m.id == id);
      expect(creato.createdAt, isNotNull);
      await saveMaterialeUsato(MaterialeUsato(
          id: id, materialeId: materiale.id, quantita: 2, createdAt: creato.createdAt));
      final modificato = (await getMaterialiUsati()).firstWhere((m) => m.id == id);
      expect(modificato.createdAt, creato.createdAt);
    });

    test('copyWith della quantità conserva il mezzo', () {
      const mu = MaterialeUsato(id: 'x', materialeId: 'm', quantita: 1, mezzo: '12');
      expect(mu.copyWith(quantita: 3).mezzo, '12');
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

    test('quantita < 1 rifiutata dal CHECK dello schema (v7)', () async {
      // Il vincolo vive nel DB, non solo nei clamp della UI: una scrittura
      // difettosa non può salvare quantità zero o negative.
      await saveMateriale('Guanti sterili');
      final materiale =
          (await getMateriali()).firstWhere((m) => m.nome == 'Guanti sterili');
      final id = newId();
      await saveMaterialeUsato(MaterialeUsato(id: id, materialeId: materiale.id, quantita: 1));
      await expectLater(
          aggiornaQuantitaMaterialeUsato(id, 0), throwsA(isA<Exception>()));
      // La riga esistente resta intatta.
      final riga = (await getMaterialiUsati()).firstWhere((m) => m.id == id);
      expect(riga.quantita, 1);
    });

    test('deleteMateriale in uso elimina anche gli utilizzi collegati (CASCADE)', () async {
      await saveMateriale('Collari cervicali');
      final materiale = (await getMateriali())
          .firstWhere((m) => m.nome == 'Collari cervicali');
      final idUsato = newId();
      await saveMaterialeUsato(MaterialeUsato(id: idUsato, materialeId: materiale.id));
      await deleteMateriale(materiale.id);
      expect((await getMateriali()).where((m) => m.id == materiale.id), isEmpty);
      expect((await getMaterialiUsati()).where((m) => m.id == idUsato), isEmpty);
    });
  });

  group('Conteggi anagrafiche (badge in AnagraficheScreen)', () {
    test('contaOccorrenzePersone: stesso ruolo doppio nello stesso turno conta una volta, sommato alle assistenze', () async {
      await saveAssociazione('Assoc Conteggio Persone');
      final assocId = (await getAssociazioni())
          .firstWhere((a) => a.nome == 'Assoc Conteggio Persone').id;
      final personaId = await savePersona('ContaPersona', 'Test');

      // Stessa persona in due ruoli dello stesso turno: deve contare 1, non 2
      // (stessa semantica OR di getTurniPerPersona).
      await saveTurno(Turno(
        id: newId(),
        data: '2024-10-01',
        associazioneId: assocId,
        eq1AutistaId: personaId,
        eq2TerzoId: personaId,
      ));
      // Un secondo turno con la persona in un solo ruolo.
      await saveTurno(Turno(
        id: newId(),
        data: '2024-10-02',
        associazioneId: assocId,
        eq1CsId: personaId,
      ));
      // Un'assistenza.
      await saveAssistenza(Assistenza(
        id: newId(),
        data: '2024-10-03',
        associazioneId: assocId,
        eq1AutistaId: personaId,
      ));

      final conteggi = await contaOccorrenzePersone();
      expect(conteggi[personaId], 3);
    });

    test('contaOccorrenzeOspedali: più servizi con lo stesso ospedale nello stesso turno contano una volta', () async {
      await saveAssociazione('Assoc Conteggio Ospedali');
      final assocId = (await getAssociazioni())
          .firstWhere((a) => a.nome == 'Assoc Conteggio Ospedali').id;
      final ospedaleId = await saveOspedale('Conta Ospedale', 'Milano');

      final t1 = newId();
      await saveTurno(Turno(id: t1, data: '2024-10-10', associazioneId: assocId));
      await saveServizio(Servizio(id: newId(), turnoId: t1, ospedaleId: ospedaleId));
      await saveServizio(Servizio(id: newId(), turnoId: t1, ospedaleId: ospedaleId));

      final t2 = newId();
      await saveTurno(Turno(id: t2, data: '2024-10-11', associazioneId: assocId));
      await saveServizio(Servizio(id: newId(), turnoId: t2, ospedaleId: ospedaleId));

      final conteggi = await contaOccorrenzeOspedali();
      expect(conteggi[ospedaleId], 2);
    });

    test('contaOccorrenzeAssociazioni: somma turni + assistenze', () async {
      await saveAssociazione('Assoc Conteggio Totale');
      final assocId = (await getAssociazioni())
          .firstWhere((a) => a.nome == 'Assoc Conteggio Totale').id;
      await saveTurno(Turno(id: newId(), data: '2024-10-15', associazioneId: assocId));
      await saveTurno(Turno(id: newId(), data: '2024-10-16', associazioneId: assocId));
      await saveAssistenza(Assistenza(id: newId(), data: '2024-10-17', associazioneId: assocId));

      final conteggi = await contaOccorrenzeAssociazioni();
      expect(conteggi[assocId], 3);
    });

    test('contaOccorrenzeTipologie: conta i turni per ciascun id nella colonna multi-valore', () async {
      await saveAssociazione('Assoc Conteggio Tipologie');
      final assocId = (await getAssociazioni())
          .firstWhere((a) => a.nome == 'Assoc Conteggio Tipologie').id;
      await saveTipologiaTurno('Conta Tipologia A');
      await saveTipologiaTurno('Conta Tipologia B');
      final tipologie = await getTipologieTurno();
      final idA = tipologie.firstWhere((t) => t.nome == 'Conta Tipologia A').id;
      final idB = tipologie.firstWhere((t) => t.nome == 'Conta Tipologia B').id;

      await saveTurno(Turno(id: newId(), data: '2024-10-20', associazioneId: assocId, tipologie: [idA, idB]));
      await saveTurno(Turno(id: newId(), data: '2024-10-21', associazioneId: assocId, tipologie: [idA]));
      // Turno senza tipologie: non deve far fallire il parsing degli altri.
      await saveTurno(Turno(id: newId(), data: '2024-10-22', associazioneId: assocId));

      final conteggi = await contaOccorrenzeTipologie();
      expect(conteggi[idA], 2);
      expect(conteggi[idB], 1);
    });
  });
}
