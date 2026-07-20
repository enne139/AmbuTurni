// Test di ToolsProvider (lib/providers/app_provider.dart). La logica di
// "grandfathering" in carica() è delicata (un tool aggiunto al catalogo dopo
// che l'utente ha già personalizzato Tools attivi deve comunque prendere il
// proprio default) e merita copertura diretta, non solo verifica manuale.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ambu_turni/providers/app_provider.dart';
import 'package:ambu_turni/utils/prefs_keys.dart';
import 'package:ambu_turni/utils/tools_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ToolsProvider.carica', () {
    test('prima configurazione (nessuna preferenza salvata): applica i default del catalogo', () async {
      SharedPreferences.setMockInitialValues({});
      final provider = ToolsProvider();
      await provider.carica();
      for (final t in kToolsDisponibili) {
        expect(provider.attivo(t.id), t.attivoDiDefault, reason: t.id);
      }
    });

    test('un tool nuovo nel catalogo (assente da kPrefToolsConosciuti) prende il proprio default',
        () async {
      // Simula un device che aveva già personalizzato Tools attivi PRIMA che
      // kToolListaOspedali esistesse: preferenza salvata e "conosciuti" non lo contengono.
      final vecchiId = kToolsDisponibili
          .where((t) => t.id != kToolListaOspedali)
          .map((t) => t.id)
          .toList();
      SharedPreferences.setMockInitialValues({
        'flutter.$kPrefToolsAttivi': [kToolMaterialiUsati],
        'flutter.$kPrefToolsConosciuti': vecchiId,
      });
      final provider = ToolsProvider();
      await provider.carica();
      // Il tool nuovo prende il suo default (true), non resta escluso solo
      // perché non compariva nella preferenza salvata in passato.
      expect(provider.attivo(kToolListaOspedali), isTrue);
      // Le scelte esplicite sui tool già noti restano rispettate.
      expect(provider.attivo(kToolMaterialiUsati), isTrue);
      expect(provider.attivo(kToolPianoTurni), isFalse);
    });

    test('un tool già noto e disattivato esplicitamente resta disattivato anche a caricamenti successivi',
        () async {
      SharedPreferences.setMockInitialValues({
        'flutter.$kPrefToolsAttivi': <String>[],
        'flutter.$kPrefToolsConosciuti': kToolsDisponibili.map((t) => t.id).toList(),
      });
      final provider = ToolsProvider();
      await provider.carica();
      for (final t in kToolsDisponibili) {
        expect(provider.attivo(t.id), isFalse, reason: t.id);
      }
      // Una seconda carica() non reintroduce nulla: tutti gli id sono ormai "conosciuti".
      await provider.carica();
      for (final t in kToolsDisponibili) {
        expect(provider.attivo(t.id), isFalse, reason: t.id);
      }
    });
  });
}
