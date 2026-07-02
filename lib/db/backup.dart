import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'database.dart';
import 'helpers.dart' show ricalcolaTutteLeNumerazioni;

const int _backupVersion = 1;

// Ordine di eliminazione rispettoso dei vincoli FK: prima le righe figlie,
// poi le righe padre. (In pratica l'ordine non è vincolante durante l'import:
// la transazione gira con PRAGMA foreign_keys = OFF dall'inizio alla fine —
// vedi importBackup — ma lo teniamo comunque corretto per chiarezza/difesa.)
const _deleteOrder = [
  'deletions',
  'sync_meta',
  'servizi',
  'materiali_usati',
  'turni',
  'assistenze',
  'tipologie_turno',
  'tipologie_assistenza',
  'ospedali',
  'persone',
  'materiali',
  'associazioni',
];

// Tabelle incluse nel backup. Stesse tabelle e stesso ordine dell'app RN per
// compatibilità JSON, con in più materiali/materiali_usati (esclusive
// dell'app Flutter): un backup Flutter importato nell'app RN le ignorerebbe
// semplicemente (chiavi JSON sconosciute), e un vecchio backup RN importato
// qui le lascia assenti (tables[table] == null → nessuna riga da reinserire).
const _backupTables = [
  'associazioni',
  'persone',
  'ospedali',
  'tipologie_turno',
  'tipologie_assistenza',
  'turni',
  'servizi',
  'assistenze',
  'materiali',
  'materiali_usati',
];

/// Esporta tutti i dati in un file JSON.
/// Su desktop (Windows/Linux/macOS) mostra un dialog "Salva come" nativo;
/// su Android/iOS apre la share sheet (consente di salvare su Drive, Files, ecc.).
/// Restituisce il percorso salvato, oppure null se l'utente annulla.
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
  final ts = DateTime.now().millisecondsSinceEpoch;
  return _salvaFile(json, 'ambuturni_backup_$ts.json', 'Backup AmbuTurni');
}

/// Esporta i turni in formato leggibile: ID sostituiti con nomi, servizi
/// annidati dentro ogni turno, tipologie come lista di stringhe.
/// Utile per consultare i dati fuori dall'app senza interpretare UUID.
Future<String?> exportSemplificato() async {
  final db = await getDb();

  // Lookup table: ID → nome leggibile.
  final assocMap = {for (final r in await db.query('associazioni')) r['id'] as String: r['nome'] as String};
  final personeMap = {
    for (final r in await db.query('persone'))
      r['id'] as String: '${r['cognome']} ${r['nome']}'
  };
  final tipologieMap = {for (final r in await db.query('tipologie_turno')) r['id'] as String: r['nome'] as String};

  // Converte un ID persona nullable nel nome completo (null se assente).
  String? p(dynamic id) => id == null ? null : personeMap[id as String];

  final turniRows = await db.query('turni', orderBy: 'data DESC, created_at DESC');
  final List<Map<String, dynamic>> risultato = [];

  for (final t in turniRows) {
    final turnoId = t['id'] as String;

    // Tipologie: primaria + extra → lista di nomi. Stesso jsonDecode di
    // Turno.fromMap (il campo è un array JSON di stringhe).
    final tipIds = <String>[];
    final pid = t['tipologia_id'] as String?;
    if (pid != null) tipIds.add(pid);
    final extraRaw = (t['tipologie_extra'] as String?) ?? '';
    if (extraRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(extraRaw);
        if (decoded is List) tipIds.addAll(decoded.whereType<String>());
      } catch (_) {
        // Valore corrotto/legacy: l'export prosegue senza le tipologie extra.
      }
    }

    // Servizi annidati.
    final serviziRows = await db.rawQuery('''
      SELECT s.*, o.nome AS ospedale_nome
      FROM servizi s
      LEFT JOIN ospedali o ON o.id = s.ospedale_id
      WHERE s.turno_id = ?
      ORDER BY s.ordine ASC
    ''', [turnoId]);

    risultato.add({
      'associazione': assocMap[t['associazione_id'] as String? ?? ''],
      'numero_progressivo': t['numero_progressivo'],
      'data': t['data'],
      'ore': t['ore'],
      'tipologie': tipIds.map((id) => tipologieMap[id]).whereType<String>().toList(),
      'num_servizi': t['num_servizi'],
      'cambio_meta': (t['cambio_meta'] as int?) == 1,
      'descrizione': t['descrizione'],
      'note': t['note'],
      'eq1_autista': p(t['eq1_autista_id']),
      'eq1_cs': p(t['eq1_cs_id']),
      'eq1_terzo': p(t['eq1_terzo_id']),
      'eq1_quarto': p(t['eq1_quarto_id']),
      'eq1_centralinista': p(t['eq1_centralinista_id']),
      'eq2_autista': p(t['eq2_autista_id']),
      'eq2_cs': p(t['eq2_cs_id']),
      'eq2_terzo': p(t['eq2_terzo_id']),
      'eq2_quarto': p(t['eq2_quarto_id']),
      'eq2_centralinista': p(t['eq2_centralinista_id']),
      'servizi': serviziRows.map((s) => {
        'codice_chiamata': s['codice_chiamata'],
        'codice_uscita': s['codice_uscita'],
        'ospedale': s['ospedale_nome'],
        'descrizione': s['descrizione'],
        'ordine': s['ordine'],
      }).toList(),
    });
  }

  final json = const JsonEncoder.withIndent('  ').convert({'turni': risultato});
  final ts = DateTime.now().millisecondsSinceEpoch;
  return _salvaFile(json, 'ambuturni_export_turni_$ts.json', 'Export Turni AmbuTurni');
}

/// Helper condiviso: salva il testo [contenuto] su filesystem.
/// Desktop → dialog "Salva come"; mobile → share sheet.
Future<String?> _salvaFile(String contenuto, String nomeFile, String shareText) async {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    final outputPath = await FilePicker.platform.saveFile(
      dialogTitle: 'Salva file',
      fileName: nomeFile,
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (outputPath == null) return null;
    await File(outputPath).writeAsString(contenuto, encoding: utf8);
    return outputPath;
  } else {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$nomeFile');
    await file.writeAsString(contenuto, encoding: utf8);
    await Share.shareXFiles([XFile(file.path)], text: shareText);
    return file.path;
  }
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

  // Ricalcola la numerazione progressiva per ogni associazione: i raw INSERT
  // del backup non passano per saveTurno, quindi i numeri potrebbero essere
  // sbagliati o assenti se il backup non li aveva aggiornati.
  await ricalcolaTutteLeNumerazioni();

  final ts = payload['exportedAt'] as String? ?? '?';
  return 'Import completato. Dati del $ts ripristinati.';
}
