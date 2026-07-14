import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/prefs_keys.dart';
import 'backup_file.dart';
import 'database.dart';
import 'helpers.dart' show ricalcolaTutteLeNumerazioni, saveOspedale, aggiornaCoordinateOspedale;

// Versione 2: aggiunta la sezione opzionale "preferenze" (Piano turni; poi
// estesa al Magazzino Verde senza bump: ogni chiave è opzionale, un backup
// che non la contiene lascia la preferenza del device com'era).
// L'import accetta qualunque versione >= 1: i backup v1 semplicemente non
// hanno la sezione e le preferenze del device restano com'erano.
const int _backupVersion = 2;

// Ordine di eliminazione rispettoso dei vincoli FK: prima le righe figlie,
// poi le righe padre. Con le FK disattivate durante l'import (vedi
// importBackup) non sarebbe strettamente necessario, ma resta corretto come
// difesa nel caso il PRAGMA non venisse applicato.
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

// Tabelle incluse nel backup. L'app RN è dismessa, ma i suoi vecchi backup
// (e quelli Flutter pre-v8) restano importabili: le tabelle assenti nel file
// vengono lasciate vuote (tables[table] == null → nessuna riga da reinserire)
// e le righe dei turni vengono normalizzate in importBackup (date ISO,
// fusione tipologia_id/tipologie_extra → tipologie).
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

/// Timestamp leggibile per i nomi dei file esportati (AAAAMMGG_HH_MM),
/// al posto dei millisecondi da epoch: un utente che guarda i file salvati
/// non deve decifrare un numero per capire quando è stato fatto l'export.
String _timestampFile() {
  final now = DateTime.now();
  final data = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  final ora = now.hour.toString().padLeft(2, '0');
  final minuti = now.minute.toString().padLeft(2, '0');
  return '${data}_${ora}_$minuti';
}

/// Esporta tutti i dati in un file JSON.
/// Su desktop (Windows/Linux/macOS) mostra un dialog "Salva come" nativo;
/// su Android/iOS apre la share sheet (consente di salvare su Drive, Files,
/// ecc.); su web scarica il file nel browser (vedi backup_file_web.dart).
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

  // Preferenze del Piano turni: vivono in SharedPreferences, non nel DB, ma
  // senza di loro un restore su un device nuovo perderebbe l'archivio degli
  // URL dei fogli mensili e il nome cercato (segnalini sul calendario).
  // L'archivio va nel JSON come mappa decodificata, non come stringa JSON
  // annidata: il backup resta leggibile a occhio.
  final prefs = await SharedPreferences.getInstance();
  Map<String, dynamic> fogli = {};
  try {
    final decoded = jsonDecode(prefs.getString(kPrefPianoTurniFogli) ?? '{}');
    if (decoded is Map) fogli = Map<String, dynamic>.from(decoded);
  } catch (_) {
    // Archivio corrotto: il backup si esporta senza, non è un errore.
  }
  payload['preferenze'] = {
    kPrefPianoTurniUrl: prefs.getString(kPrefPianoTurniUrl),
    kPrefPianoTurniFogli: fogli,
    kPrefPianoTurniUltimaRicerca: prefs.getString(kPrefPianoTurniUltimaRicerca),
    // Configurazione del Magazzino Verde: la chiave API viene inclusa
    // deliberatamente — il backup completo serve al trasferimento su un
    // device nuovo, e senza chiave il tool resterebbe scollegato (andrebbe
    // rigenerata dalla pagina Amministrazione del gestionale).
    kPrefMagazzinoUrl: prefs.getString(kPrefMagazzinoUrl),
    kPrefMagazzinoApiKey: prefs.getString(kPrefMagazzinoApiKey),
    // Tool attivi in Impostazioni: null se mai salvato (si applicano i
    // default del catalogo al restore, come su un device mai configurato).
    kPrefToolsAttivi: prefs.getStringList(kPrefToolsAttivi),
    // Tool già "visti" su questo device (ToolsProvider.carica): senza,
    // un restore tratterebbe come "nuovi" tutti i tool già noti all'origine,
    // riaccendendo quelli disattivati esplicitamente prima del backup.
    kPrefToolsConosciuti: prefs.getStringList(kPrefToolsConosciuti),
  };

  final json = const JsonEncoder.withIndent('  ').convert(payload);
  return _salvaFile(json, 'ambuturni_backup_${_timestampFile()}.json', 'Backup AmbuTurni');
}

