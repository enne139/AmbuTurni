import 'package:flutter/material.dart';
import '../utils/theme.dart';

/// Chip colorato per visualizzare un codice chiamata o uscita del servizio.
/// Il colore è determinato dalla funzione getCodiceColor in theme.dart.
class CodiceChip extends StatelessWidget {
  final String? codice;
  final String prefisso;

  const CodiceChip({super.key, this.codice, this.prefisso = ''});

  @override
  Widget build(BuildContext context) {
    if (codice == null || codice!.isEmpty) return const SizedBox.shrink();
    final color = getCodiceColor(codice);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        prefisso.isEmpty ? codice! : '$prefisso: $codice',
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
