import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'database.dart';

const int _backupVersion = 1;

// Ordine di eliminazione rispettoso dei vincoli FK: prima le righe figlie,
// poi le righe padre.
const _deleteOrder = [
  'deletions',
  'sync_meta',
  'servizi',
  'turni',
  'assistenze',
  'tipologie_turno',
  'tipologie_assistenza',
  'ospedali',
  'persone',
  'associazioni',
];

// Tabelle incluse nel backup (stesso ordine dell'app RN per compatibilità JSON).
const _backupTables = [
  'associazioni',
  'persone',
  'ospedali',
  'tipologie_turno',
  'tipologie_assistenza',
  'turni',
  'servizi',
  'assistenze',
];

/// Esporta tutti i dati in un file JSON e lo condivide tramite share_plus.
/// Restituisce il percorso del file creato, oppure null in caso di errore.
Future<String?> exportBackup() async {
  final db = await getDb();

  final Map<String, dynamic> payload = {
    'version': _backupVersion,
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
  };

  for (final table in _backupTables) {
    payload[table] = await db.query(table);
  }

  final json = const JsonEncoder.withIndent('  ').convert(payload);
  final dir = await getApplicationDocumentsDirectory();
  final ts = DateTime.now().millisecondsSinceEpoch;
  final file = File('${dir.path}/ambulanza_backup_$ts.json');
  await file.writeAsString(json, encoding: utf8);

  await Share.shareXFiles([XFile(file.path)], text: 'Backup Ambulanza Turni');
  return file.path;
}

/// Importa un backup JSON scelto dall'utente.
/// Sovrascrive TUTTI i dati locali (import distruttivo, come da spec originale).
/// Restituisce un messaggio di esito (successo o errore).
Future<String> importBackup() async {
  // Apre il file picker filtrato su JSON.
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['json'],
  );
  if (result == null || result.files.isEmpty) return 'Import annullato.';

  final path = result.files.single.path;
  if (path == null) return 'Percorso file non disponibile.';

  final raw = await File(path).readAsString(encoding: utf8);
  final Map<String, dynamic> payload;
  try {
    payload = jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return 'File non valido (JSON malformato).';
  }

  // Verifica versione minima del formato.
  final version = payload['version'] as int? ?? 0;
  if (version < 1) return 'Formato backup non supportato (versione $version).';

  // Compatibilità con il formato legacy React Native: nell'app RN le tabelle
  // erano annidate sotto la chiave "tables" invece che al livello radice.
  final Map<String, dynamic> tables;
  if (payload.containsKey('tables')) {
    tables = Map<String, dynamic>.from(payload['tables'] as Map);
  } else {
    tables = payload;
  }

  // Normalizza le date dei turni: l'app RN salvava "YYYY-MM-DDT00:00:00.000Z"
  // (ISO datetime), l'app Flutter si aspetta "YYYY-MM-DD" (solo data).
  if (tables['turni'] is List) {
    tables['turni'] = (tables['turni'] as List).map((row) {
      final map = Map<String, dynamic>.from(row as Map);
      final data = map['data'];
      if (data is String && data.length > 10) {
        map['data'] = data.substring(0, 10);
      }
      return map;
    }).toList();
  }

  final db = await getDb();

  // Elimina tutti i dati nell'ordine corretto (FK-safe).
  await db.transaction((txn) async {
    await txn.execute('PRAGMA foreign_keys = OFF');
    for (final table in _deleteOrder) {
      await txn.delete(table);
    }
    // Reinserisce ogni tabella presente nel backup.
    for (final table in _backupTables) {
      final rows = tables[table];
      if (rows == null) continue;
      for (final row in (rows as List)) {
        try {
          await txn.insert(table, Map<String, dynamic>.from(row as Map));
        } catch (_) {
          // Ignora righe che violano vincoli (es. duplicati) — continua.
        }
      }
    }
    await txn.execute('PRAGMA foreign_keys = ON');
  });

  final ts = payload['exportedAt'] as String? ?? '?';
  return 'Import completato. Dati del $ts ripristinati.';
}
