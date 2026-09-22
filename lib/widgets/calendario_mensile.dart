import 'package:flutter/material.dart';
import '../utils/format.dart';
import '../utils/theme.dart';

/// Vista calendario mensile generica, alternativa alla lista (toggle in
/// AppBar): griglia del mese con un pallino per elemento (colore a scelta
/// del chiamante, tipicamente quello dell'associazione) e, sotto, gli
/// elementi del giorno selezionato. Nata come CalendarioTurni e resa
/// generica quando la vista è stata estesa alle assistenze: `Turno` e
/// `Assistenza` sono classi diverse e duplicare ~250 righe di griglia era
/// peggio di tre callback.
///
/// Griglia custom invece di un package (es. table_calendar): serve solo una
/// vista mese con marker, e il progetto tiene deliberatamente il pubspec
/// minimo (stessa ragione per cui byId* evita il package collection).
///
/// Il giorno selezionato è stato del padre (la lista), non locale: serve
/// anche al FAB per precompilare la data quando si crea un elemento dal
/// calendario. Il mese visualizzato invece è solo di questa vista.
class CalendarioMensile<T> extends StatefulWidget {
  final List<T> elementi;
  /// Data ISO (YYYY-MM-DD) dell'elemento, per il raggruppamento nei giorni.
  final String Function(T) dataIso;
  /// Colore del pallino dell'elemento (null → kPrimary).
  final Color? Function(T) colore;
  /// Card dell'elemento nella lista del giorno selezionato (incluso onTap).
  final Widget Function(BuildContext, T) itemBuilder;
  /// Etichetta del conteggio del giorno (es. "1 turno" / "3 turni").
  final String Function(int) etichettaConteggio;
  /// Testo mostrato quando il giorno selezionato non ha elementi.
  final String testoVuoto;
  final DateTime giornoSelezionato;
  final ValueChanged<DateTime> onSelezionaGiorno;

  const CalendarioMensile({
    super.key,
    required this.elementi,
    required this.dataIso,
    required this.colore,
    required this.itemBuilder,
    required this.etichettaConteggio,
    required this.testoVuoto,
    required this.giornoSelezionato,
    required this.onSelezionaGiorno,
  });

  @override
  State<CalendarioMensile<T>> createState() => _CalendarioMensileState<T>();
}

class _CalendarioMensileState<T> extends State<CalendarioMensile<T>> {
  // Primo giorno del mese visualizzato (giorno sempre 1: il resto della
  // griglia si ricava da qui).
  late DateTime _mese;
  // Elementi raggruppati per data ISO, memoizzato: ricalcolato solo quando
  // widget.elementi cambia (nuova lista dal provider), non a ogni build —
  // altrimenti anche un semplice tap su un giorno diverso (stessa lista)
  // riscandirebbe l'intero storico di turni/assistenze.
  late Map<String, List<T>> _perGiorno;

  @override
  void initState() {
    super.initState();
    _mese = DateTime(widget.giornoSelezionato.year, widget.giornoSelezionato.month, 1);
    _perGiorno = _raggruppaPerGiorno(widget.elementi);
  }

