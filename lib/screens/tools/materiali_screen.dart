import 'package:flutter/material.dart';
import '../../db/helpers.dart';
import '../../db/models.dart';
import '../../utils/theme.dart';

/// Gestione del catalogo materiali (rinomina/elimina). La creazione avviene
/// anche al volo dal MaterialePicker ("Aggiungi...") nel form di utilizzo;
/// questa schermata serve a correggere un nome sbagliato o eliminare un
/// materiale non più usato.
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

  Future<void> _rinomina(Materiale m) async {
    final ctrl = TextEditingController(text: m.nome);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rinomina materiale'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Nome'),
          textCapitalization: TextCapitalization.sentences,
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salva')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final nome = ctrl.text.trim();
    if (nome.isEmpty) return;
    await saveMateriale(nome, id: m.id);
    if (mounted) _carica();
  }

  Future<void> _elimina(Materiale m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina materiale'),
        content: Text('Eliminare "${m.nome}" dal catalogo?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Elimina', style: TextStyle(color: kPrimary))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await deleteMateriale(m.id);
      if (mounted) _carica();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossibile eliminare: il materiale è usato in almeno un utilizzo registrato')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Catalogo materiali')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _materiali.isEmpty
              ? const Center(
                  child: Text('Nessun materiale nel catalogo', style: TextStyle(color: Colors.white54)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
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
