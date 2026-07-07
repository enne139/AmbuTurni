import 'package:flutter/material.dart';
import '../../db/helpers.dart';
import '../../db/models.dart';
import '../../utils/theme.dart';

/// Gestione del catalogo materiali (aggiungi/rinomina/elimina). La creazione
/// avviene anche al volo dal MaterialePicker ("Aggiungi...") nel form di
/// utilizzo; il FAB qui permette di popolare il catalogo in anticipo senza
/// passare dalla registrazione di un utilizzo.
class MaterialiScreen extends StatefulWidget {
  const MaterialiScreen({super.key});

  @override
  State<MaterialiScreen> createState() => _MaterialiScreenState();
}

class _MaterialiScreenState extends State<MaterialiScreen> {
  List<Materiale> _materiali = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _carica();
  }

  Future<void> _carica() async {
    final materiali = await getMateriali();
    if (mounted) setState(() { _materiali = materiali; _loading = false; });
  }

  /// Dialog condiviso da aggiungi/rinomina: chiede un nome e lo restituisce
  /// già ripulito, null se l'utente annulla o lascia vuoto.
  Future<String?> _chiediNome(String titolo, {String iniziale = ''}) async {
    final ctrl = TextEditingController(text: iniziale);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titolo),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Nome'),
          textCapitalization: TextCapitalization.sentences,
          autofocus: true,
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salva')),
        ],
      ),
    );
    final nome = ctrl.text.trim();
    return (ok == true && nome.isNotEmpty) ? nome : null;
  }

  /// True se [nome] esiste già nel catalogo (case-insensitive, come il
  /// MaterialePicker: la tabella non ha UNIQUE sul nome e "Garze"/"garze"
  /// diventerebbero due voci). [eccettoId] esclude il materiale che si sta
  /// rinominando, altrimenti risulterebbe doppione di sé stesso.
  bool _nomeDoppio(String nome, {String? eccettoId}) => _materiali.any(
      (m) => m.id != eccettoId && m.nome.toLowerCase() == nome.toLowerCase());

  void _avvisaDoppione(String nome) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$nome" è già nel catalogo')));
  }

  Future<void> _aggiungi() async {
    final nome = await _chiediNome('Nuovo materiale');
    if (nome == null || !mounted) return;
    if (_nomeDoppio(nome)) {
      _avvisaDoppione(nome);
      return;
    }
    await saveMateriale(nome);
    if (mounted) _carica();
  }

  Future<void> _rinomina(Materiale m) async {
    final nome = await _chiediNome('Rinomina materiale', iniziale: m.nome);
    if (nome == null || !mounted) return;
    if (_nomeDoppio(nome, eccettoId: m.id)) {
      _avvisaDoppione(nome);
      return;
    }
    await saveMateriale(nome, id: m.id);
    if (mounted) _carica();
  }

  Future<void> _elimina(Materiale m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina materiale'),
        content: Text('Eliminare "${m.nome}" dal catalogo? Vengono eliminati anche gli eventuali utilizzi registrati per questo materiale.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Elimina', style: TextStyle(color: kPrimary))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await deleteMateriale(m.id);
    if (mounted) _carica();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Catalogo materiali')),
      floatingActionButton: FloatingActionButton(
        onPressed: _aggiungi,
        tooltip: 'Nuovo materiale',
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _materiali.isEmpty
              ? const Center(
                  child: Text('Nessun materiale nel catalogo', style: TextStyle(color: Colors.white54)),
                )
              : ListView.builder(
                  // Padding in fondo per non lasciare l'ultima card coperta dal FAB.
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                  itemCount: _materiali.length,
                  itemBuilder: (ctx, i) {
                    final m = _materiali[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        title: Text(m.nome),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 20),
                            tooltip: 'Rinomina',
                            onPressed: () => _rinomina(m),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 20),
                            tooltip: 'Elimina',
                            onPressed: () => _elimina(m),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
    );
  }
}
