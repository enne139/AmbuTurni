import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../db/helpers.dart';
import '../../db/models.dart';
import '../../providers/app_provider.dart';
import '../../utils/backend_api.dart';
import '../../utils/materiali_condivisi.dart';
import '../../utils/theme.dart';
import '../../widgets/anag_pickers.dart';

/// Accesso al backend per un materiale condiviso: client già configurato e
/// token del login utente-app. Null nel form = materiale locale.
typedef AccessoCondiviso = ({BackendApi api, String token});

/// Form per registrare o modificare un utilizzo di materiale da ripristinare.
/// Se [esistente] (locale) o [esistenteCondiviso] è non-null si è in
/// modalità modifica: i campi vengono precompilati e il salvataggio
/// aggiorna la riga invece di crearne una nuova.
///
/// Con [condiviso] valorizzato il materiale vive sul backend condiviso
/// (visibile a tutti gli utenti con accesso) invece che nel DB locale: la
/// modalità la decide l'interruttore "Condivisi" della lista, non un campo
/// del form — ciò che si vede in lista è dove si aggiunge, senza un secondo
/// interruttore che possa contraddire il primo.
class MaterialeUsatoForm extends StatefulWidget {
  final MaterialeUsato? esistente;
  final MaterialeUsatoCondiviso? esistenteCondiviso;
  final AccessoCondiviso? condiviso;
  // Mezzi scaricati dal backend (selettore della lista) e quello scelto lì,
  // che precompila il campo per un materiale nuovo.
  final List<String> mezzi;
  final String? mezzoIniziale;

  const MaterialeUsatoForm({
    super.key,
    this.esistente,
    this.esistenteCondiviso,
    this.condiviso,
    this.mezzi = const [],
    this.mezzoIniziale,
  });

  @override
  State<MaterialeUsatoForm> createState() => _MaterialeUsatoFormState();
}

class _MaterialeUsatoFormState extends State<MaterialeUsatoForm> {
  late TextEditingController _unitaCtrl;
  late TextEditingController _noteCtrl;

  String? _materialeId;
  int _quantita = 1;
  String? _posizione;
  String? _mezzo;
  List<Materiale> _materiali = [];
  bool _loading = true;
  bool _saving = false;

  bool get _inModifica => widget.esistente != null || widget.esistenteCondiviso != null;

  @override
  void initState() {
    super.initState();
    final locale = widget.esistente;
    final condiviso = widget.esistenteCondiviso;
    _unitaCtrl = TextEditingController(text: locale?.unita ?? condiviso?.unita ?? '');
    _noteCtrl = TextEditingController(text: locale?.note ?? condiviso?.note ?? '');
    _materialeId = locale?.materialeId;
    _quantita = locale?.quantita ?? condiviso?.quantita ?? 1;
    _posizione = locale?.posizione ?? condiviso?.posizione;
    _mezzo = _inModifica ? (locale?.mezzo ?? condiviso?.mezzo) : widget.mezzoIniziale;
    _carica();
  }

  Future<void> _carica() async {
    var materiali = await getMateriali();
    // Un materiale condiviso porta solo il NOME (gli id dei cataloghi sono
    // diversi su ogni device): per il picker serve l'id locale con quel
    // nome. Se manca — nome creato al volo sul device di un altro
    // volontario — lo si aggiunge al catalogo locale con lo stesso upsert
    // del download dal backend, invece di lasciare il campo vuoto.
    final condiviso = widget.esistenteCondiviso;
    String? idDaNome;
    if (condiviso != null) {
      bool trova(Materiale m) => m.nome.toLowerCase() == condiviso.materiale.toLowerCase();
      if (!materiali.any(trova)) {
        await upsertMateriali([condiviso.materiale]);
        materiali = await getMateriali();
      }
      idDaNome = materiali.where(trova).firstOrNull?.id;
    }
    if (mounted) {
      setState(() {
        _materiali = materiali;
        _materialeId ??= idDaNome;
        _loading = false;
      });
    }
  }

