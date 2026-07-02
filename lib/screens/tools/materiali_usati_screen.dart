import 'package:flutter/material.dart';
import '../../db/helpers.dart';
import '../../db/models.dart';
import '../../utils/theme.dart';
import 'materiale_usato_form.dart';
import 'materiali_screen.dart';

/// Lista dei materiali usati non ancora ripristinati. Il tocco sul check
/// segna la riga come ripristinata (sparisce dalla lista, resta in storico
/// nel DB); lo swipe la elimina del tutto (es. inserimento per errore).
class MaterialiUsatiScreen extends StatefulWidget {
  const MaterialiUsatiScreen({super.key});

  @override
  State<MaterialiUsatiScreen> createState() => _MaterialiUsatiScreenState();
}

class _MaterialiUsatiScreenState extends State<MaterialiUsatiScreen> {
  List<MaterialeUsato> _lista = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _carica();
  }

  Future<void> _carica() async {
    final lista = await getMaterialiUsati();
    if (mounted) setState(() { _lista = lista; _loading = false; });
  }

  Future<void> _ripristina(MaterialeUsato mu) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Segna come ripristinato'),
        content: Text('"${mu.materialeNome ?? '—'}" (${mu.quantitaLabel}) è stato ripristinato?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sì, ripristinato')),
        ],
      ),
    );
    if (ok == true && mounted) {
      await segnaMaterialeRipristinato(mu.id);
      if (mounted) _carica();
    }
  }

  Future<void> _ripristinaTutto() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ripristina tutto'),
        content: Text('Segnare come ripristinati tutti i ${_lista.length} materiali in lista?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sì, ripristina tutto')),
        ],
      ),
    );
    if (ok == true && mounted) {
      await segnaTuttiMaterialiRipristinati();
      if (mounted) _carica();
    }
  }

  /// Variazione rapida della quantità (+/- in lista): aggiorna prima lo stato
  /// locale per una risposta immediata, poi persiste sul DB in background.
  Future<void> _variaQuantita(MaterialeUsato mu, int delta) async {
    final nuova = mu.quantita + delta;
    if (nuova < 1) return;
    final idx = _lista.indexWhere((m) => m.id == mu.id);
    if (idx == -1) return;
    setState(() => _lista[idx] = mu.copyWith(quantita: nuova));
    await aggiornaQuantitaMaterialeUsato(mu.id, nuova);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Materiali usati'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_note),
            tooltip: 'Gestisci materiali',
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const MaterialiScreen()));
              if (mounted) _carica();
            },
          ),
          if (_lista.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.done_all),
              tooltip: 'Ripristina tutto',
              onPressed: _ripristinaTutto,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _lista.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 64, color: Colors.white24),
                      SizedBox(height: 16),
                      Text('Nessun materiale da ripristinare', style: TextStyle(color: Colors.white54)),
                      SizedBox(height: 8),
                      Text('Tocca + per segnarne uno usato', style: TextStyle(color: Colors.white38, fontSize: 13)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                  itemCount: _lista.length,
                  itemBuilder: (ctx, i) {
                    final mu = _lista[i];
                    return Dismissible(
                      key: ValueKey(mu.id),
                      direction: DismissDirection.endToStart,
                      confirmDismiss: (_) => showDialog<bool>(
                        context: context,
                        builder: (dctx) => AlertDialog(
                          title: const Text('Elimina riga'),
                          content: Text('Eliminare "${mu.materialeNome ?? '—'}" (${mu.quantitaLabel})?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Annulla')),
                            TextButton(
                              onPressed: () => Navigator.pop(dctx, true),
                              child: const Text('Elimina', style: TextStyle(color: kPrimary)),
                            ),
                          ],
                        ),
                      ),
                      onDismissed: (_) async {
                        await deleteMaterialeUsato(mu.id);
                        if (mounted) _carica();
                      },
                      background: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        decoration: BoxDecoration(
                          color: kPrimary.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      child: Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          child: Row(children: [
                            // Stepper +/- con la quantità in evidenza al centro: stesso
                            // stile del badge "#numero" usato nelle card di turni/assistenze,
                            // ma qui interattivo per un ritocco rapido durante il turno.
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline, size: 20),
                              color: Colors.white38,
                              visualDensity: VisualDensity.compact,
                              onPressed: mu.quantita > 1 ? () => _variaQuantita(mu, -1) : null,
                            ),
                            Container(
                              constraints: const BoxConstraints(minWidth: 48),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                              decoration: BoxDecoration(
                                color: kPrimary.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: kPrimary.withOpacity(0.4)),
                              ),
                              alignment: Alignment.center,
                              child: Text(mu.quantitaLabel,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: kPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline, size: 20),
                              color: Colors.white38,
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _variaQuantita(mu, 1),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(mu.materialeNome ?? '—', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                                if (mu.posizione != null || mu.note != null)
                                  Text(
                                    [if (mu.posizione != null) mu.posizione!, if (mu.note != null) mu.note!].join(' · '),
                                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                                  ),
                              ]),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 20),
                              color: Colors.white38,
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Modifica',
                              onPressed: () async {
                                await Navigator.push(context, MaterialPageRoute(builder: (_) => MaterialeUsatoForm(esistente: mu)));
                                if (mounted) _carica();
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.check_circle_outline),
                              color: Colors.white38,
                              tooltip: 'Segna come ripristinato',
                              onPressed: () => _ripristina(mu),
                            ),
                          ]),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const MaterialeUsatoForm()));
          if (mounted) _carica();
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
