import 'package:flutter/material.dart';
import '../../utils/theme.dart';
import 'magazzino_screen.dart';
import 'materiali_usati_screen.dart';
import 'piano_turni_screen.dart';

/// Elenco degli strumenti extra dell'app (fuori dal flusso turni/assistenze).
/// Pensata per ospitare più strumenti senza ridisegnare la navigazione principale.
class ToolsScreen extends StatelessWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tools')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.inventory_2_outlined, color: kPrimary),
              title: const Text('Materiali usati'),
              subtitle: const Text('Segna i materiali usati da ripristinare'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MaterialiUsatiScreen()),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.event_busy_outlined, color: kPrimary),
              title: const Text('Piano turni'),
              subtitle: const Text('Equipaggi e buchi dal foglio Google dei turni'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PianoTurniScreen()),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.warehouse_outlined, color: kPrimary),
              title: const Text('Magazzino Verde'),
              subtitle: const Text('Giacenze e movimenti dal gestionale di magazzino'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MagazzinoScreen()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
