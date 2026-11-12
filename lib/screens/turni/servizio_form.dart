import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../db/helpers.dart';
import '../../db/models.dart';
import '../../providers/app_provider.dart';
import '../../utils/theme.dart';
import '../../widgets/anag_pickers.dart';
import '../../widgets/campi_servizio.dart';

/// Form per aggiungere o modificare un servizio di un turno.
class ServizioForm extends StatefulWidget {
  final String turnoId;
  final String? servizioId;
  final int ordine;
  const ServizioForm({super.key, required this.turnoId, this.servizioId, required this.ordine});

  @override
  State<ServizioForm> createState() => _ServizioFormState();
}

class _ServizioFormState extends State<ServizioForm> {
  String? _codiceChiamata;
  String? _codiceUscita;
  String? _ospedaleId;
  late TextEditingController _descCtrl;
  // Valori dei campi personalizzati, partendo da quelli salvati: comprende
  // anche i campi nascosti, che il form non mostra ma non deve cancellare.
  Map<String, dynamic> _campi = {};
  // Controller dei campi di testo e numero, creati alla prima costruzione
  // del campo (l'elenco dei campi arriva dal provider, non da qui).
  final Map<String, TextEditingController> _ctrlCampi = {};
  bool _loading = true;
  bool _saving = false;
  String? _existingId;
  String? _erroreCaricamento;

  @override
  void initState() {
    super.initState();
    _descCtrl = TextEditingController();
    _caricaDati();
  }

