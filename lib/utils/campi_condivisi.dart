// Condivisione della lista dei campi personalizzati dei servizi con un file
// (Impostazioni → Campi dei servizi → Esporta / Importa). Dart puro, testato
// in test/utils/campi_condivisi_test.dart: qui solo il formato del file e
// l'unione con la lista del dispositivo, il salvataggio è in helpers.dart.
import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../db/models.dart';

/// Valore di "formato" nel file esportato: distingue una lista di campi da
/// un altro JSON (un backup, la lista degli ospedali...).
const kFormatoCampi = 'ambuturni_campi_servizio';

const _uuid = Uuid();

/// La lista dei campi come file JSON leggibile, nell'ordine scelto. Gli id
/// ci sono perché chi la importa possa riconoscere i campi che ha già.
String campiInJson(List<CampoServizio> campi, {DateTime? adesso}) {
  final ordinati = [...campi]..sort((a, b) => a.ordine.compareTo(b.ordine));
  return const JsonEncoder.withIndent('  ').convert({
    'formato': kFormatoCampi,
    'versione': 1,
    'esportatoIl': (adesso ?? DateTime.now()).toUtc().toIso8601String(),
    'campi': [
      for (final c in ordinati)
        {
          'id': c.id,
          'nome': c.nome,
          'tipo': c.tipo,
          'visibile': c.visibile,
          'opzioni': c.opzioni.map((o) => o.toMap()).toList(),
        },
    ],
  });
}

/// Legge una lista di campi da [raw]: il file di "Esporta", oppure — per
/// comodità, come per gli ospedali — un backup completo, che ha la tabella
/// `campi_servizio`. Le voci rovinate o di un tipo sconosciuto si saltano e
/// si contano in `scartati`. Lancia FormatException se il file non contiene
/// proprio una lista di campi.
({List<CampoServizio> campi, int scartati}) campiDaJson(String raw) {
  final dynamic payload;
  try {
    payload = jsonDecode(raw);
  } catch (_) {
    throw const FormatException('File non valido (JSON malformato).');
  }
  if (payload is! Map) throw const FormatException('Il file non contiene una lista di campi.');
  final formato = payload['formato'];
  if (formato != null && formato != kFormatoCampi) {
    throw const FormatException('Il file non contiene una lista di campi.');
  }
  final lista = payload['campi'] ?? payload['campi_servizio'];
  if (lista is! List) throw const FormatException('Il file non contiene una lista di campi.');

  final campi = <CampoServizio>[];
  var scartati = 0;
  for (final voce in lista) {
    final campo = voce is Map ? _campoDaMappa(voce) : null;
    if (campo == null) {
      scartati++;
    } else {
      campi.add(campo.copyWith(ordine: campi.length));
    }
  }
  return (campi: campi, scartati: scartati);
}

/// Una voce del file come campo, o null se manca qualcosa di essenziale.
/// Le opzioni possono essere una lista (file di "Esporta") o una stringa
/// JSON (riga di un backup); `visibile` un booleano o 0/1.
CampoServizio? _campoDaMappa(Map<dynamic, dynamic> m) {
  final nome = m['nome'];
  final tipo = m['tipo'];
  if (nome is! String || nome.trim().isEmpty) return null;
  if (tipo is! String || !(tipiCampoServizio.contains(tipo) || tipo == kCampoSessoEta)) return null;
  dynamic opzioniRaw = m['opzioni'];
  if (opzioniRaw is String) {
    try {
      opzioniRaw = jsonDecode(opzioniRaw);
    } catch (_) {
      opzioniRaw = null;
    }
  }
  final opzioni = <OpzioneCampo>[];
  if (opzioniRaw is List) {
    for (final o in opzioniRaw.whereType<Map>()) {
      if (o['id'] is String && o['nome'] is String && (o['nome'] as String).trim().isNotEmpty) {
        opzioni.add(OpzioneCampo(
          id: o['id'] as String,
          nome: (o['nome'] as String).trim(),
          colore: o['colore'] is String ? o['colore'] as String : null,
        ));
      }
    }
  }
  final visibile = m['visibile'];
  final id = m['id'];
  return CampoServizio(
    id: id is String && id.isNotEmpty ? id : _uuid.v4(),
    nome: nome.trim(),
    tipo: tipo,
    opzioni: tipoConOpzioni(tipo) ? opzioni : const [],
    visibile: visibile is bool ? visibile : (visibile is num ? visibile != 0 : true),
  );
}

/// Risultato di unisciCampi: la lista da salvare (con `ordine` già
/// assegnato) e cosa è successo, per il messaggio all'utente.
class EsitoUnioneCampi {
  final List<CampoServizio> campi;
  final int aggiornati;
  final int nuovi;
  // Campi del file che hanno lo stesso nome di uno del dispositivo ma un
  // tipo incompatibile: unirli farebbe perdere i valori, quindi si saltano.
  final List<String> saltati;
  const EsitoUnioneCampi(this.campi, {required this.aggiornati, required this.nuovi, required this.saltati});
}

/// true se un campo di tipo [da] può diventare di tipo [a] senza perdere
/// valori né cambiarne la forma: stesso tipo, oppure tendina e colori
/// (stessi valori, stessi id). La combo box salva una lista di id, quindi
/// si unisce solo con un'altra combo box.
bool _tipiCompatibili(String da, String a) =>
    da == a || {da, a}.difference({kCampoTendina, kCampoColori}).isEmpty;

