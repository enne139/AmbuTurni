// Test della logica pura dei tipi di tessera (lib/utils/tessere_tipi.dart):
// etichette e validazione del valore per tipo. Il rendering del codice
// (barcodeDaTipo) è coperto dal package barcode_widget, non qui.
import 'package:flutter_test/flutter_test.dart';
import 'package:ambu_turni/utils/tessere_tipi.dart';

void main() {
  group('etichettaTipoTessera', () {
    test('nomi leggibili per i tipi noti', () {
      expect(etichettaTipoTessera(kTipoCode128), 'Code 128');
      expect(etichettaTipoTessera(kTipoEan13), 'EAN-13');
      expect(etichettaTipoTessera(kTipoEan8), 'EAN-8');
      expect(etichettaTipoTessera(kTipoQr), 'QR');
    });

    test('un tipo sconosciuto si mostra com\'è', () {
      expect(etichettaTipoTessera('pdf417'), 'pdf417');
    });
  });

  group('valoreValidoPerTipo', () {
    test('code128 e qr accettano qualsiasi testo non vuoto', () {
      expect(valoreValidoPerTipo(kTipoCode128, 'ABC-123'), isTrue);
      expect(valoreValidoPerTipo(kTipoQr, 'https://esempio.it'), isTrue);
      expect(valoreValidoPerTipo(kTipoCode128, ''), isFalse);
    });

    test('ean13 vuole 12 o 13 cifre', () {
      expect(valoreValidoPerTipo(kTipoEan13, '978020137962'), isTrue); // 12
      expect(valoreValidoPerTipo(kTipoEan13, '9780201379624'), isTrue); // 13
      expect(valoreValidoPerTipo(kTipoEan13, '12345'), isFalse);
      expect(valoreValidoPerTipo(kTipoEan13, 'ABCDEFGHIJKLM'), isFalse);
    });

    test('ean8 vuole 7 o 8 cifre', () {
      expect(valoreValidoPerTipo(kTipoEan8, '5901234'), isTrue); // 7
      expect(valoreValidoPerTipo(kTipoEan8, '59012341'), isTrue); // 8
      expect(valoreValidoPerTipo(kTipoEan8, '123'), isFalse);
    });
  });
}
