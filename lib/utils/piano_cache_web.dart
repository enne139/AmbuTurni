// Implementazione web: stessa cache "un piano per mese", ma su
// shared_preferences (localStorage nel browser) invece che su file — path_provider
// non ha una directory di supporto persistente utilizzabile allo stesso modo
// nel browser. Stesso design "best-effort" di piano_cache_io.dart: un
// errore di lettura/scrittura non deve bloccare nulla, la cache è solo un
// acceleratore e chi chiama ricarica dalla rete se manca.
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'piano_mensile.dart';

String _chiavePrefs(String chiaveMese) => 'piano_turni_cache_$chiaveMese';

Future<void> salvaPianoInCache(String chiaveMese, PianoMensile piano) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chiavePrefs(chiaveMese), jsonEncode(piano.toMap()));
  } catch (_) {}
}

Future<PianoMensile?> leggiPianoDaCache(String chiaveMese) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_chiavePrefs(chiaveMese));
    if (raw == null) return null;
    return PianoMensile.fromMap(
        Map<String, dynamic>.from(jsonDecode(raw) as Map));
  } catch (_) {
    return null;
  }
}

Future<void> eliminaPianoDaCache(String chiaveMese) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_chiavePrefs(chiaveMese));
  } catch (_) {}
}