/// Unisce la lista [daFile] a quella del dispositivo [locali], come scelto
/// dall'utente: i campi uguali si aggiornano, quelli nuovi si aggiungono,
/// quelli solo sul dispositivo restano. Nessun valore salvato nei servizi
/// può andare perso:
/// - un campo si riconosce per id, poi per nome (senza badare a maiuscole);
///   il campo speciale sesso ed età si riconosce anche solo dal tipo;
/// - di un campo riconosciuto restano l'id (i servizi puntano a quello) e i
///   valori dell'elenco che il file non ha, in fondo; nome, tipo,
///   visibilità e i valori del file vincono;
/// - un campo con lo stesso nome ma un tipo incompatibile non si tocca.
/// L'ordine diventa quello del file, coi campi solo del dispositivo dopo.
/// [palette] dà i colori ai valori che ne restano senza in un campo a colori.
EsitoUnioneCampi unisciCampi(List<CampoServizio> locali, List<CampoServizio> daFile,
    {List<String> palette = const ['#757575']}) {
  final usati = <String>{};
  final risultato = <CampoServizio>[];
  final saltati = <String>[];
  var aggiornati = 0, nuovi = 0;

  CampoServizio? trova(CampoServizio f) {
    for (final l in locali) {
      if (!usati.contains(l.id) && l.id == f.id) return l;
    }
    for (final l in locali) {
      if (usati.contains(l.id)) continue;
      if (f.speciale && l.speciale) return l;
      if (l.nome.toLowerCase() == f.nome.toLowerCase()) return l;
    }
    return null;
  }

  final idLocali = locali.map((l) => l.id).toSet();
  for (final f in daFile) {
    final l = trova(f);
    if (l != null && (l.speciale != f.speciale || !_tipiCompatibili(l.tipo, f.tipo))) {
      saltati.add(f.nome);
      continue; // il campo del dispositivo resta com'è, fra quelli solo locali
    }
    if (l != null) {
      usati.add(l.id);
      aggiornati++;
      risultato.add(CampoServizio(
        id: l.id,
        nome: l.speciale ? l.nome : f.nome,
        tipo: f.tipo,
        opzioni: _unisciOpzioni(l.opzioni, f.opzioni, f.tipo, palette),
        visibile: f.visibile,
        createdAt: l.createdAt,
      ));
    } else {
      // Un id già usato da un altro campo del dispositivo (che non è questo,
      // altrimenti l'avrebbe trovato) si cambia, per non sovrascriverlo.
      final id = idLocali.contains(f.id) ? _uuid.v4() : f.id;
      nuovi++;
      risultato.add(CampoServizio(
        id: id,
        nome: f.nome,
        tipo: f.tipo,
        opzioni: _unisciOpzioni(const [], f.opzioni, f.tipo, palette),
        visibile: f.visibile,
      ));
    }
  }
  for (final l in locali) {
    if (!usati.contains(l.id)) risultato.add(l);
  }
  return EsitoUnioneCampi(
    [for (var i = 0; i < risultato.length; i++) risultato[i].copyWith(ordine: i)],
    aggiornati: aggiornati,
    nuovi: nuovi,
    saltati: saltati,
  );
}

/// Valori dell'elenco uniti: quelli del file (riconosciuti per id o per
/// nome, tenendo l'id del dispositivo) e poi quelli che c'erano solo sul
/// dispositivo. Solo i campi a colori tengono un colore.
List<OpzioneCampo> _unisciOpzioni(
    List<OpzioneCampo> locali, List<OpzioneCampo> daFile, String tipo, List<String> palette) {
  if (!tipoConOpzioni(tipo)) return const [];
  final colori = tipo == kCampoColori;
  final usati = <String>{};
  final risultato = <OpzioneCampo>[];
  String coloreLibero() {
    final presi = risultato.map((o) => o.colore).toSet();
    return palette.firstWhere((c) => !presi.contains(c), orElse: () => palette.first);
  }

  OpzioneCampo? trova(OpzioneCampo f) {
    for (final l in locali) {
      if (!usati.contains(l.id) && l.id == f.id) return l;
    }
    for (final l in locali) {
      if (!usati.contains(l.id) && l.nome.toLowerCase() == f.nome.toLowerCase()) return l;
    }
    return null;
  }

  final idLocali = locali.map((l) => l.id).toSet();
  for (final f in daFile) {
    final l = trova(f);
    if (l != null) usati.add(l.id);
    final id = l?.id ?? (idLocali.contains(f.id) ? _uuid.v4() : f.id);
    if (risultato.any((o) => o.nome.toLowerCase() == f.nome.toLowerCase())) continue; // doppione nel file
    risultato.add(OpzioneCampo(
      id: id,
      nome: f.nome,
      colore: colori ? (f.colore ?? l?.colore ?? coloreLibero()) : null,
    ));
  }
  for (final l in locali) {
    if (usati.contains(l.id)) continue;
    risultato.add(OpzioneCampo(id: l.id, nome: l.nome, colore: colori ? (l.colore ?? coloreLibero()) : null));
  }
  return risultato;
}
