// Implementazione nativa (Android/iOS/Windows/Linux/macOS) del salvataggio e
// della lettura del file di backup: unico punto che può importare dart:io in
// tutta la feature backup (vedi backup_file.dart per il perché).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/platform_check.dart';

/// Salva [contenuto] su filesystem nativo.
/// Desktop (Windows/Linux/macOS): dialog "Salva come" nativo.
/// Mobile (Android/iOS): apre la share sheet (consente di salvare su Drive,
/// Files, ecc.). Restituisce il percorso salvato, null se l'utente annulla.
Future<String?> salvaFilePiattaforma(
    String contenuto, String nomeFile, String shareText) async {
  if (isDesktop) {
    final outputPath = await FilePicker.saveFile(
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

/// Salva [bytes] su filesystem nativo — variante binaria di
/// salvaFilePiattaforma (pensata per testo: JSON/.ics), usata per scaricare
/// il PDF di un comunicato (Tools → Archivio comunicati). Stesso
/// comportamento per piattaforma: dialog "Salva come" su desktop, share
/// sheet su mobile (mimeType passato a XFile per farla riconoscere ai
/// destinatari della condivisione, es. "Apri con" un lettore PDF).
Future<String?> salvaFileBinarioPiattaforma(
    Uint8List bytes, String nomeFile, String shareText, String mimeType) async {
  if (isDesktop) {
    final outputPath = await FilePicker.saveFile(
      dialogTitle: 'Salva file',
      fileName: nomeFile,
      type: FileType.any,
    );
    if (outputPath == null) return null;
    await File(outputPath).writeAsBytes(bytes);
    return outputPath;
  }

  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$nomeFile');
  await file.writeAsBytes(bytes);
  await SharePlus.instance
      .share(ShareParams(files: [XFile(file.path, mimeType: mimeType)], text: shareText));
  return file.path;
}

/// Apre il PDF prodotto da [caricaBytes] con l'app predefinita del sistema
/// per [mimeType], invece di forzare un salvataggio/condivisione — usata dal
/// pulsante "Visualizza" di Archivio comunicati. Callback invece di bytes
/// già pronti per avere la stessa firma della variante web (backup_file_web.dart),
/// dove l'ordine "apri la finestra, poi carica i byte" non è opzionale (vedi
/// i commenti lì) — qui nessun popup blocker da aggirare, ma l'interfaccia
/// condivisa evita due firme diverse per lo stesso scopo.
/// Su desktop scrive un file temporaneo e lo apre via url_launcher
/// (`Uri.file`, delega all'app associata all'estensione, es. il lettore PDF
/// predefinito). Su mobile un `file://` diretto non è affidabile da un'app
/// terza (Android blocca l'accesso, servirebbe un `FileProvider` dedicato) —
/// **bug reale trovato dal test manuale dell'utente**: una prima versione
/// ripiegava direttamente sulla share sheet (`ACTION_SEND`), che su Android
/// elenca solo le app di CONDIVISIONE (chat, bluetooth, cloud...) — molti
/// lettori PDF si registrano per `ACTION_VIEW` ma non per `ACTION_SEND`,
/// quindi non comparivano affatto tra le opzioni e il file non si poteva
/// davvero visualizzare, solo inoltrare altrove. Corretto con il package
/// `open_filex`, che genera da solo un `content://` via `FileProvider`
/// (dichiarato nel suo stesso `AndroidManifest.xml`, incluso in merge senza
/// alcuna configurazione manuale qui) e lancia un vero `ACTION_VIEW` — mostra
/// solo le app che sanno aprire un PDF, coerente col pulsante "Visualizza".
/// La share sheet resta un ripiego per `ResultType.noAppToOpen`/errori (nessun
/// lettore PDF installato): meglio poter comunque inoltrare il file altrove
/// che un vicolo cieco.
Future<void> apriFileBinarioPiattaforma(
    Future<Uint8List> Function() caricaBytes, String nomeFile, String mimeType) async {
  final bytes = await caricaBytes();
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$nomeFile');
  await file.writeAsBytes(bytes);
  if (isMobile) {
    final risultato = await OpenFilex.open(file.path, type: mimeType);
    if (risultato.type == ResultType.done) return;
  }
  if (isDesktop) {
    final aperto = await launchUrl(Uri.file(file.path));
    if (aperto) return;
  }
  await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: mimeType)]));
}

/// Apre il file picker e legge il contenuto testuale del backup scelto.
/// Null se l'utente annulla la selezione.
Future<String?> leggiBackupScelto() async {
  final result = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['json'],
  );
  if (result == null || result.files.isEmpty) return null;
  final path = result.files.single.path;
  if (path == null) throw StateError('Percorso file non disponibile.');
  return File(path).readAsString(encoding: utf8);
}
