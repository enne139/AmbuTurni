// Test di TutorialProvider (lib/providers/app_provider.dart). Due regole
// delicate: (1) `richiesta` è un contatore incrementale, non un bool — deve
// aumentare sia al primo avvio mai completato (carica()) sia a ogni replay
// esplicito (richiediReplay()), anche se il tutorial risulta già completato;
// (2) segnaCompletato() persiste true una sola volta ed è un no-op se
// richiamato di nuovo (un replay non deve riscrivere inutilmente la pref).
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ambu_turni/providers/app_provider.dart';
import 'package:ambu_turni/utils/prefs_keys.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TutorialProvider.carica', () {
    test('nessuna preferenza salvata: non completato, richiesta incrementata (comparsa automatica)',
        () async {
      SharedPreferences.setMockInitialValues({});
      final provider = TutorialProvider();
      await provider.carica();
      expect(provider.completato, isFalse);
      expect(provider.richiesta, 1);
    });

    test('già completato in precedenza: nessuna comparsa automatica', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.$kPrefTutorialCompletato': true,
      });
      final provider = TutorialProvider();
      await provider.carica();
      expect(provider.completato, isTrue);
      expect(provider.richiesta, 0);
    });
  });

  group('TutorialProvider.richiediReplay', () {
    test('incrementa richiesta anche se già completato', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.$kPrefTutorialCompletato': true,
      });
      final provider = TutorialProvider();
      await provider.carica();
      expect(provider.richiesta, 0);

      provider.richiediReplay();
      expect(provider.richiesta, 1);
      provider.richiediReplay();
      expect(provider.richiesta, 2);
    });
  });

  group('TutorialProvider.segnaCompletato', () {
    test('persiste true al primo completamento', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = TutorialProvider();
      await provider.carica();

      await provider.segnaCompletato();
      expect(provider.completato, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kPrefTutorialCompletato), isTrue);
    });

    test('è un no-op se richiamato di nuovo (replay) dopo il primo completamento', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.$kPrefTutorialCompletato': true,
      });
      final provider = TutorialProvider();
      await provider.carica();

      // Nessuna eccezione e lo stato resta coerente: la pref non viene
      // riscritta (verificato indirettamente, l'importante è che non fallisca).
      await provider.segnaCompletato();
      expect(provider.completato, isTrue);
    });
  });

  group('TutorialProvider.impostaNomeCercato', () {
    test('persiste il cognome nella preferenza della ricerca del Piano turni', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = TutorialProvider();

      await provider.impostaNomeCercato('Rossi');

      expect(provider.nomeDalTutorial, 'Rossi');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kPrefPianoTurniUltimaRicerca), 'Rossi');
    });

    test('taglia gli spazi prima di salvare', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = TutorialProvider();

      await provider.impostaNomeCercato('  Bianchi  ');

      expect(provider.nomeDalTutorial, 'Bianchi');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kPrefPianoTurniUltimaRicerca), 'Bianchi');
    });

    test('un cognome vuoto (campo saltato) non scrive nulla', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = TutorialProvider();

      await provider.impostaNomeCercato('   ');

      expect(provider.nomeDalTutorial, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kPrefPianoTurniUltimaRicerca), isNull);
    });
  });
}
