import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/app_provider.dart';
import '../screens/anagrafiche/anagrafiche_screen.dart';
import '../screens/turni/turni_list.dart';
import '../screens/assistenze/assistenze_list.dart';
import '../screens/statistiche/statistiche_screen.dart';
import '../screens/tools/tools_screen.dart';
import '../screens/tools/piano_turni_screen.dart';
import '../screens/impostazioni/impostazioni_screen.dart';
import '../utils/theme.dart';

/// Identità logica di una tab, indipendente dalla sua posizione: le tab
/// Attività e Statistiche possono essere nascoste insieme, e Piano turni può
/// comparire come voce propria (entrambe da Impostazioni → Navigazione),
/// quindi la posizione delle altre nella NavigationBar/IndexedStack si
/// sposta — tenere la selezione per identità invece che per indice numerico
/// evita di dover tradurre manualmente gli indici a ogni cambio di
/// `attivitaStatisticheAttive`/`pianoTurniInNavbar`, e se la tab attualmente
/// aperta (es. Impostazioni) resta visibile, resta selezionata alla sua
/// nuova posizione senza alcun caso speciale.
enum _TabId { attivita, statistiche, pianoTurni, tools, impostazioni }

/// Scaffold principale con NavigationBar: Attività (turni + assistenze) e
/// Statistiche (disattivabili insieme), Piano turni (opzionale, spostato
/// dalla tab Tools), Tools, Impostazioni. Mantiene lo stato di ciascuna tab
/// con IndexedStack per non ricaricare i widget al cambio tab.
class AppNavigator extends StatefulWidget {
  const AppNavigator({super.key});

  @override
  State<AppNavigator> createState() => _AppNavigatorState();
}

class _AppNavigatorState extends State<AppNavigator> {
  // Default coerente con NavigazioneProvider (Piano turni in navbar e come
  // pagina principale, Attività/Statistiche disattivate): nessun flash
  // visibile prima che carica() confermi la preferenza salvata.
  _TabId _tabSelezionata = _TabId.pianoTurni;

  @override
  void initState() {
    super.initState();
    // Carica le anagrafiche e i tool attivi una sola volta all'avvio.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      context.read<AnagraficheProvider>().carica();
      context.read<ToolsProvider>().carica();
      final nav = context.read<NavigazioneProvider>();
      await nav.carica();
      // Pagina principale scelta in Impostazioni → Navigazione: applicata
      // solo ora che è nota (prima di `carica()` il default coincide già col
      // valore iniziale del campo, nessun flash visibile in assenza di una
      // preferenza salvata).
      if (mounted) {
        setState(() => _tabSelezionata = switch (nav.paginaPrincipale) {
              PaginaPrincipale.tools => _TabId.tools,
              PaginaPrincipale.pianoTurni => _TabId.pianoTurni,
              PaginaPrincipale.attivita => _TabId.attivita,
            });
      }
    });
  }

  List<_TabId> _tabsVisibili(bool attivitaStatisticheAttive, bool pianoTurniInNavbar) => [
        if (attivitaStatisticheAttive) _TabId.attivita,
        if (attivitaStatisticheAttive) _TabId.statistiche,
        if (pianoTurniInNavbar) _TabId.pianoTurni,
        _TabId.tools,
        _TabId.impostazioni,
      ];

  Widget _schermata(_TabId id) {
    switch (id) {
      case _TabId.attivita:
        return const _AttivitaTab();
      case _TabId.statistiche:
        return const StatisticheScreen();
      case _TabId.pianoTurni:
        return const PianoTurniScreen();
      case _TabId.tools:
        return const ToolsScreen();
      case _TabId.impostazioni:
        return const ImpostazioniScreen();
    }
  }

  NavigationDestination _destinazione(_TabId id) {
    switch (id) {
      case _TabId.attivita:
        return const NavigationDestination(
            icon: Icon(Icons.calendar_today_outlined), selectedIcon: Icon(Icons.calendar_today), label: 'Attività');
      case _TabId.statistiche:
        return const NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'Statistiche');
      case _TabId.pianoTurni:
        // Stessa icona del catalogo Tools (utils/tools_config.dart), per
        // coerenza visiva col tool da cui questa voce si è spostata.
        return const NavigationDestination(
            icon: Icon(Icons.event_busy_outlined), selectedIcon: Icon(Icons.event_busy), label: 'Piano turni');
      case _TabId.tools:
        return const NavigationDestination(
            icon: Icon(Icons.handyman_outlined), selectedIcon: Icon(Icons.handyman), label: 'Tools');
      case _TabId.impostazioni:
        return const NavigationDestination(
            icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Impostazioni');
    }
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavigazioneProvider>();
    final tabs = _tabsVisibili(nav.attivitaStatisticheAttive, nav.pianoTurniInNavbar);
    // Se la tab selezionata è sparita (Attività/Statistiche disattivate o
    // Piano turni rimosso dalla navbar mentre una di queste era aperta) si
    // ripiega su Tools, senza toccare il campo: se la tab torna visibile più
    // tardi, la selezione originale torna a valere da sola.
    final selezionata = tabs.contains(_tabSelezionata) ? _tabSelezionata : _TabId.tools;
    final index = tabs.indexOf(selezionata);

    return Scaffold(
      body: IndexedStack(
        index: index,
        children: tabs.map(_schermata).toList(),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => _tabSelezionata = tabs[i]),
        destinations: tabs.map(_destinazione).toList(),
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

  /// Icona nell'AppBar (comune a Turni e Assistenze) che apre la nuova
  /// pagina Anagrafiche (Associazioni, Persone, Ospedali, Tipologie turno):
  /// spostata da Impostazioni perché di uso frequente proprio insieme a
  /// turni/assistenze (creazione al volo di una persona/ospedale nuovo).
  List<Widget> _azioniAnagrafiche() => [
        IconButton(
          icon: const Icon(Icons.groups_outlined),
          tooltip: 'Anagrafiche',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AnagraficheScreen()),
          ),
        ),
      ];

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
        TurniList(selettore: _selettore(), azioniExtra: _azioniAnagrafiche()),
        AssistenzeList(selettore: _selettore(), azioniExtra: _azioniAnagrafiche()),
      ],
    );
  }
}