/// Esporta turni e assistenze in formato leggibile: ID sostituiti con nomi,
/// servizi annidati dentro ogni turno, tipologie come lista di stringhe.
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

    // Tipologie → lista di nomi. Stesso jsonDecode di Turno.fromMap
    // (il campo è un array JSON di stringhe).
    final tipIds = <String>[];
    final tipRaw = (t['tipologie'] as String?) ?? '';
    if (tipRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(tipRaw);
        if (decoded is List) tipIds.addAll(decoded.whereType<String>());
      } catch (_) {
        // Valore corrotto/legacy: l'export prosegue senza le tipologie.
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

  // Assistenze: stessa idea dei turni ma senza tipologie né servizi (la
  // tabella non li ha).
  final assistenzeRows = await db.query('assistenze', orderBy: 'data DESC, created_at DESC');
  final risultatoAssistenze = assistenzeRows.map((a) => {
        'associazione': assocMap[a['associazione_id'] as String? ?? ''],
        'numero_progressivo': a['numero_progressivo'],
        'data': a['data'],
        'ore': a['ore'],
        'descrizione': a['descrizione'],
        'note': a['note'],
        'eq1_autista': p(a['eq1_autista_id']),
        'eq1_cs': p(a['eq1_cs_id']),
        'eq1_terzo': p(a['eq1_terzo_id']),
        'eq1_quarto': p(a['eq1_quarto_id']),
        'eq1_centralinista': p(a['eq1_centralinista_id']),
        'eq2_autista': p(a['eq2_autista_id']),
        'eq2_cs': p(a['eq2_cs_id']),
        'eq2_terzo': p(a['eq2_terzo_id']),
        'eq2_quarto': p(a['eq2_quarto_id']),
        'eq2_centralinista': p(a['eq2_centralinista_id']),
      }).toList();

  final json = const JsonEncoder.withIndent('  ').convert({
    'turni': risultato,
    'assistenze': risultatoAssistenze,
  });
  return _salvaFile(json, 'ambuturni_export_${_timestampFile()}.json', 'Export AmbuTurni');
}

/// Helper condiviso: salva il testo [contenuto] su filesystem.
/// Desktop → dialog "Salva come"; mobile → share sheet; web → download
/// browser. La parte che tocca filesystem/picker/share vive in
/// backup_file.dart (import condizionale io/web): qui non deve mai comparire
/// dart:io, altrimenti l'intero file (e con esso l'app) non compilerebbe
/// per il target web.
Future<String?> _salvaFile(String contenuto, String nomeFile, String shareText) =>
    salvaFilePiattaforma(contenuto, nomeFile, shareText);

