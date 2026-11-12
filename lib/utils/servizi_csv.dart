// Export dei servizi in CSV (Impostazioni → Backup → "Esporta servizi in
// CSV"). Dart puro, testato in test/utils/servizi_csv_test.dart: qui solo
// il formato, la lettura dal DB è in backup.dart.
import '../db/models.dart';

/// Un servizio con i dati del suo turno, già risolti in testo leggibile.
class RigaServizioCsv {
  final String data; // AAAA-MM-GG, come nel DB
  final int? numeroTurno;
  final String? associazione;
  final String tipologie; // nomi separati da virgola
  final String? orario;
  final int numeroServizio; // posizione nel turno, da 1
  final String? codiceChiamata;
  final String? codiceUscita;
  final String? ospedale;
  final String? citta;
  final String? descrizione;
  final Map<String, dynamic> campi;

  const RigaServizioCsv({
    required this.data,
    this.numeroTurno,
    this.associazione,
    this.tipologie = '',
    this.orario,
    required this.numeroServizio,
    this.codiceChiamata,
    this.codiceUscita,
    this.ospedale,
    this.citta,
    this.descrizione,
    this.campi = const {},
  });
}

/// I servizi in CSV pensato per Excel/LibreOffice in italiano: separatore
/// punto e virgola (la virgola è il separatore decimale), numeri con la
/// virgola, date GG/MM/AAAA, BOM UTF-8 in testa (senza, Excel legge male
/// accenti e "à" di "Età") e righe chiuse da CRLF. Una riga per servizio,
/// con i dati del turno, e una colonna per ogni campo in [campi] nell'ordine
/// dato; il campo speciale sesso ed età fa due colonne, "Sesso" ed "Età".
/// I valori che non valgono più per la definizione del campo restano vuoti.
String serviziInCsv(List<RigaServizioCsv> righe, List<CampoServizio> campi) {
  final intestazione = [
    'Data', 'Turno n.', 'Associazione', 'Tipologia', 'Orario turno', 'Servizio n.',
    'Codice chiamata', 'Codice uscita', 'Ospedale', 'Città', 'Descrizione',
    for (final c in campi) ...(c.speciale ? ['Sesso', 'Età'] : [c.nome]),
  ];
  final buffer = StringBuffer('﻿')..write(_riga(intestazione));
  for (final r in righe) {
    buffer.write(_riga([
      _data(r.data),
      r.numeroTurno?.toString(),
      r.associazione,
      r.tipologie,
      r.orario,
      '${r.numeroServizio}',
      r.codiceChiamata,
      r.codiceUscita,
      r.ospedale,
      r.citta,
      r.descrizione,
      for (final c in campi) ..._valori(c, r.campi[c.id]),
    ]));
  }
  return buffer.toString();
}

/// Le celle di un campo: due per lo speciale (sesso, età), una per gli altri.
List<String?> _valori(CampoServizio campo, dynamic valore) {
  if (campo.speciale) {
    final v = campo.pulisci(valore);
    final eta = campo.etaDi(v);
    return [campo.sessoDi(v)?.nome, eta == null ? null : formatNumeroCampo(eta)];
  }
  return [campo.etichetta(valore)];
}

/// "2026-11-10" → "10/11/2026"; un valore in un formato diverso resta com'è.
String _data(String iso) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(iso);
  return m == null ? iso : '${m[3]}/${m[2]}/${m[1]}';
}

String _riga(List<String?> celle) => '${celle.map(_cella).join(';')}\r\n';

/// Una cella: tra virgolette se contiene il separatore, virgolette o a capo
/// (le descrizioni in markdown possono averne), con le virgolette raddoppiate.
String _cella(String? valore) {
  final v = valore ?? '';
  if (!v.contains(RegExp('[;"\r\n]'))) return v;
  return '"${v.replaceAll('"', '""')}"';
}
