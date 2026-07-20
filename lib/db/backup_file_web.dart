// Implementazione web del salvataggio e della lettura del file di backup:
// niente dart:io (non disponibile sul target web) né dialog "Salva come"
// (file_picker non implementa saveFile nel browser, solo pickFiles).
import 'dart:convert';
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
