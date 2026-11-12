import 'package:flutter_test/flutter_test.dart';
import 'package:ambu_turni/db/models.dart';
import 'package:ambu_turni/utils/servizi_csv.dart';

void main() {
  const campi = [
    CampoServizio(id: kIdCampoSessoEta, nome: 'Sesso ed età', tipo: kCampoSessoEta, opzioni: [
      OpzioneCampo(id: 'm', nome: 'M'),
      OpzioneCampo(id: 'f', nome: 'F'),
    ]),
    CampoServizio(id: 'colore_invio', nome: 'Colore invio', tipo: kCampoColori, opzioni: [
      OpzioneCampo(id: 'giallo', nome: 'Giallo', colore: '#FDD835'),
    ]),
    CampoServizio(id: 'note', nome: 'Note paziente', tipo: kCampoTesto),
  ];

  test('intestazione, BOM, separatore e una riga per servizio', () {
    final csv = serviziInCsv([
      const RigaServizioCsv(
        data: '2026-11-10',
        numeroTurno: 12,
        associazione: 'Croce Verde',
        tipologie: 'H12 mattina',
        orario: '12:00 - 18:00',
        numeroServizio: 1,
        codiceChiamata: 'GIALLO',
        codiceUscita: 'VERDE',
        ospedale: 'Ospedale Civile',
        citta: 'Brescia',
        descrizione: 'Caduta in casa',
        campi: {
          kIdCampoSessoEta: {'sesso': 'f', 'eta': 37.5},
          'colore_invio': 'giallo',
        },
      ),
    ], campi);
    expect(csv.startsWith('﻿'), isTrue);
    final righe = csv.substring(1).split('\r\n');
    expect(righe.last, ''); // ogni riga chiusa da CRLF
    expect(righe[0],
        'Data;Turno n.;Associazione;Tipologia;Orario turno;Servizio n.;Codice chiamata;Codice uscita;'
        'Ospedale;Città;Descrizione;Sesso;Età;Colore invio;Note paziente');
    expect(righe[1],
        '10/11/2026;12;Croce Verde;H12 mattina;12:00 - 18:00;1;GIALLO;VERDE;Ospedale Civile;Brescia;'
        'Caduta in casa;F;37,5;Giallo;');
  });

  test('virgolette per separatori, virgolette e a capo; valori non validi vuoti', () {
    final csv = serviziInCsv([
      const RigaServizioCsv(
        data: '2026-11-11',
        numeroServizio: 2,
        descrizione: 'Prima riga\nseconda; con "virgolette"',
        campi: {
          kIdCampoSessoEta: {'eta': 7},
          'colore_invio': 'rosso', // valore tolto dall'elenco
          'note': 'a;b',
        },
      ),
    ], campi);
    final riga = csv.substring(1).split('\r\n')[1];
    expect(riga,
        '11/11/2026;;;;;2;;;;;"Prima riga\nseconda; con ""virgolette""";;7;;"a;b"');
  });

  test('senza servizi resta solo l\'intestazione', () {
    final csv = serviziInCsv(const [], const []);
    expect(csv, '﻿Data;Turno n.;Associazione;Tipologia;Orario turno;Servizio n.;Codice chiamata;'
        'Codice uscita;Ospedale;Città;Descrizione\r\n');
  });
}
