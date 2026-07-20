// Test di NavigazioneProvider (lib/providers/app_provider.dart). Due regole
// delicate: (1) il default quando nessuna preferenza è mai stata salvata è
// Attività/Statistiche disattivate e Piano turni in navbar/pagina principale
// (richiesta esplicita, applicata anche a device con dati già esistenti,
// vedi CLAUDE.md) — l'opposto del comportamento "storico"; (2) Attività
// disattivata (o Piano turni non in navbar) non può mai restare la pagina
// principale, sia al caricamento sia quando la si disattiva da attiva.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ambu_turni/providers/app_provider.dart';
import 'package:ambu_turni/utils/prefs_keys.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NavigazioneProvider.carica', () {
    test(
        'nessuna preferenza salvata: Attività/Statistiche disattivate, Piano turni in navbar e pagina principale',
        () async {
      SharedPreferences.setMockInitialValues({});
      final provider = NavigazioneProvider();
      await provider.carica();
      expect(provider.attivitaStatisticheAttive, isFalse);
      expect(provider.pianoTurniInNavbar, isTrue);
      expect(provider.paginaPrincipale, PaginaPrincipale.pianoTurni);
    });

    test('pagina principale "tools" salvata viene rispettata', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.$kPrefPaginaPrincipale': 'tools',
      });
      final provider = NavigazioneProvider();
      await provider.carica();
      expect(provider.paginaPrincipale, PaginaPrincipale.tools);
    });

    test('pagina principale "attivita" salvata viene rispettata se Attività/Statistiche sono attive',
        () async {
      SharedPreferences.setMockInitialValues({
        'flutter.$kPrefAttivitaStatisticheAttive': true,
        'flutter.$kPrefPaginaPrincipale': 'attivita',
      });
      final provider = NavigazioneProvider();
      await provider.carica();
      expect(provider.paginaPrincipale, PaginaPrincipale.attivita);
    });

    test(
        'Attività/Statistiche disattivate forzano la pagina principale su Tools anche se era salvata "attivita"',
        () async {
      SharedPreferences.setMockInitialValues({
        'flutter.$kPrefAttivitaStatisticheAttive': false,
        'flutter.$kPrefPaginaPrincipale': 'attivita',
      });
      final provider = NavigazioneProvider();
      await provider.carica();
      expect(provider.attivitaStatisticheAttive, isFalse);
      expect(provider.paginaPrincipale, PaginaPrincipale.tools);
    });

    test('pagina principale "piano_turni" salvata viene rispettata se Piano turni è in navbar',
        () async {
      SharedPreferences.setMockInitialValues({
        'flutter.$kPrefPianoTurniInNavbar': true,
        'flutter.$kPrefPaginaPrincipale': 'piano_turni',
      });
      final provider = NavigazioneProvider();
      await provider.carica();
      expect(provider.pianoTurniInNavbar, isTrue);
      expect(provider.paginaPrincipale, PaginaPrincipale.pianoTurni);
    });

    test('pagina principale "piano_turni" salvata viene ignorata se Piano turni NON è in navbar',
        () async {
      SharedPreferences.setMockInitialValues({
        'flutter.$kPrefPianoTurniInNavbar': false,
        'flutter.$kPrefPaginaPrincipale': 'piano_turni',
      });
      final provider = NavigazioneProvider();
      await provider.carica();
      expect(provider.pianoTurniInNavbar, isFalse);
      expect(provider.paginaPrincipale, PaginaPrincipale.tools);
    });
  });

  group('NavigazioneProvider.setAttivitaStatisticheAttive', () {
    test('disattivare mentre Attività è la pagina principale la sposta su Tools (e persiste)',
        () async {
      SharedPreferences.setMockInitialValues({
        'flutter.$kPrefAttivitaStatisticheAttive': true,
        'flutter.$kPrefPaginaPrincipale': 'attivita',
      });
      final provider = NavigazioneProvider();
      await provider.carica();
      expect(provider.paginaPrincipale, PaginaPrincipale.attivita);

      await provider.setAttivitaStatisticheAttive(false);
      expect(provider.attivitaStatisticheAttive, isFalse);
      expect(provider.paginaPrincipale, PaginaPrincipale.tools);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kPrefAttivitaStatisticheAttive), isFalse);
      expect(prefs.getString(kPrefPaginaPrincipale), 'tools');
    });

    test('disattivare quando la pagina principale è già Tools non tocca la preferenza pagina',
        () async {
      SharedPreferences.setMockInitialValues({
        'flutter.$kPrefPaginaPrincipale': 'tools',
      });
      final provider = NavigazioneProvider();
      await provider.carica();

      await provider.setAttivitaStatisticheAttive(false);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kPrefPaginaPrincipale), 'tools');
    });

    test('riattivare non cambia da sola la pagina principale', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.$kPrefAttivitaStatisticheAttive': false,
        'flutter.$kPrefPaginaPrincipale': 'attivita',
      });
      final provider = NavigazioneProvider();
      await provider.carica();
      expect(provider.paginaPrincipale, PaginaPrincipale.tools);

      await provider.setAttivitaStatisticheAttive(true);
      expect(provider.attivitaStatisticheAttive, isTrue);
      // Resta su Tools finché l'utente non la cambia esplicitamente.
      expect(provider.paginaPrincipale, PaginaPrincipale.tools);
    });
  });

  group('NavigazioneProvider.setPaginaPrincipale', () {
    test('imposta e persiste la scelta', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = NavigazioneProvider();
      await provider.carica();

      await provider.setPaginaPrincipale(PaginaPrincipale.tools);
      expect(provider.paginaPrincipale, PaginaPrincipale.tools);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(kPrefPaginaPrincipale), 'tools');
    });
  });

  group('NavigazioneProvider.setPianoTurniInNavbar', () {
    test('attivarla imposta subito Piano turni come pagina principale (e persiste)', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.$kPrefPianoTurniInNavbar': false,
        'flutter.$kPrefAttivitaStatisticheAttive': true,
        'flutter.$kPrefPaginaPrincipale': 'attivita',
      });
      final provider = NavigazioneProvider();
      await provider.carica();
      expect(provider.paginaPrincipale, PaginaPrincipale.attivita);

      await provider.setPianoTurniInNavbar(true);
      expect(provider.pianoTurniInNavbar, isTrue);
      expect(provider.paginaPrincipale, PaginaPrincipale.pianoTurni);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kPrefPianoTurniInNavbar), isTrue);
      expect(prefs.getString(kPrefPaginaPrincipale), 'piano_turni');
    });

    test('disattivarla mentre è la pagina principale ripiega su Attività se attiva', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.$kPrefAttivitaStatisticheAttive': true,
      });
      final provider = NavigazioneProvider();
      await provider.carica();
      await provider.setPianoTurniInNavbar(true);

      await provider.setPianoTurniInNavbar(false);
      expect(provider.pianoTurniInNavbar, isFalse);
      expect(provider.paginaPrincipale, PaginaPrincipale.attivita);
    });

    test('disattivarla mentre è la pagina principale ripiega su Tools se Attività è disattivata',
        () async {
      SharedPreferences.setMockInitialValues({});
      final provider = NavigazioneProvider();
      await provider.carica();
      await provider.setAttivitaStatisticheAttive(false);
      await provider.setPianoTurniInNavbar(true);

      await provider.setPianoTurniInNavbar(false);
      expect(provider.paginaPrincipale, PaginaPrincipale.tools);
    });

    test('disattivarla mentre la pagina principale è un\'altra non la cambia', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = NavigazioneProvider();
      await provider.carica();
      await provider.setPianoTurniInNavbar(true);
      await provider.setPaginaPrincipale(PaginaPrincipale.tools);

      await provider.setPianoTurniInNavbar(false);
      expect(provider.paginaPrincipale, PaginaPrincipale.tools);
    });
  });
}