  /// Carica i dati del servizio esistente in modalità modifica.
  /// Rilegge tutti i servizi del turno e filtra per ID: più semplice che
  /// aggiungere una getServizioById dedicata per un caso così raro.
  Future<void> _caricaDati() async {
    try {
      if (widget.servizioId != null) {
        final servizi = await getServizi(widget.turnoId);
        final s = servizi.where((s) => s.id == widget.servizioId).firstOrNull;
        if (s != null && mounted) {
          setState(() {
            _existingId = s.id;
            _codiceChiamata = s.codiceChiamata;
            _codiceUscita = s.codiceUscita;
            _ospedaleId = s.ospedaleId;
            _descCtrl.text = s.descrizione ?? '';
            _campi = Map<String, dynamic>.from(s.campi);
          });
        }
      }
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() { _loading = false; _erroreCaricamento = e.toString(); });
    }
  }

  /// Valori da salvare: quelli salvati prima (campi nascosti compresi), con
  /// sopra quelli dei campi visibili come sono adesso nel form. Restituisce
  /// null, dopo aver avvisato, se un campo numero contiene un testo che non
  /// è un numero.
  Map<String, dynamic>? _valoriCampi() {
    final valori = Map<String, dynamic>.from(_campi);
    for (final campo in context.read<AnagraficheProvider>().campiServizioVisibili) {
      if (campo.speciale) {
        // Il sesso è già nella mappa (scelto dalla tendina), l'età si legge
        // dal suo controller; senza nessuna delle due il valore si toglie.
        final parti = _parti(campo)..remove('eta');
        final testo = _ctrlEta(campo).text.trim();
        if (testo.isNotEmpty) {
          final eta = parseNumeroCampo(testo);
          if (eta == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('L\'età deve essere un numero')),
            );
            return null;
          }
          parti['eta'] = eta;
        }
        if (parti.isEmpty) {
          valori.remove(campo.id);
        } else {
          valori[campo.id] = parti;
        }
        continue;
      }
      // Tendina, colori, combo box e orario sono già nella mappa (scelti col
      // tocco); testo e numero si leggono dai loro controller.
      if (campo.tipo != kCampoTesto && campo.tipo != kCampoNumero) continue;
      final testo = _ctrlCampi[campo.id]?.text.trim() ?? '';
      if (testo.isEmpty) {
        valori.remove(campo.id);
      } else if (campo.tipo == kCampoTesto) {
        valori[campo.id] = testo;
      } else {
        final n = parseNumeroCampo(testo);
        if (n == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('«${campo.nome}» deve essere un numero')),
          );
          return null;
        }
        valori[campo.id] = n;
      }
    }
    return valori;
  }

  Future<void> _salva() async {
    final campi = _valoriCampi();
    if (campi == null) return;
    setState(() => _saving = true);
    final s = Servizio(
      id: _existingId ?? newId(),
      turnoId: widget.turnoId,
      codiceChiamata: _codiceChiamata,
      codiceUscita: _codiceUscita,
      ospedaleId: _ospedaleId,
      descrizione: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      ordine: widget.ordine,
      campi: campi,
    );
    try {
      await saveServizio(s);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore durante il salvataggio: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    for (final c in _ctrlCampi.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Controller di un campo testo o numero, creato col valore salvato.
  TextEditingController _ctrlCampo(CampoServizio campo) =>
      _ctrlCampi.putIfAbsent(campo.id, () {
        final v = _campi[campo.id];
        final testo = v is num ? formatNumeroCampo(v) : (v is String ? v : '');
        return TextEditingController(text: testo);
      });

  /// Valore del campo speciale come mappa modificabile ({"sesso", "eta"}).
  Map<String, dynamic> _parti(CampoServizio campo) {
    final v = _campi[campo.id];
    return v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
  }

  /// Controller dell'età del campo speciale, creato col valore salvato.
  TextEditingController _ctrlEta(CampoServizio campo) =>
      _ctrlCampi.putIfAbsent('${campo.id}.eta', () {
        final eta = campo.etaDi(_campi[campo.id]);
        return TextEditingController(text: eta == null ? '' : formatNumeroCampo(eta));
      });

  /// Sceglie (o toglie, con null) il sesso nel campo speciale, lasciando
  /// com'è l'età.
  void _scegliSesso(CampoServizio campo, String? opzioneId) => setState(() {
        final parti = _parti(campo);
        if (opzioneId == null) {
          parti.remove('sesso');
        } else {
          parti['sesso'] = opzioneId;
        }
        if (parti.isEmpty) {
          _campi.remove(campo.id);
        } else {
          _campi[campo.id] = parti;
        }
      });

  /// Campo speciale: sesso (tendina) ed età (numero) sulla stessa riga,
  /// ognuno con la sua etichetta, come voluto dall'utente.
  Widget _inputSessoEta(CampoServizio campo) {
    const stileEtichetta = TextStyle(color: kPrimary, fontSize: 13, fontWeight: FontWeight.w600);
    final sesso = campo.sessoDi(_campi[campo.id])?.id;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Sesso', style: stileEtichetta),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                initialValue: sesso,
                dropdownColor: Theme.of(context).colorScheme.surface,
                decoration: const InputDecoration(),
                hint: const Text('—'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('—')),
                  ...campo.opzioni.map((o) => DropdownMenuItem<String?>(value: o.id, child: Text(o.nome))),
                ],
                onChanged: (v) => _scegliSesso(campo, v),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Età', style: stileEtichetta),
              const SizedBox(height: 8),
              TextField(
                controller: _ctrlEta(campo),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(hintText: 'Anni'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Imposta (o toglie, con null) il valore scelto in un campo a tendina o
  /// a colori.
  void _scegli(CampoServizio campo, String? opzioneId) => setState(() {
        if (opzioneId == null) {
          _campi.remove(campo.id);
        } else {
          _campi[campo.id] = opzioneId;
        }
      });

  /// Apre l'orologio per un campo orario, partendo dall'ora salvata o da
  /// adesso, sempre nel formato 24 ore.
  Future<void> _scegliOrario(CampoServizio campo, String? attuale) async {
    final parti = attuale?.split(':');
    final iniziale = parti == null
        ? TimeOfDay.now()
        : TimeOfDay(hour: int.parse(parti[0]), minute: int.parse(parti[1]));
    final ora = await showTimePicker(
      context: context,
      initialTime: iniziale,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (ora == null || !mounted) return;
    String due(int n) => n.toString().padLeft(2, '0');
    _scegli(campo, '${due(ora.hour)}:${due(ora.minute)}');
  }

  /// Il controllo giusto per il tipo di un campo personalizzato.
  Widget _inputCampo(CampoServizio campo) {
    // Un valore che non vale più (opzione tolta) va trattato come vuoto,
    // altrimenti la tendina riceverebbe un valore che non ha tra le voci.
    final valore = _campi[campo.id];
    final daElenco = campo.tipo == kCampoTendina || campo.tipo == kCampoColori;
    final scelto = daElenco && campo.valoreValido(valore) ? valore as String : null;
    switch (campo.tipo) {
      case kCampoTendina:
        return DropdownButtonFormField<String?>(
          initialValue: scelto,
          dropdownColor: Theme.of(context).colorScheme.surface,
          decoration: const InputDecoration(),
          hint: const Text('—'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('—')),
            ...campo.opzioni.map((o) => DropdownMenuItem<String?>(value: o.id, child: Text(o.nome))),
          ],
          onChanged: (v) => _scegli(campo, v),
        );
      case kCampoColori:
        // Chip colorati come i codici chiamata/uscita; toccare quello già
        // scelto lo toglie.
        return Wrap(
          spacing: 8,
          runSpacing: 4,
          children: campo.opzioni.map((o) {
            final sel = scelto == o.id;
            final colore = colorFromHex(o.colore) ?? coloreTesto(context, 0.4);
            return ChoiceChip(
              avatar: PallinoColore(colore: o.colore),
              label: Text(o.nome),
              selected: sel,
              showCheckmark: false,
              selectedColor: colore.withValues(alpha: 0.3),
              side: sel ? BorderSide(color: colore, width: 1.5) : null,
              onSelected: (v) => _scegli(campo, v ? o.id : null),
            );
          }).toList(),
        );
      case kCampoNumero:
        return TextField(
          controller: _ctrlCampo(campo),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(hintText: 'Numero'),
        );
      case kCampoOrario:
        // Niente tastiera: si tocca e si sceglie l'ora con l'orologio; la
        // x la toglie.
        final ora = campo.pulisci(valore) as String?;
        return InkWell(
          onTap: () => _scegliOrario(campo, ora),
          borderRadius: BorderRadius.circular(8),
          child: InputDecorator(
            isEmpty: ora == null,
            decoration: InputDecoration(
              hintText: 'Tocca per scegliere l\'ora',
              prefixIcon: const Icon(Icons.access_time, size: 18),
              suffixIcon: ora == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Togli l\'orario',
                      onPressed: () => _scegli(campo, null),
                    ),
            ),
            child: Text(ora ?? ''),
          ),
        );
      case kCampoCombo:
        // Scelta multipla: un chip con la spunta per ogni valore, se ne
        // accendono quanti se ne vuole. Si salvano gli id nell'ordine
        // dell'elenco, non in quello del tocco.
        final scelti = (campo.pulisci(valore) as List?) ?? const [];
        return Wrap(
          spacing: 8,
          runSpacing: 4,
          children: campo.opzioni.map((o) {
            return FilterChip(
              label: Text(o.nome),
              selected: scelti.contains(o.id),
              selectedColor: kPrimary.withValues(alpha: 0.25),
              onSelected: (v) => setState(() {
                final nuovi = campo.opzioni
                    .where((x) => x.id == o.id ? v : scelti.contains(x.id))
                    .map((x) => x.id)
                    .toList();
                if (nuovi.isEmpty) {
                  _campi.remove(campo.id);
                } else {
                  _campi[campo.id] = nuovi;
                }
              }),
            );
          }).toList(),
        );
      default:
        return TextField(
          controller: _ctrlCampo(campo),
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_erroreCaricamento != null) {
      return Scaffold(body: Center(child: Text('Errore: $_erroreCaricamento')));
    }
    final anag = context.watch<AnagraficheProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.servizioId == null ? 'Nuovo servizio' : 'Modifica servizio'),
        actions: [
          if (_saving)
            const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
          else
            IconButton(icon: const Icon(Icons.check), onPressed: _salva),
        ],
      ),
      // Ordine richiesto dall'utente: codici, ospedale, descrizione e solo
      // dopo i campi personalizzati, così la descrizione resta in alto anche
      // quando i campi sono tanti. Prima la descrizione era in fondo e
      // riempiva lo spazio libero (CustomScrollView + SliverFillRemaining):
      // in mezzo agli altri campi ha invece un'altezza che cresce col testo
      // (da 4 a 10 righe, poi scorre dentro il campo), e la pagina intera
      // scorre in una ListView, quindi la tastiera non manda in overflow.
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Codice chiamata
          const Text('Codice chiamata', style: TextStyle(color: kPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: codiciChiamata.map((c) => ChoiceChip(
              label: Text(c),
              selected: _codiceChiamata == c,
              selectedColor: getCodiceColor(c).withValues(alpha: 0.3),
              labelStyle: TextStyle(color: _codiceChiamata == c ? getCodiceColor(c) : coloreTesto(context, 0.6)),
              onSelected: (sel) => setState(() => _codiceChiamata = sel ? c : null),
            )).toList(),
          ),
          const SizedBox(height: 20),

          // Codice uscita
          const Text('Codice uscita', style: TextStyle(color: kPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: codiciUscita.map((c) => ChoiceChip(
              label: Text(c),
              selected: _codiceUscita == c,
              selectedColor: getCodiceColor(c).withValues(alpha: 0.3),
              labelStyle: TextStyle(color: _codiceUscita == c ? getCodiceColor(c) : coloreTesto(context, 0.6)),
              onSelected: (sel) => setState(() => _codiceUscita = sel ? c : null),
            )).toList(),
          ),
          const SizedBox(height: 20),

          // Ospedale
          const Text('Ospedale', style: TextStyle(color: kPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          OspedalePicker(
            ospedali: anag.ospedali,
            selectedId: _ospedaleId,
            onChanged: (v) => setState(() => _ospedaleId = v),
          ),
          const SizedBox(height: 20),

          // Descrizione: accetta markdown.
          const Text('Descrizione', style: TextStyle(color: kPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextFormField(
            controller: _descCtrl,
            minLines: 4,
            maxLines: 10,
            keyboardType: TextInputType.multiline,
            textAlignVertical: TextAlignVertical.top,
            decoration: const InputDecoration(
              hintText: 'Descrizione del servizio in markdown (opzionale)',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 20),

          // Campi personalizzati visibili, nell'ordine delle
          // Impostazioni → Campi dei servizi.
          for (final campo in anag.campiServizioVisibili) ...[
            if (campo.speciale)
              _inputSessoEta(campo)
            else ...[
              Text(campo.nome, style: const TextStyle(color: kPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              _inputCampo(campo),
            ],
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }
}
