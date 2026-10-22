// Test del generatore .ics del Piano turni (lib/utils/calendario_ics.dart).
import 'package:flutter_test/flutter_test.dart';
import 'package:ambu_turni/utils/calendario_ics.dart';

void main() {
  final adesso = DateTime.utc(2026, 10, 22, 8, 0);

  test('più eventi in un solo VCALENDAR, nell\'ordine dato', () {
    final ics = generaIcs([
      EventoCalendario('CVS (sera)', DateTime(2026, 7, 1, 18, 30), DateTime(2026, 7, 1, 23, 30)),
      EventoCalendario('CVS (notte)', DateTime(2026, 7, 2, 23, 30), DateTime(2026, 7, 3, 6, 0)),
    ], adesso: adesso);
    final righe = ics.split('\r\n');
    expect(righe.first, 'BEGIN:VCALENDAR');
    expect(righe.last, 'END:VCALENDAR');
    expect(righe.where((r) => r == 'BEGIN:VEVENT'), hasLength(2));
    expect(righe, containsAllInOrder([
      'DTSTART:20260701T183000', 'DTEND:20260701T233000', 'SUMMARY:CVS (sera)',
      'DTSTART:20260702T233000', 'DTEND:20260703T060000', 'SUMMARY:CVS (notte)',
    ]));
    expect(righe.where((r) => r == 'DTSTAMP:20261022T080000Z'), hasLength(2));
  });

  test('UID deterministico, diverso per eventi diversi, senza caratteri speciali', () {
    final e = EventoCalendario('CVS (sera)', DateTime(2026, 7, 1, 18, 30), DateTime(2026, 7, 1, 23, 30));
    String uid(String ics) => ics.split('\r\n').firstWhere((r) => r.startsWith('UID:'));
    final a = uid(generaIcs([e], adesso: adesso));
    final b = uid(generaIcs([e], adesso: DateTime.utc(2027)));
    expect(a, b); // stesso turno reimportato = stesso UID
    expect(a, 'UID:20260701T183000-cvs-sera-@ambuturni');
    final altro = uid(generaIcs([
      EventoCalendario('CVS (sera)', DateTime(2026, 7, 2, 18, 30), DateTime(2026, 7, 2, 23, 30)),
    ]));
    expect(altro, isNot(a));
  });

  test('titolo con caratteri riservati escapato', () {
    final ics = generaIcs([
      EventoCalendario(r'a;b,c\d', DateTime(2026, 7, 1, 8), DateTime(2026, 7, 1, 9)),
    ]);
    expect(ics, contains(r'SUMMARY:a\;b\,c\\d'));
  });

  test('lista vuota: calendario valido senza eventi', () {
    expect(generaIcs([]).split('\r\n'),
        ['BEGIN:VCALENDAR', 'VERSION:2.0', 'PRODID:-//AmbuTurni//IT', 'END:VCALENDAR']);
  });
}
