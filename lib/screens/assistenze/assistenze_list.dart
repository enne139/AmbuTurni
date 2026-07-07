import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/app_provider.dart';
import '../../utils/format.dart';
import '../../utils/theme.dart';
import 'assistenza_form.dart';
import 'assistenza_detail.dart';

/// Lista assistenze, speculare a TurniList ma senza tipologia né servizi.
/// L'eliminazione (swipe e long-press) è stata rimossa dalla lista, come
/// per TurniList: l'unico modo per eliminare un'assistenza resta il
/// cestino nell'AppBar del dettaglio, per evitare cancellazioni accidentali
/// mentre si scorre o si tocca a lungo una card per sbaglio.
class AssistenzeList extends StatefulWidget {
  /// Barra opzionale sotto l'AppBar: il selettore Turni/Assistenze della
  /// tab unificata (v. app_navigator.dart), come in TurniList.
  final PreferredSizeWidget? selettore;
  const AssistenzeList({super.key, this.selettore});

  @override
  State<AssistenzeList> createState() => _AssistenzeListState();
}

class _AssistenzeListState extends State<AssistenzeList> {
  String? _filtroAssocId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AssistenzeProvider>().carica();
    });
  }

  @override
  Widget build(BuildContext context) {
    final anag = context.watch<AnagraficheProvider>();
    final assistenze = context.watch<AssistenzeProvider>().assistenze;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Assistenze'),
        actions: [
          // Icona col colore dell'associazione filtrata (v. TurniList):
          // mostra *quale* filtro è attivo, non solo che ce n'è uno.
          if (anag.associazioni.isNotEmpty)
            PopupMenuButton<String?>(
              icon: Icon(
                Icons.filter_list,
                color: _filtroAssocId == null
                    ? Colors.white70
                    : colorFromHex(anag.byIdAssociazione(_filtroAssocId)?.colore) ?? kPrimary,
              ),
              tooltip: 'Filtra per associazione',
              onSelected: (val) {
                setState(() => _filtroAssocId = val);
                context.read<AssistenzeProvider>().carica(associazioneId: val);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: null, child: Text('Tutti')),
                ...anag.associazioni.map((a) => PopupMenuItem(value: a.id, child: Text(a.nome))),
              ],
            ),
        ],
        bottom: widget.selettore,
      ),
      body: assistenze.isEmpty
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.local_hospital_outlined, size: 64, color: Colors.white24),
                  SizedBox(height: 16),
                  Text('Nessuna assistenza', style: TextStyle(color: Colors.white54)),
                  SizedBox(height: 8),
                  Text('Tocca + per aggiungerne una', style: TextStyle(color: Colors.white38, fontSize: 13)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
              itemCount: assistenze.length,
              itemBuilder: (ctx, i) {
                final a = assistenze[i];
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: InkWell(
                    onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (_) => AssistenzaDetail(assistenzaId: a.id)));
                      if (mounted) context.read<AssistenzeProvider>().ricarica();
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: kPrimary.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: kPrimary.withOpacity(0.4)),
                          ),
                          alignment: Alignment.center,
                          child: Text('#${a.numeroProgressivo ?? '—'}',
                              style: const TextStyle(color: kPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(formatDate(a.data), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                            if (a.associazioneNome != null)
                              Text(a.associazioneNome!, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                          ]),
                        ),
                        Text(formatOre(a.ore), style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const AssistenzaForm()));
          if (mounted) context.read<AssistenzeProvider>().ricarica();
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
