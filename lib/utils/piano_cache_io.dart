// Implementazione nativa (Android/iOS/Windows/Linux/macOS) della cache: un
// file JSON per mese nella directory di supporto dell'app. Unico punto che
// può importare dart:io in tutta la feature (vedi piano_cache.dart per il
// perché non deve mai finire nel file pubblico).
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'piano_mensile.dart';

Future<File> _fileCache(String chiaveMese) async {
  final dir = await getApplicationSupportDirectory();
  return File('${dir.path}${Platform.pathSeparator}piano_turni_$chiaveMese.json');
}

/// Salva il piano decodificato. Best-effort: un errore di scrittura non deve
/// disturbare il caricamento appena riuscito (la cache è solo un acceleratore).
Future<void> salvaPianoInCache(String chiaveMese, PianoMensile piano) async {
  try {
    await (await _fileCache(chiaveMese)).writeAsString(jsonEncode(piano.toMap()));
  } catch (_) {}
}

/// Legge il piano di un mese dalla cache; null se assente o illeggibile
/// (file corrotto, formato di una versione vecchia): chi chiama riscarica.
Future<PianoMensile?> leggiPianoDaCache(String chiaveMese) async {
  try {
    final file = await _fileCache(chiaveMese);
    if (!await file.exists()) return null;
    return PianoMensile.fromMap(
        Map<String, dynamic>.from(jsonDecode(await file.readAsString()) as Map));
  } catch (_) {
    return null;
  }
}

/// Elimina la cache di un mese (quando il foglio viene rimosso dai salvati).
Future<void> eliminaPianoDaCache(String chiaveMese) async {
  try {
    final file = await _fileCache(chiaveMese);
    if (await file.exists()) await file.delete();
  } catch (_) {}
}
