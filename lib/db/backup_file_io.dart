// Implementazione nativa (Android/iOS/Windows/Linux/macOS) del salvataggio e
// della lettura del file di backup: unico punto che può importare dart:io in
// tutta la feature backup (vedi backup_file.dart per il perché).
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/platform_check.dart';

/// Salva [contenuto] su filesystem nativo.
/// Desktop (Windows/Linux/macOS): dialog "Salva come" nativo.
/// Mobile (Android/iOS): apre la share sheet (consente di salvare su Drive,
/// Files, ecc.). Restituisce il percorso salvato, null se l'utente annulla.
Future<String?> salvaFilePiattaforma(
    String contenuto, String nomeFile, String shareText) async {
  if (isDesktop) {
    final outputPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Salva file',
      fileName: nomeFile,
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (outputPath == null) return null;
    await File(outputPath).writeAsString(contenuto, encoding: utf8);
    return outputPath;
  }

  // Cache dir invece di Documents: prima ogni export lasciava per sempre nel
  // sandbox una copia del file (con dentro dati personali). La cache può
  // essere ripulita dal sistema e comunque gli export delle volte precedenti
  // vengono eliminati qui sotto. Il file corrente NON viene cancellato subito
  // dopo la share: alcune app destinatarie lo leggono in modo asincrono dopo
  // la chiusura della share sheet.
  final dir = await getTemporaryDirectory();
  await for (final f in dir.list()) {
    final nome = f.uri.pathSegments.last;
    if (f is File && nome.startsWith('ambuturni_') && nome.endsWith('.json')) {
      try {
        await f.delete();
      } catch (_) {
        // Best-effort: un file bloccato non deve impedire l'export.
      }
    }
  }
  final file = File('${dir.path}/$nomeFile');
  await file.writeAsString(contenuto, encoding: utf8);
  await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: shareText));
  return file.path;
}

/// Apre il file picker e legge il contenuto testuale del backup scelto.
/// Null se l'utente annulla la selezione.
Future<String?> leggiBackupScelto() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['json'],
  );
  if (result == null || result.files.isEmpty) return null;
  final path = result.files.single.path;
  if (path == null) throw StateError('Percorso file non disponibile.');
  return File(path).readAsString(encoding: utf8);
}
