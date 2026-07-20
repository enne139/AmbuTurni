import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../../utils/theme.dart';
import '../../utils/tools_config.dart';
import 'lista_ospedali_screen.dart';
import 'magazzino_screen.dart';
import 'materiali_usati_screen.dart';
import 'piano_turni_screen.dart';

// Schermata di destinazione per ogni tool del catalogo (utils/tools_config.dart).
// Mappa separata dai metadati: questi widget non servono a Impostazioni,
// che mostra solo gli switch.
final Map<String, WidgetBuilder> _destinazioni = {
  kToolMaterialiUsati: (_) => const MaterialiUsatiScreen(),
  kToolPianoTurni: (_) => const PianoTurniScreen(),
  kToolMagazzino: (_) => const MagazzinoScreen(),
  kToolListaOspedali: (_) => const ListaOspedaliScreen(),
};

/// Elenco degli strumenti extra dell'app (fuori dal flusso turni/assistenze).
/// Mostra solo i tool attivati da Impostazioni → Tools attivi (ToolsProvider):
/// pensata per ospitare più strumenti senza ridisegnare la navigazione
/// principale, senza però ingombrare la lista con quelli che non si usano.
/// Piano turni sparisce da qui se spostato in navbar (Impostazioni →
/// Navigazione, NavigazioneProvider.pianoTurniInNavbar): sarebbe un accesso
/// duplicato alla stessa schermata.
class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final tools = context.watch<ToolsProvider>();
    final pianoTurniInNavbar = context.watch<NavigazioneProvider>().pianoTurniInNavbar;
    if (!tools.caricato) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final attivi = kToolsDisponibili
        .where((t) => tools.attivo(t.id))
        .where((t) => !(t.id == kToolPianoTurni && pianoTurniInNavbar))
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Tools')),
      body: attivi.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Nessun tool attivo: abilitali da Impostazioni → Tools attivi.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: attivi.map((t) => Card(
                child: ListTile(
                  leading: Icon(t.icon, color: kPrimary),
                  title: Text(t.titolo),
                  subtitle: Text(t.sottotitolo),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: _destinazioni[t.id]!),
                  ),
                ),
              )).toList(),
            ),
    );
  }
}
