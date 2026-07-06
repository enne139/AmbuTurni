import 'package:flutter/material.dart';
import '../../db/models.dart';
import '../../providers/app_provider.dart';
import '../../utils/format.dart';
import '../../utils/theme.dart';
import '../../widgets/turno_card.dart';

// Nomi di mesi e giorni hardcoded in italiano: l'app non usa
// flutter_localizations (tutte le stringhe sono già italiane fisse) e
// DateFormat con locale 'it' richiederebbe initializeDateFormatting all'avvio
// — una dipendenza di setup in più per due liste di costanti.
const _mesi = [
  'Gennaio', 'Febbraio', 'Marzo', 'Aprile', 'Maggio', 'Giugno',
  'Luglio', 'Agosto', 'Settembre', 'Ottobre', 'Novembre', 'Dicembre',
];
const _giorniSettimana = ['Lun', 'Mar', 'Mer', 'Gio', 'Ven', 'Sab', 'Dom'];

/// Vista calendario mensile dei turni, alternativa alla lista (toggle in
/// AppBar di TurniList). Griglia del mese con un pallino per turno (colore
/// dell'associazione) e, sotto, i turni del giorno selezionato.
///
/// Griglia custom invece di un package (es. table_calendar): serve solo una
/// vista mese con marker, e il progetto tiene deliberatamente il pubspec
/// minimo (stessa ragione per cui byId* evita il package collection).
///
/// Il giorno selezionato è stato del padre (TurniList), non locale: serve
/// anche al FAB per precompilare la data quando si crea un turno dal
/// calendario. Il mese visualizzato invece è solo di questa vista.
class CalendarioTurni extends StatefulWidget {
  final List<Turno> turni;
  final AnagraficheProvider anag;
  final DateTime giornoSelezionato;
  final ValueChanged<DateTime> onSelezionaGiorno;
  final void Function(Turno) onTapTurno;

  const CalendarioTurni({
    super.key,
    required this.turni,
    required this.anag,
    required this.giornoSelezionato,
    required this.onSelezionaGiorno,
    required this.onTapTurno,
  });

  @override
  State<CalendarioTurni> createState() => _CalendarioTurniState();
}

class _CalendarioTurniState extends State<CalendarioTurni> {
  // Primo giorno del mese visualizzato (giorno sempre 1: il resto della
  // griglia si ricava da qui).
  late DateTime _mese;

  @override
  void initState() {
    super.initState();
    _mese = DateTime(widget.giornoSelezionato.year, widget.giornoSelezionato.month, 1);
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
    // Turni raggruppati per data ISO. substring difensivo: i dati normali
    // sono già YYYY-MM-DD, ma un backup legacy importato male potrebbe avere
    // un datetime completo — meglio un raggruppamento corretto che un buco.
    final turniPerGiorno = <String, List<Turno>>{};
    for (final t in widget.turni) {
      final chiave = t.data.length > 10 ? t.data.substring(0, 10) : t.data;
      turniPerGiorno.putIfAbsent(chiave, () => []).add(t);
    }

    final selIso = dateToIso(widget.giornoSelezionato);
    final turniDelGiorno = turniPerGiorno[selIso] ?? const <Turno>[];

    return Column(
      children: [
        _intestazioneMese(),
        _rigaGiorniSettimana(),
        _griglia(turniPerGiorno, selIso),
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
                turniDelGiorno.length == 1 ? '1 turno' : '${turniDelGiorno.length} turni',
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
          ),
        ),
        Expanded(
          child: turniDelGiorno.isEmpty
              ? const Center(
                  child: Text(
                    'Nessun turno in questo giorno',
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                )
              : ListView.builder(
                  // Padding basso abbondante per non finire sotto il FAB.
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                  itemCount: turniDelGiorno.length,
                  itemBuilder: (ctx, i) {
                    final turno = turniDelGiorno[i];
                    return TurnoCard(
                      turno: turno,
                      anag: widget.anag,
                      onTap: () => widget.onTapTurno(turno),
                    );
                  },
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
              '${_mesi[_mese.month - 1]} ${_mese.year}',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
          ),
          TextButton(
            onPressed: _vaiAOggi,
            child: const Text('Oggi'),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Colors.white70),
            tooltip: 'Mese precedente',
            onPressed: () => _cambiaMese(-1),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: Colors.white70),
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
          for (final g in _giorniSettimana)
            Expanded(
              child: Center(
                child: Text(
                  g,
                  style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _griglia(Map<String, List<Turno>> turniPerGiorno, String selIso) {
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
                  _cella(s * 7 + g - offset + 1, giorniNelMese, turniPerGiorno, selIso),
              ],
            ),
        ],
      ),
    );
  }

  /// Cella di un giorno. [numero] può uscire da [1..giorniNelMese]: in quel
  /// caso è un giorno del mese adiacente, mostrato attenuato e non tappabile
  /// (il costruttore DateTime lo normalizza alla data reale per il numero).
  Widget _cella(int numero, int giorniNelMese, Map<String, List<Turno>> turniPerGiorno, String selIso) {
    final giorno = DateTime(_mese.year, _mese.month, numero);
    final nelMese = numero >= 1 && numero <= giorniNelMese;
    final iso = dateToIso(giorno);
    final turniGiorno = nelMese ? (turniPerGiorno[iso] ?? const <Turno>[]) : const <Turno>[];
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
                : (oggi ? Border.all(color: Colors.white24) : null),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${giorno.day}',
                style: TextStyle(
                  fontSize: 13,
                  color: !nelMese
                      ? Colors.white24
                      : (oggi ? kPrimary : Colors.white),
                  fontWeight: selezionato || oggi ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              // Altezza fissa anche senza pallini: evita che i numeri dei
              // giorni "ballino" tra celle con e senza turni.
              SizedBox(
                height: 8,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final t in turniGiorno.take(4))
                      Container(
                        width: 5,
                        height: 5,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: colorFromHex(t.associazioneColore) ?? kPrimary,
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
