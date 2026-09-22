import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../db/models.dart';
import '../../providers/app_provider.dart';
import '../../utils/format.dart';
import '../../utils/theme.dart';
import '../../widgets/calendario_mensile.dart';
import 'assistenza_form.dart';
import 'assistenza_detail.dart';

// Preferenza persistente della vista scelta (lista/calendario), separata da
// quella dei turni: chi usa il calendario per i turni non è detto lo voglia
// anche per le assistenze.
const _kVistaCalendarioKey = 'assistenze_vista_calendario';

/// Lista assistenze, speculare a TurniList: filtro per associazione, ricerca
/// testuale (descrizione/note: le assistenze non hanno servizi) e vista
/// calendario mensile (CalendarioMensile condiviso coi turni).
/// L'eliminazione (swipe e long-press) è stata rimossa dalla lista, come
/// per TurniList: l'unico modo per eliminare un'assistenza resta il
/// cestino nell'AppBar del dettaglio, per evitare cancellazioni accidentali
/// mentre si scorre o si tocca a lungo una card per sbaglio.
class AssistenzeList extends StatefulWidget {
  /// Barra opzionale sotto l'AppBar: il selettore Turni/Assistenze della
  /// tab unificata (v. app_navigator.dart), come in TurniList.
  final PreferredSizeWidget? selettore;
  /// Azioni aggiuntive in coda a quelle dell'AppBar, come in TurniList
  /// (icona Anagrafiche iniettata da app_navigator.dart).
  final List<Widget> azioniExtra;
  const AssistenzeList({super.key, this.selettore, this.azioniExtra = const []});

  @override
  State<AssistenzeList> createState() => _AssistenzeListState();
}

