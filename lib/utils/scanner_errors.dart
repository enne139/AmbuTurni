// Messaggio d'errore della fotocamera per mobile_scanner, condiviso tra le
// schermate che usano lo scanner (lookup materiale e conteggio): differenziato
// su web perché lì il permesso e i requisiti (HTTPS) sono del browser, non
// dell'app.
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mobile_scanner/mobile_scanner.dart';

String messaggioErroreFotocamera(MobileScannerErrorCode codice) {
  if (codice == MobileScannerErrorCode.permissionDenied) {
    return kIsWeb
        ? 'Permesso fotocamera negato: concedilo dalle impostazioni del '
            'sito nel browser per scansionare.'
        : 'Permesso fotocamera negato: concedilo dalle impostazioni di '
            'sistema dell\'app per scansionare.';
  }
  if (kIsWeb && codice == MobileScannerErrorCode.unsupported) {
    return 'Il browser non supporta l\'accesso alla fotocamera: serve una '
        'connessione HTTPS e un browser aggiornato (Chrome, Edge, Firefox).';
  }
  return 'Fotocamera non disponibile (${codice.name}).';
}
