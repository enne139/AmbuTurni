import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../db/models.dart';
import '../../providers/app_provider.dart';
import '../../utils/format.dart';
import '../../utils/theme.dart';
import '../../widgets/calendario_mensile.dart';
import '../../widgets/turno_card.dart';
import 'turno_form.dart';
import 'turno_detail.dart';

// Preferenza persistente della vista scelta (lista/calendario): senza,
// l'utente che usa sempre il calendario dovrebbe riattivarlo a ogni avvio.
const _kVistaCalendarioKey = 'turni_vista_calendario';

/// Lista turni ordinata per data decrescente, con filtro per associazione.
/// Toggle in AppBar per la vista calendario mensile (CalendarioTurni).
/// L'eliminazione (swipe e long-press) è stata rimossa dalla lista su
/// richiesta esplicita: l'unico modo per eliminare un turno resta il
/// cestino nell'AppBar del dettaglio, per evitare cancellazioni accidentali
/// mentre si scorre o si tocca a lungo una card per sbaglio.
class TurniList extends StatefulWidget {
  /// Barra opzionale sotto l'AppBar: la tab unificata "Attività" ci mette il
  /// selettore Turni/Assistenze (v. app_navigator.dart), la lista non deve
  /// sapere altro.
  final PreferredSizeWidget? selettore;
  const TurniList({super.key, this.selettore});

  @override
  State<TurniList> createState() => _TurniListState();
}

class _TurniListState extends State<TurniList> {
  String? _filtroAssocId;
  bool _searching = false;
  bool _vistaCalendario = false;
  // Giorno selezionato nel calendario. Vive qui (non in CalendarioTurni)
  // perché serve anche al FAB per precompilare la data di un nuovo turno.
  DateTime _giornoSelezionato = DateTime.now();
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Carica i turni al primo avvio usando il provider.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TurniProvider>().carica();
    });
    // Ripristina la vista usata l'ultima volta.
    SharedPreferences.getInstance().then((prefs) {
      if (mounted && (prefs.getBool(_kVistaCalendarioKey) ?? false)) {
        setState(() => _vistaCalendario = true);
      }
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

  void _toggleVista() {
    // La ricerca testuale ha senso solo in lista: passando al calendario
    // viene chiusa (e il provider ricaricato senza filtro di testo), così i
    // pallini riflettono tutti i turni e non un sottoinsieme cercato.
    if (!_vistaCalendario && _searching) _chiudiRicerca();
    setState(() => _vistaCalendario = !_vistaCalendario);
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setBool(_kVistaCalendarioKey, _vistaCalendario));
  }

  Future<void> _apriDettaglio(String turnoId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => TurnoDetail(turnoId: turnoId)),
    );
    if (!mounted) return;
    context.read<TurniProvider>().ricarica();
    // Le statistiche (ore, conteggi) dipendono da turni e servizi: senza
    // questo refresh restavano quelle di prima anche dopo una modifica, dato
    // che la tab Statistiche resta montata nell'IndexedStack di AppNavigator.
    context.read<StatisticheProvider>().ricarica();
  }

  Future<void> _nuovoTurno() async {
    // Dal calendario il nuovo turno parte già dal giorno selezionato:
    // è quasi sempre il motivo per cui si sta guardando quel giorno.
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TurnoForm(
          dataIniziale: _vistaCalendario ? dateToIso(_giornoSelezionato) : null,
        ),
      ),
    );
    if (!mounted) return;
    context.read<TurniProvider>().ricarica();
    context.read<StatisticheProvider>().ricarica();
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
            // La ricerca testuale è disponibile solo in vista lista: in
            // calendario un risultato di ricerca sparso su più mesi non
            // avrebbe una rappresentazione utile.
            if (!_vistaCalendario)
              IconButton(
                icon: const Icon(Icons.search),
                tooltip: 'Cerca',
                onPressed: () => setState(() => _searching = true),
              ),
            IconButton(
              icon: Icon(_vistaCalendario ? Icons.view_list : Icons.calendar_month),
              tooltip: _vistaCalendario ? 'Vista elenco' : 'Vista calendario',
              onPressed: _toggleVista,
            ),
            // Filtro per associazione. L'icona prende il colore
            // dell'associazione filtrata: mostra a colpo d'occhio *quale*
            // filtro è attivo, non solo che ce n'è uno (kPrimary come
            // fallback per associazioni senza colore assegnato).
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
        bottom: widget.selettore,
      ),
      body: _vistaCalendario
          ? CalendarioMensile<Turno>(
              elementi: turni,
              dataIso: (t) => t.data,
              colore: (t) => colorFromHex(t.associazioneColore),
              etichettaConteggio: (n) => n == 1 ? '1 turno' : '$n turni',
              testoVuoto: 'Nessun turno in questo giorno',
              giornoSelezionato: _giornoSelezionato,
              onSelezionaGiorno: (g) => setState(() => _giornoSelezionato = g),
              itemBuilder: (ctx, t) => TurnoCard(
                turno: t,
                anag: anag,
                onTap: () => _apriDettaglio(t.id),
              ),
            )
          : turni.isEmpty
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
                    return TurnoCard(
                      turno: turno,
                      anag: anag,
                      onTap: () => _apriDettaglio(turno.id),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _nuovoTurno,
        child: const Icon(Icons.add),
      ),
    );
  }
}
