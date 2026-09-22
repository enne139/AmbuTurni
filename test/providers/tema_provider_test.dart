// Test di TemaProvider (lib/providers/app_provider.dart). Regola delicata:
// il default (nessuna preferenza salvata) deve restare `ModalitaTema.sistema`
// (ThemeMode.system) — a differenza di altre preferenze del progetto che di
// default preservano il comportamento storico, qui il default è
// esplicitamente "segui il sistema operativo" (richiesta esplicita
// dell'utente). kPrefModalitaChiara è un bool *nullable*: null = sistema,
// true/false = scelta esplicita chiara/scura.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ambu_turni/providers/app_provider.dart';
import 'package:ambu_turni/utils/prefs_keys.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TemaProvider.carica', () {
    test('nessuna preferenza salvata: segue il sistema', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = TemaProvider();
      await provider.carica();
      expect(provider.modalita, ModalitaTema.sistema);
      expect(provider.themeMode, ThemeMode.system);
    });

    test('modalità chiara forzata in precedenza: ripristinata', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.$kPrefModalitaChiara': true,
      });
      final provider = TemaProvider();
      await provider.carica();
      expect(provider.modalita, ModalitaTema.chiaro);
      expect(provider.themeMode, ThemeMode.light);
    });

    test('modalità scura forzata in precedenza: ripristinata', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.$kPrefModalitaChiara': false,
      });
      final provider = TemaProvider();
      await provider.carica();
      expect(provider.modalita, ModalitaTema.scuro);
      expect(provider.themeMode, ThemeMode.dark);
    });
  });

  group('TemaProvider.setModalita', () {
    test('chiaro/scuro persistono un bool esplicito', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = TemaProvider();
      await provider.carica();

      await provider.setModalita(ModalitaTema.chiaro);
      expect(provider.modalita, ModalitaTema.chiaro);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kPrefModalitaChiara), isTrue);

      await provider.setModalita(ModalitaTema.scuro);
      expect(provider.modalita, ModalitaTema.scuro);
      expect(prefs.getBool(kPrefModalitaChiara), isFalse);
    });

    test('tornare a sistema rimuove la preferenza salvata (non scrive un valore a parte)', () async {
      SharedPreferences.setMockInitialValues({
        'flutter.$kPrefModalitaChiara': true,
      });
      final provider = TemaProvider();
      await provider.carica();
      expect(provider.modalita, ModalitaTema.chiaro);

      await provider.setModalita(ModalitaTema.sistema);
      expect(provider.modalita, ModalitaTema.sistema);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(kPrefModalitaChiara), isNull);
    });
  });
}
