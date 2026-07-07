// Cache locale del Piano turni: un file JSON per mese ("piano_turni_2026-07.json")
// nella directory di supporto dell'app. Serve a mostrare subito l'ultimo piano
// decodificato all'apertura del tool (anche offline): l'endpoint export di
// Google genera l'XLSX al momento e il package excel decodifica l'intero
// workbook — insieme costano diversi secondi a ogni caricamento, per dati che
// tra un'apertura e l'altra quasi non cambiano. Il download resta comunque:
// la cache è solo la prima cosa mostrata, i dati freschi la sostituiscono.
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