/// Importa un backup JSON scelto dall'utente.
/// Sovrascrive TUTTI i dati locali (import distruttivo, come da spec originale).
/// Restituisce un messaggio di esito (successo o errore).
Future<String> importBackup() async {
  // Apre il file picker filtrato su JSON e legge il contenuto: la parte che
  // tocca filesystem/picker vive in backup_file.dart (io/web separati, vedi
  // _salvaFile sopra per il perché).
  final String raw;
  try {
    final letto = await leggiBackupScelto();
    if (letto == null) return 'Import annullato.';
    raw = letto;
  } on StateError catch (e) {
    return e.message;
  }

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

  // Normalizza le righe dei turni dei backup più vecchi:
  // - date: l'app RN salvava "YYYY-MM-DDT00:00:00.000Z" (ISO datetime),
  //   l'app Flutter si aspetta "YYYY-MM-DD" (solo data);
  // - tipologie: i backup pre-v8 (RN e Flutter fino alla DB v7) hanno le
  //   colonne separate tipologia_id/tipologie_extra — vanno fuse nella
  //   colonna unica `tipologie`, altrimenti l'INSERT fallirebbe su colonne
  //   che non esistono più e la riga verrebbe scartata.
  if (tables['turni'] is List) {
    tables['turni'] = (tables['turni'] as List).map((row) {
      final map = Map<String, dynamic>.from(row as Map);
      final data = map['data'];
      if (data is String && data.length > 10) {
        map['data'] = data.substring(0, 10);
      }
      if (!map.containsKey('tipologie')) {
        final tipologie = <String>[];
        final pid = map['tipologia_id'];
        if (pid is String && pid.isNotEmpty) tipologie.add(pid);
        final extraRaw = map['tipologie_extra'];
        if (extraRaw is String && extraRaw.isNotEmpty) {
          try {
            final decoded = jsonDecode(extraRaw);
            if (decoded is List) tipologie.addAll(decoded.whereType<String>());
          } catch (_) {
            // Valore corrotto/legacy: la riga si importa senza tipologie extra.
          }
        }
        map['tipologie'] = jsonEncode(tipologie);
      }
      map
        ..remove('tipologia_id')
        ..remove('tipologie_extra');
      return map;
    }).toList();
  }

  final db = await getDb();

  // PRAGMA foreign_keys va cambiato FUORI dalla transazione: per specifica
  // SQLite dentro una transazione è un no-op silenzioso (la prima versione di
  // questo codice lo eseguiva dentro, e le FK restavano attive). Disattivarle
  // rende l'import un vero restore: ogni riga del file viene reinserita
  // com'era nel DB di origine, anche con riferimenti pendenti pregressi.
  int scartate = 0;
  await db.execute('PRAGMA foreign_keys = OFF');
  try {
    await db.transaction((txn) async {
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
          } catch (e) {
            // Una riga malformata (es. colonna di un'altra versione dello
            // schema, vincolo UNIQUE/CHECK violato) non deve bloccare il
            // resto dell'import — ma nemmeno sparire in silenzio: viene
            // contata e segnalata nel messaggio di esito.
            scartate++;
            debugPrint('[import] riga scartata da $table: $e');
          }
        }
      }
    });
  } finally {
    await db.execute('PRAGMA foreign_keys = ON');
  }

  // Ricalcola la numerazione progressiva per ogni associazione: i raw INSERT
  // del backup non passano per saveTurno, quindi i numeri potrebbero essere
  // sbagliati o assenti se il backup non li aveva aggiornati.
  await ricalcolaTutteLeNumerazioni();

  // Ripristina le preferenze del Piano turni, se il backup le contiene
  // (v1 e formati RN non le hanno: le preferenze del device restano
  // com'erano). Ogni valore viene scritto solo se presente e valido:
  // niente cancellazioni, coerente con l'assenza della sezione.
  final preferenze = payload['preferenze'];
  if (preferenze is Map) {
    final prefs = await SharedPreferences.getInstance();
    final url = preferenze[kPrefPianoTurniUrl];
    if (url is String && url.isNotEmpty) {
      await prefs.setString(kPrefPianoTurniUrl, url);
    }
    final fogli = preferenze[kPrefPianoTurniFogli];
    if (fogli is Map && fogli.isNotEmpty) {
      await prefs.setString(kPrefPianoTurniFogli, jsonEncode(fogli));
    }
    final ricerca = preferenze[kPrefPianoTurniUltimaRicerca];
    if (ricerca is String && ricerca.isNotEmpty) {
      await prefs.setString(kPrefPianoTurniUltimaRicerca, ricerca);
    }
    final magazzinoUrl = preferenze[kPrefMagazzinoUrl];
    if (magazzinoUrl is String && magazzinoUrl.isNotEmpty) {
      await prefs.setString(kPrefMagazzinoUrl, magazzinoUrl);
    }
    final magazzinoKey = preferenze[kPrefMagazzinoApiKey];
    if (magazzinoKey is String && magazzinoKey.isNotEmpty) {
      await prefs.setString(kPrefMagazzinoApiKey, magazzinoKey);
    }
    // Lista (non stringa): a differenza delle altre preferenze una lista
    // vuota è un valore valido (l'utente ha disattivato tutti i tool), non
    // va scartata come le stringhe vuote sopra — solo l'assenza del campo
    // (backup pre-funzionalità) lascia i default del device.
    final toolsAttivi = preferenze[kPrefToolsAttivi];
    if (toolsAttivi is List && toolsAttivi.every((e) => e is String)) {
      await prefs.setStringList(kPrefToolsAttivi, toolsAttivi.cast<String>());
    }
    // Stessa eccezione di toolsAttivi: una lista vuota è un valore valido.
    final toolsConosciuti = preferenze[kPrefToolsConosciuti];
    if (toolsConosciuti is List && toolsConosciuti.every((e) => e is String)) {
      await prefs.setStringList(kPrefToolsConosciuti, toolsConosciuti.cast<String>());
    }
  }

  final ts = payload['exportedAt'] as String? ?? '?';
  final avviso = scartate == 0
      ? ''
      : ' Attenzione: $scartate righe non valide scartate (dettagli nel log).';
  return 'Import completato. Dati del $ts ripristinati.$avviso';
}

