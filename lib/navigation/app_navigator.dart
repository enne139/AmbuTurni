import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../screens/turni/turni_list.dart';
import '../screens/assistenze/assistenze_list.dart';
import '../screens/statistiche/statistiche_screen.dart';
import '../screens/tools/tools_screen.dart';
import '../screens/impostazioni/impostazioni_screen.dart';

/// Scaffold principale con NavigationBar a 5 tab: Turni, Assistenze,
/// Statistiche, Tools, Impostazioni. Mantiene lo stato di ciascuna tab con
/// IndexedStack per non ricaricare i widget al cambio tab.
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
          TurniList(),
          AssistenzeList(),
          StatisticheScreen(),
          ToolsScreen(),
          ImpostazioniScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.calendar_today_outlined), selectedIcon: Icon(Icons.calendar_today), label: 'Turni'),
          NavigationDestination(icon: Icon(Icons.local_hospital_outlined), selectedIcon: Icon(Icons.local_hospital), label: 'Assistenze'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'Statistiche'),
          NavigationDestination(icon: Icon(Icons.handyman_outlined), selectedIcon: Icon(Icons.handyman), label: 'Tools'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Impostazioni'),
        ],
      ),
    );
  }
}
