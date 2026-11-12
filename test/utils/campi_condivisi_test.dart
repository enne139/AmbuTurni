import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ambu_turni/db/models.dart';
import 'package:ambu_turni/utils/campi_condivisi.dart';

const _speciale = CampoServizio(id: kIdCampoSessoEta, nome: 'Sesso ed età', tipo: kCampoSessoEta, opzioni: [
  OpzioneCampo(id: 'm', nome: 'M'),
  OpzioneCampo(id: 'f', nome: 'F'),
  OpzioneCampo(id: 'a', nome: 'A'),
]);
const _colore = CampoServizio(id: 'colore_invio', nome: 'Colore invio', tipo: kCampoColori, ordine: 1, opzioni: [
  OpzioneCampo(id: 'verde', nome: 'Verde', colore: '#43A047'),
  OpzioneCampo(id: 'giallo', nome: 'Giallo', colore: '#FDD835'),
]);

void main() {
  group('file della lista dei campi', () {
    test('esporta e rilegge la stessa lista, nell\'ordine', () {
      final json = campiInJson([_colore, _speciale], adesso: DateTime.utc(2026, 11, 12));
      final payload = jsonDecode(json) as Map<String, dynamic>;
      expect(payload['formato'], kFormatoCampi);
      final letti = campiDaJson(json);
      expect(letti.scartati, 0);
      expect(letti.campi.map((c) => c.id), [kIdCampoSessoEta, 'colore_invio']);
      expect(letti.campi.last.opzioni.first.colore, '#43A047');
      expect(letti.campi.first.speciale, isTrue);
    });

    test('legge anche un backup completo (tabella campi_servizio)', () {
      final backup = jsonEncode({
        'version': 2,
        'campi_servizio': [
          {'id': 'x', 'nome': 'Peso', 'tipo': 'NUMERO', 'opzioni': '[]', 'visibile': 0, 'ordine': 0},
        ],
      });
      final c = campiDaJson(backup).campi.single;
      expect(c.nome, 'Peso');
      expect(c.visibile, isFalse);
    });

    test('voci rovinate scartate, file sbagliati rifiutati', () {
      final letti = campiDaJson(jsonEncode({
        'formato': kFormatoCampi,
        'campi': [
          {'nome': 'Senza tipo'},
          {'nome': 'Tipo strano', 'tipo': 'BOH'},
          {'nome': 'Note', 'tipo': 'TESTO'}, // senza id: ne riceve uno
          'non una mappa',
        ],
      }));
      expect(letti.scartati, 3);
      expect(letti.campi.single.id, isNotEmpty);
      expect(() => campiDaJson('{rotto'), throwsFormatException);
      expect(() => campiDaJson(jsonEncode({'ospedali': []})), throwsFormatException);
      expect(() => campiDaJson(jsonEncode({'formato': 'altro', 'campi': []})), throwsFormatException);
    });
  });

  group('unisciCampi', () {
    test('aggiorna i campi uguali, aggiunge i nuovi, tiene quelli solo locali', () {
      const mio = CampoServizio(id: 'mio', nome: 'Cosa', tipo: kCampoTesto, ordine: 2);
      final esito = unisciCampi([_speciale, _colore, mio], [
        const CampoServizio(id: 'altro-id', nome: 'colore INVIO', tipo: kCampoColori, opzioni: [
          OpzioneCampo(id: 'v2', nome: 'verde', colore: '#00FF00'),
          OpzioneCampo(id: 'r2', nome: 'Rosso', colore: '#FF0000'),
        ]),
        const CampoServizio(id: 'nuovo', nome: 'Peso', tipo: kCampoNumero, visibile: false),
      ]);
      expect(esito.aggiornati, 1);
      expect(esito.nuovi, 1);
      expect(esito.saltati, isEmpty);
      // Ordine del file, poi i campi solo del dispositivo.
      expect(esito.campi.map((c) => c.id), ['colore_invio', 'nuovo', kIdCampoSessoEta, 'mio']);
      expect(esito.campi.map((c) => c.ordine), [0, 1, 2, 3]);

      final colore = esito.campi.first;
      expect(colore.nome, 'colore INVIO');
      // Verde riconosciuto per nome: tiene l'id del dispositivo, prende il
      // colore del file; Rosso è nuovo; Giallo c'era solo qui e resta.
      expect(colore.opzioni.map((o) => '${o.id}:${o.nome}:${o.colore}'),
          ['verde:verde:#00FF00', 'r2:Rosso:#FF0000', 'giallo:Giallo:#FDD835']);
      expect(esito.campi[1].visibile, isFalse);
    });

    test('tipo incompatibile: il campo del file si salta, quello locale resta', () {
      const eta = CampoServizio(id: 'e', nome: 'Note', tipo: kCampoTesto);
      final esito = unisciCampi([eta], [const CampoServizio(id: 'x', nome: 'note', tipo: kCampoNumero)]);
      expect(esito.saltati, ['note']);
      expect(esito.campi.single.tipo, kCampoTesto);
      expect(esito.aggiornati + esito.nuovi, 0);
    });

    test('da tendina a colori si può, e i valori senza colore ne ricevono uno', () {
      const tendina = CampoServizio(id: 'p', nome: 'Priorità', tipo: kCampoTendina, opzioni: [
        OpzioneCampo(id: 'alta', nome: 'Alta'),
      ]);
      final esito = unisciCampi([tendina], [
        const CampoServizio(id: 'p', nome: 'Priorità', tipo: kCampoColori, opzioni: [
          OpzioneCampo(id: 'bassa', nome: 'Bassa', colore: '#43A047'),
        ]),
      ], palette: const ['#43A047', '#E53935']);
      final c = esito.campi.single;
      expect(c.tipo, kCampoColori);
      expect(c.opzioni.map((o) => o.id), ['bassa', 'alta']);
      expect(c.opzioni.last.colore, '#E53935'); // il primo colore libero
    });

    test('il campo speciale si riconosce dal tipo e tiene il suo nome', () {
      final esito = unisciCampi([_speciale], [
        const CampoServizio(id: 'diverso', nome: 'Paziente', tipo: kCampoSessoEta, visibile: false, opzioni: [
          OpzioneCampo(id: 'x', nome: 'F'),
          OpzioneCampo(id: 'y', nome: 'Non indicato'),
        ]),
      ]);
      final c = esito.campi.single;
      expect(c.id, kIdCampoSessoEta);
      expect(c.nome, 'Sesso ed età');
      expect(c.visibile, isFalse);
      expect(c.opzioni.map((o) => o.id), ['f', 'y', 'm', 'a']);
    });

    test('un campo nuovo con un id già usato qui ne riceve uno diverso', () {
      const locale = CampoServizio(id: 'stesso', nome: 'A', tipo: kCampoTesto);
      // Stesso id ma tipo incompatibile e nome diverso: è un altro campo.
      final esito = unisciCampi([locale], [const CampoServizio(id: 'stesso', nome: 'B', tipo: kCampoNumero)]);
      expect(esito.saltati, ['B']); // riconosciuto per id, tipo incompatibile
      final esito2 = unisciCampi([locale.copyWith(nome: 'A')], [
        const CampoServizio(id: 'altro', nome: 'C', tipo: kCampoNumero),
      ]);
      expect(esito2.campi.map((c) => c.id), ['altro', 'stesso']);
    });
  });
}
