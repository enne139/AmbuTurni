import 'package:flutter/material.dart';
import '../../utils/theme.dart';
import 'materiali_usati_screen.dart';

/// Elenco degli strumenti extra dell'app (fuori dal flusso turni/assistenze).
/// Per ora contiene solo "Materiali usati"; pensata per ospitarne altri in
/// futuro senza dover ridisegnare la navigazione principale.
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
        ],
      ),
    );
  }
}
