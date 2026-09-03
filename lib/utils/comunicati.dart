// Parsing/raggruppamento dei comunicati (Tools → Archivio comunicati).
// Dart puro (niente import Flutter), come piano_mensile.dart/geocoding_api.dart,
// per essere unit-testabile senza dover montare un widget.
import 'format.dart';

/// Estrae la data dai primi 8 caratteri del nome file (formato "AAAAMMGG",
/// convenzione reale con cui l'associazione nomina i PDF caricati, es.
/// "20260115_003_verbale-assemblea.pdf" — il numero progressivo dopo la
/// data si azzera ogni anno, quindi non è utile da solo per ordinare tra
/// anni diversi). null se il nome non rispetta il formato: quei comunicati
/// non spariscono dal raggruppamento, vedi dataComunicato sotto.
DateTime? dataDaNomeFile(String? fileName) {
  if (fileName == null || fileName.length < 8) return null;
  final prefisso = fileName.substring(0, 8);
  if (!RegExp(r'^\d{8}$').hasMatch(prefisso)) return null;
  final anno = int.parse(prefisso.substring(0, 4));
  final mese = int.parse(prefisso.substring(4, 6));
  final giorno = int.parse(prefisso.substring(6, 8));
  if (mese < 1 || mese > 12 || giorno < 1 || giorno > 31) return null;
  final d = DateTime(anno, mese, giorno);
  // DateTime normalizza silenziosamente un giorno fuori scala (es. 31 in un
  // mese da 30) spostandolo al mese successivo: se non torna il giorno
  // richiesto il nome non è una data reale, non va trattato come tale.
  return d.day == giorno && d.month == mese && d.year == anno ? d : null;
}

/// Data "vera" di un comunicato per ordinamento/raggruppamento: quella nel
/// nome file se riconoscibile, altrimenti la data di caricamento
/// (createdAt) — mai perdere un comunicato dal raggruppamento solo perché
/// non segue la convenzione di nome (es. caricato a mano dalla pagina admin
/// senza rinominarlo). Se anche createdAt manca/non è valido, un fallback
/// fisso nel passato: il comunicato resta visibile, solo relegato in fondo.
DateTime dataComunicato(Map<String, dynamic> c) {
  return dataDaNomeFile(c['fileName'] as String?) ??
      DateTime.tryParse(c['createdAt'] as String? ?? '') ??
      DateTime(1970);
}

/// Raggruppa [comunicati] per mese/anno della data "vera" sopra, mesi in
/// ordine dal più recente: nessun package, stessa filosofia "niente
/// dipendenza per una lista con intestazioni di sezione" già seguita per il
/// raggruppamento per regione di Lista ospedali. L'ordinamento dei gruppi
/// segue l'ordine di inserimento di Map in Dart: basta ordinare
/// [comunicati] prima di raggrupparli, non serve riordinare le chiavi dopo.
Map<String, List<Map<String, dynamic>>> raggruppaPerMese(List<Map<String, dynamic>> comunicati) {
  final ordinati = [...comunicati]..sort((a, b) => dataComunicato(b).compareTo(dataComunicato(a)));
  final gruppi = <String, List<Map<String, dynamic>>>{};
  for (final c in ordinati) {
    final d = dataComunicato(c);
    final chiave = '${kMesiItaliani[d.month - 1]} ${d.year}';
    gruppi.putIfAbsent(chiave, () => []).add(c);
  }
  return gruppi;
}
