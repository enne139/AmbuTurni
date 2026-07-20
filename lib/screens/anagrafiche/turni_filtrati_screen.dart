import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../db/helpers.dart';
import '../../db/models.dart';
import '../../providers/app_provider.dart';
import '../../utils/format.dart';
import '../../utils/theme.dart';
import '../../widgets/turno_card.dart';
import '../assistenze/assistenza_detail.dart';
import '../turni/turno_detail.dart';

/// Elenco di turni e assistenze in cui compare una determinata [Persona],
/// raggiungibile con un tap dalla lista Persone in Anagrafiche.
class TurniPersonaScreen extends StatefulWidget {
  final Persona persona;
  const TurniPersonaScreen({super.key, required this.persona});

  @override
  State<TurniPersonaScreen> createState() => _TurniPersonaScreenState();
}

class _TurniPersonaScreenState extends State<TurniPersonaScreen> {
  List<Turno> _turni = [];
  List<Assistenza> _assistenze = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _carica();
  }

  Future<void> _carica() async {
    final turni = await getTurniPerPersona(widget.persona.id);
    final assistenze = await getAssistenzePerPersona(widget.persona.id);
    if (!mounted) return;
    setState(() {
      _turni = turni;
      _assistenze = assistenze;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final anag = context.watch<AnagraficheProvider>();
    return Scaffold(
      appBar: AppBar(title: Text(widget.persona.nomeCompleto)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_turni.isEmpty && _assistenze.isEmpty)
              ? const Center(
                  child: Text('Nessun turno o assistenza trovati', style: TextStyle(color: Colors.white54)),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    if (_turni.isNotEmpty) ...[
                      _SezioneTitolo('Turni (${_turni.length})'),
                      ..._turni.map((t) => TurnoCard(
                            turno: t,
                            anag: anag,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => TurnoDetail(turnoId: t.id)),
                            ),
                          )),
                      const SizedBox(height: 12),
                    ],
                    if (_assistenze.isNotEmpty) ...[
                      _SezioneTitolo('Assistenze (${_assistenze.length})'),
                      ..._assistenze.map((a) => _AssistenzaCard(
                            assistenza: a,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => AssistenzaDetail(assistenzaId: a.id)),
                            ),
                          )),
                    ],
                  ],
                ),
    );
  }
}

/// Elenco dei turni in cui compare un determinato [Ospedale] (tramite i suoi servizi),
/// raggiungibile con un tap dalla lista Ospedali in Anagrafiche.
class TurniOspedaleScreen extends StatefulWidget {
  final Ospedale ospedale;
  const TurniOspedaleScreen({super.key, required this.ospedale});

  @override
  State<TurniOspedaleScreen> createState() => _TurniOspedaleScreenState();
}

class _TurniOspedaleScreenState extends State<TurniOspedaleScreen> {
  List<Turno> _turni = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _carica();
  }

  Future<void> _carica() async {
    final turni = await getTurniPerOspedale(widget.ospedale.id);
    if (!mounted) return;
    setState(() {
      _turni = turni;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final anag = context.watch<AnagraficheProvider>();
    return Scaffold(
      appBar: AppBar(title: Text(widget.ospedale.label)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _turni.isEmpty
              ? const Center(child: Text('Nessun turno trovato', style: TextStyle(color: Colors.white54)))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: _turni.length,
                  itemBuilder: (ctx, i) {
                    final t = _turni[i];
                    return TurnoCard(
                      turno: t,
                      anag: anag,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => TurnoDetail(turnoId: t.id)),
                      ),
                    );
                  },
                ),
    );
  }
}

class _SezioneTitolo extends StatelessWidget {
  final String titolo;
  const _SezioneTitolo(this.titolo);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(titolo, style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
    );
  }
}

/// Card di un'assistenza, stile analogo a TurnoCard ma senza tipologia/servizi.
class _AssistenzaCard extends StatelessWidget {
  final Assistenza assistenza;
  final VoidCallback onTap;
  const _AssistenzaCard({required this.assistenza, required this.onTap});

  @override
  Widget build(BuildContext context) {
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
              child: Text('#${assistenza.numeroProgressivo ?? '—'}',
                  style: const TextStyle(color: kPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(formatDate(assistenza.data), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                if (assistenza.associazioneNome != null)
                  Text(assistenza.associazioneNome!, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ]),
            ),
            Text(formatOre(assistenza.ore), style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
}
