// Implementazione web del salvataggio e della lettura del file di backup:
// niente dart:io (non disponibile sul target web) né dialog "Salva come"
// (file_picker non implementa saveFile nel browser, solo pickFiles).
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

/// "Salva" [contenuto] nel browser: si costruisce un XFile in memoria (mai
/// scritto su disco: sul web XFile.fromData tiene solo i bytes) e lo si passa
/// a share_plus, che tenta prima la Web Share API nativa (Navigator.share,
/// richiede HTTPS) e ricade da solo su un download via Blob URL se non
/// disponibile o rifiutata (downloadFallbackEnabled è true di default).
/// Non esiste un "percorso" sul web: si restituisce il nome file solo per
/// segnalare il successo al chiamante.
Future<String?> salvaFilePiattaforma(
    String contenuto, String nomeFile, String shareText) async {
  final bytes = Uint8List.fromList(utf8.encode(contenuto));
  final file = XFile.fromData(bytes, name: nomeFile, mimeType: 'application/json');
  await SharePlus.instance.share(ShareParams(files: [file], text: shareText));
  return nomeFile;
}

/// Salva [bytes] nel browser — variante binaria di salvaFilePiattaforma
/// (pensata per testo), usata per scaricare il PDF di un comunicato
/// (Tools → Archivio comunicati). Stesso meccanismo XFile.fromData +
/// share_plus, [mimeType] passato esplicitamente (qui non è mai JSON).
Future<String?> salvaFileBinarioPiattaforma(
    Uint8List bytes, String nomeFile, String shareText, String mimeType) async {
  final file = XFile.fromData(bytes, name: nomeFile, mimeType: mimeType);
  await SharePlus.instance.share(ShareParams(files: [file], text: shareText));
  return nomeFile;
}

/// Apre in una nuova scheda del browser il PDF prodotto da [caricaBytes],
/// invece di scaricarlo — usata dal pulsante "Visualizza" di Archivio
/// comunicati.
///
/// Due insidie reali dei browser moderni, trovate testando in Chrome (non
/// intercettabili da analyze/test):
/// 1. **`data:` URI bloccata**: una prima versione usava
///    `Uri.dataFromBytes` + `launchUrl` — Chrome rifiuta la navigazione
///    diretta a una `data:` URI per motivi di sicurezza (anti-phishing),
///    la scheda restava vuota senza alcun errore visibile.
/// 2. **`window.open` dopo un'attesa di rete viene trattato come popup non
///    richiesto**: il fetch del PDF (`caricaBytes`, la chiamata autenticata
///    al backend) è asincrono; se si apre la finestra solo DOPO aver
///    scaricato i byte, il browser non riconosce più l'apertura come
///    conseguenza diretta del tap dell'utente e la blocca in silenzio.
///
/// Soluzione: apre subito una scheda vuota (`html.window.open`, ultima
/// istruzione sincrona di questa funzione, ancora dentro la catena del
/// gesto di tap originale — [caricaBytes] è passata come callback proprio
/// per poterla invocare DOPO l'apertura, mai prima), poi ci carica dentro
/// il PDF (Blob URL, non una data: URI: un Blob creato in pagina non
/// ricade nella restrizione del punto 1) una volta arrivati i byte.
Future<void> apriFileBinarioPiattaforma(
    Future<Uint8List> Function() caricaBytes, String nomeFile, String mimeType) async {
  final finestra = html.window.open('', '_blank');
  try {
    final bytes = await caricaBytes();
    final blob = html.Blob([bytes], mimeType);
    final url = html.Url.createObjectUrlFromBlob(blob);
    finestra.location.href = url;
  } catch (e) {
    finestra.close();
    rethrow;
  }
}

/// Apre il file picker del browser e legge il contenuto testuale del backup
/// scelto. Null se l'utente annulla la selezione. Sul web file_picker
/// restituisce solo i bytes (mai un path reale), da qui `withData: true`.
Future<String?> leggiBackupScelto() async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['json'],
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;
  final bytes = result.files.single.bytes;
  if (bytes == null) throw StateError('Contenuto file non disponibile.');
  return utf8.decode(bytes);
}