  @override
  void didUpdateWidget(covariant CalendarioMensile<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.elementi != widget.elementi) {
      _perGiorno = _raggruppaPerGiorno(widget.elementi);
    }
    // Se il giorno selezionato cambia di mese da fuori (es. un futuro "salta
    // al giorno" mentre il calendario resta a schermo, come già avviene nel
    // Piano turni) il mese mostrato deve seguirlo: senza, la griglia
    // resterebbe sul vecchio mese mentre la lista sotto mostra già il nuovo
    // giorno selezionato.
    if (oldWidget.giornoSelezionato.year != widget.giornoSelezionato.year ||
        oldWidget.giornoSelezionato.month != widget.giornoSelezionato.month) {
      _mese = DateTime(widget.giornoSelezionato.year, widget.giornoSelezionato.month, 1);
    }
  }

  /// Raggruppa gli elementi per data ISO. substring difensivo: i dati normali
  /// sono già YYYY-MM-DD, ma un backup legacy importato male potrebbe avere
  /// un datetime completo — meglio un raggruppamento corretto che un buco.
  Map<String, List<T>> _raggruppaPerGiorno(List<T> elementi) {
    final perGiorno = <String, List<T>>{};
    for (final e in elementi) {
      final data = widget.dataIso(e);
      final chiave = data.length > 10 ? data.substring(0, 10) : data;
      perGiorno.putIfAbsent(chiave, () => []).add(e);
    }
    return perGiorno;
  }

  void _cambiaMese(int delta) {
    // Il costruttore DateTime normalizza i mesi fuori range (0 → dicembre
    // dell'anno prima, 13 → gennaio dell'anno dopo): niente aritmetica manuale.
    setState(() => _mese = DateTime(_mese.year, _mese.month + delta, 1));
  }

  void _vaiAOggi() {
    final oggi = DateTime.now();
    setState(() => _mese = DateTime(oggi.year, oggi.month, 1));
    widget.onSelezionaGiorno(DateTime(oggi.year, oggi.month, oggi.day));
  }

  @override
  Widget build(BuildContext context) {
    final selIso = dateToIso(widget.giornoSelezionato);
    final delGiorno = _perGiorno[selIso] ?? const [];

    return Column(
      children: [
        _intestazioneMese(),
        _rigaGiorniSettimana(),
        _griglia(_perGiorno, selIso),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text(
                formatDate(selIso),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              const SizedBox(width: 8),
              Text(
                widget.etichettaConteggio(delGiorno.length),
                style: TextStyle(color: coloreTesto(context, 0.54), fontSize: 13),
              ),
            ],
          ),
        ),
        Expanded(
          child: delGiorno.isEmpty
              ? Center(
                  child: Text(
                    widget.testoVuoto,
                    style: TextStyle(color: coloreTesto(context, 0.38), fontSize: 13),
                  ),
                )
              : ListView.builder(
                  // Padding basso abbondante per non finire sotto il FAB.
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                  itemCount: delGiorno.length,
                  itemBuilder: (ctx, i) => widget.itemBuilder(ctx, delGiorno[i]),
                ),
        ),
      ],
    );
  }

  Widget _intestazioneMese() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${kMesiItaliani[_mese.month - 1]} ${_mese.year}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
          ),
          TextButton(
            onPressed: _vaiAOggi,
            child: const Text('Oggi'),
          ),
          IconButton(
            icon: Icon(Icons.chevron_left, color: coloreTesto(context, 0.7)),
            tooltip: 'Mese precedente',
            onPressed: () => _cambiaMese(-1),
          ),
          IconButton(
            icon: Icon(Icons.chevron_right, color: coloreTesto(context, 0.7)),
            tooltip: 'Mese successivo',
            onPressed: () => _cambiaMese(1),
          ),
        ],
      ),
    );
  }

  Widget _rigaGiorniSettimana() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          for (final g in kGiorniSettimanaIt)
            Expanded(
              child: Center(
                child: Text(
                  g,
                  style: TextStyle(color: coloreTesto(context, 0.38), fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _griglia(Map<String, List<T>> perGiorno, String selIso) {
    // La griglia parte dal lunedì (weekday 1): offset = celle vuote prima
    // del giorno 1. DateTime(anno, mese+1, 0) = ultimo giorno del mese.
    final offset = _mese.weekday - 1;
    final giorniNelMese = DateTime(_mese.year, _mese.month + 1, 0).day;
    final settimane = ((offset + giorniNelMese) / 7).ceil();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          for (int s = 0; s < settimane; s++)
            Row(
              children: [
                for (int g = 0; g < 7; g++)
                  _cella(s * 7 + g - offset + 1, giorniNelMese, perGiorno, selIso),
              ],
            ),
        ],
      ),
    );
  }

  /// Cella di un giorno. [numero] può uscire da [1..giorniNelMese]: in quel
  /// caso è un giorno del mese adiacente, mostrato attenuato e non tappabile
  /// (il costruttore DateTime lo normalizza alla data reale per il numero).
  Widget _cella(int numero, int giorniNelMese, Map<String, List<T>> perGiorno, String selIso) {
    final giorno = DateTime(_mese.year, _mese.month, numero);
    final nelMese = numero >= 1 && numero <= giorniNelMese;
    final iso = dateToIso(giorno);
    final List<T> delGiorno = nelMese ? (perGiorno[iso] ?? const []) : const [];
    final selezionato = nelMese && iso == selIso;
    final oggi = iso == todayIso();

    return Expanded(
      child: InkWell(
        onTap: nelMese ? () => widget.onSelezionaGiorno(giorno) : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 48,
          margin: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            color: selezionato ? kPrimary.withValues(alpha: 0.18) : null,
            borderRadius: BorderRadius.circular(8),
            border: selezionato
                ? Border.all(color: kPrimary)
                // Bordo tenue su "oggi" per ritrovarlo a colpo d'occhio
                // anche quando è selezionato un altro giorno.
                : (oggi ? Border.all(color: coloreTesto(context, 0.24)) : null),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${giorno.day}',
                style: TextStyle(
                  fontSize: 13,
                  color: !nelMese
                      ? coloreTesto(context, 0.24)
                      : (oggi ? kPrimary : coloreTesto(context)),
                  fontWeight: selezionato || oggi ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              // Altezza fissa anche senza pallini: evita che i numeri dei
              // giorni "ballino" tra celle con e senza elementi.
              SizedBox(
                height: 8,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final e in delGiorno.take(4))
                      Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: widget.colore(e) ?? kPrimary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
