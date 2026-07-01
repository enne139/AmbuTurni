import 'package:flutter/material.dart';
import '../db/models.dart';
import '../providers/app_provider.dart';
import '../utils/format.dart';
import '../utils/theme.dart';

/// Card di un turno: numero progressivo, data, associazione, tipologia, ore
/// e contatore servizi. Condivisa tra la lista turni e le viste filtrate
/// (es. "turni di una persona/ospedale") per non duplicare il layout.
class TurnoCard extends StatelessWidget {
  final Turno turno;
  final AnagraficheProvider anag;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const TurnoCard({super.key, required this.turno, required this.anag, required this.onTap, this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Numero progressivo — colorato con il colore dell'associazione se impostato.
              Builder(builder: (ctx) {
                final accent = colorFromHex(turno.associazioneColore) ?? kPrimary;
                return Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: accent.withValues(alpha: 0.4)),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '#${turno.numeroProgressivo ?? '—'}',
                    style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                );
              }),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatDate(turno.data),
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    const SizedBox(height: 3),
                    Builder(builder: (_) {
                      final tipNomi = [
                        if (turno.tipologiaNome != null) turno.tipologiaNome!,
                        ...turno.tipologieExtra.map(
                          (id) => anag.byIdTipologia(id)?.nome ?? id,
                        ),
                      ];
                      final tipStr = tipNomi.join(' · ');
                      return Text(
                        [
                          if (turno.associazioneNome != null) turno.associazioneNome!,
                          if (tipStr.isNotEmpty) tipStr,
                        ].join(' · '),
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      );
                    }),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(formatOre(turno.ore), style: const TextStyle(color: kPrimary, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  if (turno.numServizi > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${turno.numServizi} serv.',
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
