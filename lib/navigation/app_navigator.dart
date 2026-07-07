import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../screens/turni/turni_list.dart';
import '../screens/assistenze/assistenze_list.dart';
import '../screens/statistiche/statistiche_screen.dart';
import '../screens/tools/tools_screen.dart';
import '../screens/impostazioni/impostazioni_screen.dart';
import '../utils/theme.dart';

/// Scaffold principale con NavigationBar a 4 tab: Attività (turni +
/// assistenze), Statistiche, Tools, Impostazioni. Mantiene lo stato di
/// ciascuna tab con IndexedStack per non ricaricare i widget al cambio tab.
class AppNavigator extends StatefulWidget {
  const AppNavigator({super.key});

  @override
  State<AppNavigator> createState() => _AppNavigatorState();
}

class _AppNavigatorState extends State<AppNavigator> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // Carica le anagrafiche una sola volta all'avvio.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AnagraficheProvider>().carica();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: const [
          _AttivitaTab(),
          StatisticheScreen(),
          ToolsScreen(),
          ImpostazioniScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.calendar_today_outlined), selectedIcon: Icon(Icons.calendar_today), label: 'Attività'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'Statistiche'),
          NavigationDestination(icon: Icon(Icons.handyman_outlined), selectedIcon: Icon(Icons.handyman), label: 'Tools'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Impostazioni'),
        ],
      ),
    );
  }
}

/// Tab unificata Turni + Assistenze: un selettore sotto l'AppBar passa da
/// una lista all'altra. Le due liste restano widget indipendenti coi loro
/// Scaffold/FAB e vivono in un IndexedStack, così filtri, ricerca e vista
/// calendario non si perdono passando avanti e indietro; il selettore viene
/// iniettato nelle loro AppBar (parametro `selettore`), unico punto di
/// contatto tra le liste e la tab che le ospita.
class _AttivitaTab extends StatefulWidget {
  const _AttivitaTab();

  @override
  State<_AttivitaTab> createState() => _AttivitaTabState();
}

class _AttivitaTabState extends State<_AttivitaTab> {
  int _sezione = 0; // 0 = turni, 1 = assistenze

  PreferredSizeWidget _selettore() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(52),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
        child: SegmentedButton<int>(
          segments: const [
            ButtonSegment(
              value: 0,
              label: Text('Turni'),
              icon: Icon(Icons.calendar_today_outlined, size: 16),
            ),
            ButtonSegment(
              value: 1,
              label: Text('Assistenze'),
              icon: Icon(Icons.local_hospital_outlined, size: 16),
            ),
          ],
          selected: {_sezione},
          onSelectionChanged: (s) => setState(() => _sezione = s.first),
          showSelectedIcon: false,
          // expandedInsets: il bottone riempie la larghezza invece di
          // galleggiare al centro con la dimensione minima.
          expandedInsets: EdgeInsets.zero,
          style: SegmentedButton.styleFrom(
            foregroundColor: Colors.white70,
            selectedForegroundColor: Colors.white,
            selectedBackgroundColor: kPrimary.withValues(alpha: 0.25),
            side: const BorderSide(color: kCardBorder),
            visualDensity: VisualDensity.compact,
            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: _sezione,
      children: [
        TurniList(selettore: _selettore()),
        AssistenzeList(selettore: _selettore()),
      ],
    );
  }
}