/// Esporta la sola anagrafica ospedali (nome, via, città, coordinate) in un
/// file JSON portabile — a differenza del backup completo, pensato per
/// scambiare/condividere la lista con un'altra installazione (o un'altra
/// associazione), non per un ripristino esatto: niente id/timestamp interni.
/// L'import (vedi importOspedali) fa un upsert per nome, quindi lo stesso
/// file può anche fare da "esportazione periodica" senza creare doppioni.
Future<String?> exportOspedali() async {
  final db = await getDb();
  final righe = await db.query('ospedali', orderBy: 'nome ASC');
  final ospedali = righe.map((r) => {
        'nome': r['nome'],
        'via': r['via'],
        'citta': r['citta'],
        'lat': r['lat'],
        'lng': r['lng'],
      }).toList();
  final json = const JsonEncoder.withIndent('  ').convert({'ospedali': ospedali});
  return _salvaFile(
      json, 'ambuturni_ospedali_${_timestampFile()}.json', 'Ospedali AmbuTurni');
}

/// Importa un file di ospedali: lo stesso prodotto da exportOspedali, oppure
/// — per comodità — un backup completo (che ha comunque una chiave
/// "ospedali"). A differenza di importBackup NON è distruttivo: ogni riga fa
/// un upsert per nome (un ospedale già in anagrafica con lo stesso nome
/// viene aggiornato, uno nuovo viene creato), il resto dei dati e gli
/// ospedali non presenti nel file restano invariati. Le coordinate si
/// scrivono solo se il file le contiene: niente geocoding automatico qui,
/// per non lanciare una raffica di richieste a Nominatim su un import
/// massivo (l'utente può comunque ritentarlo per singolo ospedale da Lista
/// ospedali). Restituisce un messaggio di esito con il conteggio.
Future<String> importOspedali() async {
  final String raw;
  try {
    final letto = await leggiBackupScelto();
    if (letto == null) return 'Import annullato.';
    raw = letto;
  } on StateError catch (e) {
    return e.message;
  }

  final dynamic payload;
  try {
    payload = jsonDecode(raw);
  } catch (_) {
    return 'File non valido (JSON malformato).';
  }

  final List<dynamic> righe;
  if (payload is List) {
    righe = payload;
  } else if (payload is Map && payload['ospedali'] is List) {
    righe = payload['ospedali'] as List;
  } else {
    return 'File non valido: non contiene un elenco di ospedali.';
  }

  final db = await getDb();
  final esistenti = {
    for (final r in await db.query('ospedali')) r['nome'] as String: r['id'] as String
  };

  int creati = 0, aggiornati = 0, scartati = 0;
  for (final riga in righe) {
    if (riga is! Map) {
      scartati++;
      continue;
    }
    final nome = (riga['nome'] as String?)?.trim();
    if (nome == null || nome.isEmpty) {
      scartati++;
      continue;
    }
    final via = (riga['via'] as String?)?.trim();
    final citta = (riga['citta'] as String?)?.trim();
    final lat = (riga['lat'] as num?)?.toDouble();
    final lng = (riga['lng'] as num?)?.toDouble();

    final idEsistente = esistenti[nome];
    final String id;
    if (idEsistente != null) {
      id = await saveOspedale(
        nome,
        (citta == null || citta.isEmpty) ? null : citta,
        id: idEsistente,
        via: (via == null || via.isEmpty) ? null : via,
      );
      aggiornati++;
    } else {
      id = await saveOspedale(
        nome,
        (citta == null || citta.isEmpty) ? null : citta,
        via: (via == null || via.isEmpty) ? null : via,
      );
      esistenti[nome] = id;
      creati++;
    }
    if (lat != null && lng != null) {
      await aggiornaCoordinateOspedale(id, lat, lng);
    }
  }

  final avviso = scartati == 0 ? '' : ' ($scartati righe scartate: nome mancante o formato non valido)';
  return 'Import completato: $creati nuovi, $aggiornati aggiornati.$avviso';
}
