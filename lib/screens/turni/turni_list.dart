import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../db/helpers.dart';
import '../../db/models.dart';
import '../../providers/app_provider.dart';
import '../../utils/format.dart';
import '../../utils/theme.dart';
import '../../widgets/turno_card.dart';
import 'turno_form.dart';
import 'turno_detail.dart';

/// Lista turni ordinata per data decrescente, con filtro per associazione e
/// long-press per eliminare (con conferma).
class TurniList extends StatefulWidget {
  const TurniList({super.key});

  @override
  State<TurniList> createState() => _TurniListState();
}

class _TurniListState extends State<TurniList> {
  String? _filtroAssocId;
  bool _searching = false;
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Carica i turni al primo avvio usando il provider.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TurniProvider>().carica();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  // Debounce per non lanciare una query a ogni singolo tasto premuto.
  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      context.read<TurniProvider>().carica(associazioneId: _filtroAssocId, ricerca: v);
    });
  }

  void _chiudiRicerca() {
    _debounce?.cancel();
    setState(() {
      _searching = false;
      _searchCtrl.clear();
    });
    context.read<TurniProvider>().carica(associazioneId: _filtroAssocId);
  }

  Future<void> _elimina(Turno turno) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Elimina turno'),
        content: Text('Eliminare il turno del ${formatDate(turno.data)}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annulla')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Elimina', style: TextStyle(color: kPrimary)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await deleteTurno(turno.id);
      if (mounted) context.read<TurniProvider>().ricarica();
    }
  }

  @override
  Widget build(BuildContext context) {
    final anag = context.watch<AnagraficheProvider>();
    final turniProvider = context.watch<TurniProvider>();
    final turni = turniProvider.turni;

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Cerca in descrizione, note, servizi...',
                  hintStyle: TextStyle(color: Colors.white38),
                  border: InputBorder.none,
                ),
                onChanged: _onSearchChanged,
              )
            : const Text('Turni'),
        actions: [
          if (_searching)
            IconButton(icon: const Icon(Icons.close), tooltip: 'Chiudi ricerca', onPressed: _chiudiRicerca)
          else ...[
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: 'Cerca',
              onPressed: () => setState(() => _searching = true),
            ),
            // Filtro per associazione
            if (anag.associazioni.isNotEmpty)
              PopupMenuButton<String?>(
                icon: Icon(
                  Icons.filter_list,
                  color: _filtroAssocId != null ? kPrimary : Colors.white70,
                ),
                tooltip: 'Filtra per associazione',
                onSelected: (val) {
                  setState(() => _filtroAssocId = val);
                  context.read<TurniProvider>().carica(associazioneId: val);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: null, child: Text('Tutti')),
                  ...anag.associazioni.map(
                    (a) => PopupMenuItem(value: a.id, child: Text(a.nome)),
                  ),
                ],
              ),
          ],
        ],
      ),
      body: turni.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_today_outlined, size: 64, color: Colors.white24),
                  const SizedBox(height: 16),
                  Text(
                    (turniProvider.ricerca?.isNotEmpty ?? false) ? 'Nessun risultato' : 'Nessun turno',
                    style: const TextStyle(color: Colors.white54),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    (turniProvider.ricerca?.isNotEmpty ?? false)
                        ? 'Prova con un altro termine di ricerca'
                        : 'Tocca + per aggiungerne uno',
                    style: const TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
              itemCount: turni.length,
              itemBuilder: (ctx, i) {
                final turno = turni[i];
                return Dismissible(
                  key: ValueKey(turno.id),
                  direction: DismissDirection.endToStart,
                  // Conferma prima di rimuovere: se l'utente annulla, l'item torna indietro.
                  confirmDismiss: (_) => showDialog<bool>(
                    context: context,
                    builder: (dctx) => AlertDialog(
                      title: const Text('Elimina turno'),
                      content: Text('Eliminare il turno del ${formatDate(turno.data)}?'),
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
                    await deleteTurno(turno.id);
                    if (mounted) context.read<TurniProvider>().ricarica();
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
                  child: TurnoCard(
                    turno: turno,
                    anag: anag,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => TurnoDetail(turnoId: turno.id)),
                      );
                      if (mounted) context.read<TurniProvider>().ricarica();
                    },
                    onLongPress: () => _elimina(turno),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => const TurnoForm()));
          if (mounted) context.read<TurniProvider>().ricarica();
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
