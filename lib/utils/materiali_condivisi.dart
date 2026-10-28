// Materiali usati condivisi con tutti (tool Materiali usati, interruttore
// "Condivisi") e mezzi dell'associazione, entrambi dal backend condiviso.
// Dart puro (niente import Flutter), come comunicati.dart, per essere
// unit-testabile senza montare widget.

/// Un materiale usato condiviso sul backend (tabella
/// materiali_usati_condivisi). Il materiale è un NOME, non un id del
/// catalogo locale: ogni device ha id propri, i cataloghi si allineano solo
/// per nome (vedi upsertMateriali in db/helpers.dart).
class MaterialeUsatoCondiviso {
  final String id;
  final String materiale;
  final int quantita;
  final String? unita;
  final String? posizione;
  final String? mezzo;
  final String? note;
  final String creatoDa;
  final DateTime? createdAt;

  const MaterialeUsatoCondiviso({
    required this.id,
    required this.materiale,
    this.quantita = 1,
    this.unita,
    this.posizione,
    this.mezzo,
    this.note,
    this.creatoDa = '',
    this.createdAt,
  });

  /// Tollerante su campi assenti o di tipo inatteso (un backend più vecchio
  /// o più nuovo dell'app): null invece di un'eccezione. Restituisce null
  /// solo se mancano id o materiale, senza i quali la riga non è usabile.
  static MaterialeUsatoCondiviso? fromJson(Map<String, dynamic> m) {
    final id = m['id'];
    final materiale = m['materiale'];
    if (id is! String || id.isEmpty || materiale is! String || materiale.isEmpty) return null;
    String? testo(Object? v) => (v is String && v.trim().isNotEmpty) ? v : null;
    final quantita = m['quantita'];
    final createdAt = m['createdAt'];
    return MaterialeUsatoCondiviso(
      id: id,
      materiale: materiale,
      quantita: quantita is num && quantita >= 1 ? quantita.toInt() : 1,
      unita: testo(m['unita']),
      posizione: testo(m['posizione']),
      mezzo: testo(m['mezzo']),
      note: testo(m['note']),
      creatoDa: m['creatoDa'] is String ? m['creatoDa'] as String : '',
      createdAt: createdAt is String ? DateTime.tryParse(createdAt)?.toLocal() : null,
    );
  }

  /// Stessa etichetta di MaterialeUsato.quantitaLabel (es. "3 flaconi").
  String get quantitaLabel => unita != null && unita!.isNotEmpty ? '$quantita $unita' : '$quantita';

  MaterialeUsatoCondiviso copyWith({int? quantita}) => MaterialeUsatoCondiviso(
        id: id,
        materiale: materiale,
        quantita: quantita ?? this.quantita,
        unita: unita,
        posizione: posizione,
        mezzo: mezzo,
        note: note,
        creatoDa: creatoDa,
        createdAt: createdAt,
      );
}

/// Corpo di POST/PUT /api/materiali-usati. I campi vuoti vanno come null:
/// il server li normalizza comunque, ma così il body dice già cosa si
/// intende ("nessuna unità", non "unità stringa vuota").
Map<String, dynamic> datiMaterialeCondiviso({
  required String materiale,
  required int quantita,
  String? unita,
  String? posizione,
  String? mezzo,
  String? note,
}) {
  String? pulito(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
  return {
    'materiale': materiale.trim(),
    'quantita': quantita,
    'unita': pulito(unita),
    'posizione': pulito(posizione),
    'mezzo': pulito(mezzo),
    'note': pulito(note),
  };
}

/// Nome mezzo valido: un numero a due cifre (stessa regola di
/// nomeMezzoValido lato backend, mezzi.go).
bool nomeMezzoValido(String nome) => RegExp(r'^[0-9]{2}$').hasMatch(nome);

/// Estrae i nomi dei mezzi dalla risposta di GET /api/mezzi (o dalla
/// cache locale): solo nomi validi, senza doppioni, in ordine — con due
/// cifre fisse l'ordine alfabetico coincide con quello numerico.
List<String> nomiMezzi(List<dynamic> righe) {
  final nomi = <String>{};
  for (final r in righe) {
    final nome = r is Map ? r['nome'] : r;
    if (nome is String && nomeMezzoValido(nome.trim())) nomi.add(nome.trim());
  }
  return nomi.toList()..sort();
}

/// Filtra per il mezzo scelto nel selettore in alto: null = tutti i mezzi.
/// Generica perché la stessa regola vale per i materiali locali
/// (MaterialeUsato) e per quelli condivisi, classi diverse.
List<T> filtraPerMezzo<T>(List<T> lista, String? mezzo, String? Function(T) mezzoDi) {
  if (mezzo == null) return lista;
  return lista.where((e) => mezzoDi(e) == mezzo).toList();
}
