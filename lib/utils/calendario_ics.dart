// Generazione di file calendario .ics (RFC 5545) per il Piano turni: un
// singolo turno (desktop/web, dove add_2_calendar non esiste) o tutti i
// turni del mese di un volontario in un solo file, importabile in blocco —
// l'intent Android di add_2_calendar crea un evento alla volta, quindi per
// "tutti i miei turni" il file è l'unica strada su ogni piattaforma.
//
// Dart puro (niente import Flutter), come piano_mensile.dart: unit-testato.

/// Un evento da scrivere nel file: titolo e intervallo, nient'altro (niente
/// descrizione, per scelta dell'utente — stesso formato dell'intent Android).
class EventoCalendario {
  final String titolo;
  final DateTime inizio;
  final DateTime fine;

  const EventoCalendario(this.titolo, this.inizio, this.fine);
}

/// Contenuto di un file .ics con [eventi], nell'ordine dato.
/// Orari "floating" (senza Z/TZID): stesso orario locale passato all'intent
/// Android, nessuna conversione fuso orario altrove nel codice.
/// UID deterministico (inizio + titolo) invece che casuale: reimportare lo
/// stesso mese dopo un aggiornamento del foglio, in un'app calendario che
/// rispetta l'UID, aggiorna gli eventi esistenti invece di duplicarli.
/// [adesso] solo per i test (DTSTAMP stabile).
String generaIcs(List<EventoCalendario> eventi, {DateTime? adesso}) {
  final dtstamp = '${_fmt((adesso ?? DateTime.now()).toUtc())}Z';
  return [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//AmbuTurni//IT',
    for (final e in eventi) ...[
      'BEGIN:VEVENT',
      'UID:${_uid(e)}',
      'DTSTAMP:$dtstamp',
      'DTSTART:${_fmt(e.inizio)}',
      'DTEND:${_fmt(e.fine)}',
      'SUMMARY:${_esc(e.titolo)}',
      'END:VEVENT',
    ],
    'END:VCALENDAR',
  ].join('\r\n');
}

String _fmt(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}'
    '${d.month.toString().padLeft(2, '0')}'
    '${d.day.toString().padLeft(2, '0')}T'
    '${d.hour.toString().padLeft(2, '0')}'
    '${d.minute.toString().padLeft(2, '0')}'
    '${d.second.toString().padLeft(2, '0')}';

String _esc(String s) => s
    .replaceAll('\\', '\\\\')
    .replaceAll(';', '\\;')
    .replaceAll(',', '\\,')
    .replaceAll('\n', '\\n');

/// Titolo ridotto a lettere/cifre: l'UID non deve contenere caratteri che
/// andrebbero escapati (spazi, parentesi).
String _uid(EventoCalendario e) {
  final slug = e.titolo.toLowerCase().replaceAll(RegExp('[^a-z0-9]+'), '-');
  return '${_fmt(e.inizio)}-$slug@ambuturni';
}