  String? _testo(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _salva() async {
    if (_materialeId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seleziona un materiale')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final accesso = widget.condiviso;
      if (accesso == null) {
        await _salvaLocale();
      } else {
        await _salvaCondiviso(accesso);
      }
      if (mounted) Navigator.pop(context, true);
    } on BackendApiUnauthorized {
      // Token scaduto/revocato: logout, e si torna alla lista, che mostra
      // il login al posto dei materiali condivisi.
      if (!mounted) return;
      await context.read<AccountProvider>().logout();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sessione scaduta: accedi di nuovo per condividere.')),
      );
      Navigator.pop(context, false);
    } on BackendApiNotFound {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Questo materiale è già stato ripristinato da qualcun altro.')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        final messaggio = widget.condiviso == null ? '$e' : messaggioErroreBackend(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Errore durante il salvataggio: $messaggio')),
        );
      }
    }
  }

  Future<void> _salvaLocale() async {
    final mu = MaterialeUsato(
      id: widget.esistente?.id ?? newId(),
      materialeId: _materialeId!,
      quantita: _quantita,
      unita: _testo(_unitaCtrl),
      posizione: _posizione,
      mezzo: _mezzo,
      note: _testo(_noteCtrl),
      createdAt: widget.esistente?.createdAt,
    );
    await saveMaterialeUsato(mu);
  }

  Future<void> _salvaCondiviso(AccessoCondiviso accesso) async {
    final nome = _materiali.where((m) => m.id == _materialeId).firstOrNull?.nome;
    if (nome == null) throw const BackendApiException('materiale non trovato nel catalogo');
    final dati = datiMaterialeCondiviso(
      materiale: nome,
      quantita: _quantita,
      unita: _unitaCtrl.text,
      posizione: _posizione,
      mezzo: _mezzo,
      note: _noteCtrl.text,
    );
    final esistente = widget.esistenteCondiviso;
    if (esistente == null) {
      await accesso.api.creaMaterialeCondiviso(token: accesso.token, dati: dati);
    } else {
      await accesso.api.aggiornaMaterialeCondiviso(token: accesso.token, id: esistente.id, dati: dati);
    }
  }

  @override
  void dispose() {
    _unitaCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    // Il mezzo già salvato resta selezionabile anche se nel frattempo è
    // stato tolto dall'elenco del backend (o l'elenco non è ancora mai
    // stato scaricato su questo device).
    final mezzi = {...widget.mezzi, if (_mezzo != null) _mezzo!}.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: Text(_inModifica ? 'Modifica materiale usato' : 'Materiale usato'),
        actions: [
          if (_saving)
            const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
          else
            IconButton(icon: const Icon(Icons.check), onPressed: _salva),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.condiviso != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kPrimary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kPrimary.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.groups_outlined, color: kPrimary, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Condiviso con tutti: lo vedono gli altri volontari con accesso, '
                    'e chiunque di loro può segnarlo come ripristinato.',
                    style: TextStyle(color: coloreTesto(context, 0.7), fontSize: 13),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 20),
          ],

          const Text('Materiale *', style: TextStyle(color: kPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          MaterialePicker(
            materiali: _materiali,
            selectedId: _materialeId,
            onChanged: (v) async {
              // Se il materiale è stato creato al volo dal picker, ricarica
              // il catalogo per includerlo nella lista locale.
              if (v != null && _materiali.where((m) => m.id == v).isEmpty) {
                _materiali = await getMateriali();
              }
              setState(() => _materialeId = v);
            },
          ),
          const SizedBox(height: 20),

          const Text('Quantità', style: TextStyle(color: kPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: _quantita > 1 ? () => setState(() => _quantita--) : null,
            ),
            SizedBox(
              width: 48,
              child: Text('$_quantita', textAlign: TextAlign.center, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => setState(() => _quantita++),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _unitaCtrl,
                decoration: const InputDecoration(hintText: 'Unità (opzionale: flaconi, ml, confezioni...)'),
              ),
            ),
          ]),
          const SizedBox(height: 20),

          // Nessuna sezione se non ci sono mezzi: l'associazione non li ha
          // ancora configurati sul backend (o il device non li ha mai
          // scaricati), un'intestazione senza scelte confonderebbe.
          if (mezzi.isNotEmpty) ...[
            const Text('Mezzo', style: TextStyle(color: kPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: mezzi.map((m) => ChoiceChip(
                label: Text(m),
                selected: _mezzo == m,
                onSelected: (sel) => setState(() => _mezzo = sel ? m : null),
              )).toList(),
            ),
            const SizedBox(height: 20),
          ],

          const Text('Posizione', style: TextStyle(color: kPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: posizioniMateriale.map((p) => ChoiceChip(
              label: Text(p),
              selected: _posizione == p,
              onSelected: (sel) => setState(() => _posizione = sel ? p : null),
            )).toList(),
          ),
          const SizedBox(height: 20),

          const Text('Note', style: TextStyle(color: kPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextFormField(
            controller: _noteCtrl,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'Note (opzionale)'),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
