import 'package:barcode_widget/barcode_widget.dart';

// Tipi di codice che una tessera può avere. Sono le stringhe salvate nella
// colonna `tipo` del DB: cambiarle romperebbe le tessere già salvate.
// code128 è il default perché accetta quasi qualsiasi testo (lettere e cifre),
// gli EAN solo cifre di lunghezza fissa, il QR qualsiasi cosa.
const kTipoCode128 = 'code128';
const kTipoEan13 = 'ean13';
const kTipoEan8 = 'ean8';
const kTipoQr = 'qr';

// Ordine mostrato nel menu del form.
const tipiTessera = [kTipoCode128, kTipoEan13, kTipoEan8, kTipoQr];

/// Nome leggibile del tipo, per i menu e il dettaglio.
String etichettaTipoTessera(String tipo) {
  switch (tipo) {
    case kTipoCode128:
      return 'Code 128';
    case kTipoEan13:
      return 'EAN-13';
    case kTipoEan8:
      return 'EAN-8';
    case kTipoQr:
      return 'QR';
  }
  // Un backup di una versione più nuova potrebbe portare un tipo sconosciuto:
  // si mostra com'è invece di far saltare la schermata.
  return tipo;
}

/// true se [valore] si può disegnare come codice del tipo [tipo]. Gli EAN
/// hanno una lunghezza fissa di sole cifre (l'ultima è di controllo, ma
/// barcode_widget la calcola da sé se diamo le cifre dei dati); code128 e QR
/// accettano qualsiasi testo non vuoto. Serve a bloccare un salvataggio che
/// poi non si potrebbe disegnare, e a scegliere il tipo giusto in scansione.
bool valoreValidoPerTipo(String tipo, String valore) {
  if (valore.isEmpty) return false;
  switch (tipo) {
    case kTipoEan13:
      return RegExp(r'^\d{12,13}$').hasMatch(valore);
    case kTipoEan8:
      return RegExp(r'^\d{7,8}$').hasMatch(valore);
    case kTipoCode128:
    case kTipoQr:
      return true;
  }
  return false;
}

/// L'oggetto Barcode di barcode_widget per disegnare il tipo scelto. Isolato
/// qui così le schermate non dipendono dai nomi interni del package.
Barcode barcodeDaTipo(String tipo) {
  switch (tipo) {
    case kTipoEan13:
      return Barcode.ean13();
    case kTipoEan8:
      return Barcode.ean8();
    case kTipoQr:
      return Barcode.qrCode();
    case kTipoCode128:
    default:
      return Barcode.code128();
  }
}