class _AssistenzeListState extends State<AssistenzeList> {
  String? _filtroAssocId;
  bool _searching = false;
  bool _vistaCalendario = false;
  // Giorno selezionato nel calendario: vive qui (non nel calendario) perché
  // serve anche al FAB per precompilare la data di una nuova assistenza.
  DateTime _giornoSelezionato = DateTime.now();
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AssistenzeProvider>().carica();
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
      context
          .read<AssistenzeProvider>()
          .carica(associazioneId: _filtroAssocId, ricerca: v);
    });
  }

  void _chiudiRicerca() {
    _debounce?.cancel();
    setState(() {
      _searching = false;
      _searchCtrl.clear();
    });
    context.read<AssistenzeProvider>().carica(associazioneId: _filtroAssocId);
  }

  void _toggleVista() {
    // Come in TurniList: la ricerca testuale ha senso solo in lista, passando
    // al calendario viene chiusa così i pallini riflettono tutte le assistenze.
    if (!_vistaCalendario && _searching) _chiudiRicerca();
    setState(() => _vistaCalendario = !_vistaCalendario);
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setBool(_kVistaCalendarioKey, _vistaCalendario));
  }

  Future<void> _apriDettaglio(String assistenzaId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AssistenzaDetail(assistenzaId: assistenzaId)),
    );
    if (!mounted) return;
    context.read<AssistenzeProvider>().ricarica();
    // Le statistiche (ore, conteggi) dipendono anche dalle assistenze: senza
    // questo refresh restavano quelle di prima anche dopo una modifica, dato
    // che la tab Statistiche resta montata nell'IndexedStack di AppNavigator.
    context.read<StatisticheProvider>().ricarica();
    // Stesso motivo per i contatori d'uso di persone/tipologie in Anagrafiche.
    context.read<AnagraficheProvider>().ricaricaConteggi();
  }

  Future<void> _nuovaAssistenza() async {
    // Dal calendario la nuova assistenza parte già dal giorno selezionato.
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AssistenzaForm(
          dataIniziale: _vistaCalendario ? dateToIso(_giornoSelezionato) : null,
        ),
      ),
    );
    if (!mounted) return;
    context.read<AssistenzeProvider>().ricarica();
    context.read<StatisticheProvider>().ricarica();
    context.read<AnagraficheProvider>().ricaricaConteggi();
  }

  @override
  Widget build(BuildContext context) {
    final anag = context.watch<AnagraficheProvider>();
    final provider = context.watch<AssistenzeProvider>();
    final assistenze = provider.assistenze;

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: TextStyle(color: coloreTesto(context)),
                decoration: InputDecoration(
                  hintText: 'Cerca in descrizione e note...',
                  hintStyle: TextStyle(color: coloreTesto(context, 0.38)),
                  border: InputBorder.none,
                ),
                onChanged: _onSearchChanged,
              )
            : const Text('Assistenze'),
        actions: [
          if (_searching)
            IconButton(icon: const Icon(Icons.close), tooltip: 'Chiudi ricerca', onPressed: _chiudiRicerca)
          else ...[
            // Ricerca solo in vista lista, come per i turni: a calendario un
            // risultato sparso su più mesi non ha una rappresentazione utile.
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
            // Icona col colore dell'associazione filtrata (v. TurniList):
            // mostra *quale* filtro è attivo, non solo che ce n'è uno.
            if (anag.associazioni.isNotEmpty)
              PopupMenuButton<String?>(
                icon: Icon(
                  Icons.filter_list,
                  color: _filtroAssocId == null
                      ? coloreTesto(context, 0.7)
                      : colorFromHex(anag.byIdAssociazione(_filtroAssocId)?.colore) ?? kPrimary,
                ),
                tooltip: 'Filtra per associazione',
                onSelected: (val) {
                  setState(() => _filtroAssocId = val);
                  context.read<AssistenzeProvider>().carica(
                      associazioneId: val,
                      ricerca: _searching ? _searchCtrl.text : null);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: null, child: Text('Tutti')),
                  ...anag.associazioni.map((a) => PopupMenuItem(value: a.id, child: Text(a.nome))),
                ],
              ),
          ],
          ...widget.azioniExtra,
        ],
        bottom: widget.selettore,
      ),
      body: _vistaCalendario
          ? CalendarioMensile<Assistenza>(
              elementi: assistenze,
              dataIso: (a) => a.data,
              colore: (a) => colorFromHex(a.associazioneColore),
              etichettaConteggio: (n) =>
                  n == 1 ? '1 assistenza' : '$n assistenze',
              testoVuoto: 'Nessuna assistenza in questo giorno',
              giornoSelezionato: _giornoSelezionato,
              onSelezionaGiorno: (g) => setState(() => _giornoSelezionato = g),
              itemBuilder: (ctx, a) => _AssistenzaCard(
                assistenza: a,
                onTap: () => _apriDettaglio(a.id),
              ),
            )
          : assistenze.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.local_hospital_outlined, size: 64, color: coloreTesto(context, 0.24)),
                      const SizedBox(height: 16),
                      Text(
                        (provider.ricerca?.isNotEmpty ?? false) ? 'Nessun risultato' : 'Nessuna assistenza',
                        style: TextStyle(color: coloreTesto(context, 0.54)),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        (provider.ricerca?.isNotEmpty ?? false)
                            ? 'Prova con un altro termine di ricerca'
                            : 'Tocca + per aggiungerne una',
                        style: TextStyle(color: coloreTesto(context, 0.38), fontSize: 13),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                  itemCount: assistenze.length,
                  itemBuilder: (ctx, i) {
                    final a = assistenze[i];
                    return _AssistenzaCard(
                      assistenza: a,
                      onTap: () => _apriDettaglio(a.id),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _nuovaAssistenza,
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// Card di un'assistenza, condivisa tra la lista e la vista calendario
/// (estratta dall'itemBuilder inline quando è arrivato il calendario).
class _AssistenzaCard extends StatelessWidget {
  final Assistenza assistenza;
  final VoidCallback onTap;
  const _AssistenzaCard({required this.assistenza, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final a = assistenza;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kPrimary.withValues(alpha: 0.4)),
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
                  Text(a.associazioneNome!, style: TextStyle(color: coloreTesto(context, 0.54), fontSize: 12)),
              ]),
            ),
            Text(formatOre(a.ore), style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}
