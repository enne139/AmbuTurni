import 'package:intl/intl.dart';

// Formato date italiano visualizzato in lista e nei dettagli.
final _dateFormatter = DateFormat('dd/MM/yyyy');

/// Formatta una stringa data ISO (YYYY-MM-DD) in dd/MM/yyyy.
/// Restituisce '—' se la stringa è nulla o non parsabile.
String formatDate(String? isoDate) {
  if (isoDate == null || isoDate.isEmpty) return '—';
  try {
    final dt = DateTime.parse(isoDate);
    return _dateFormatter.format(dt);
  } catch (_) {
    return isoDate;
  }
}

/// Formatta le ore decimali in "Xh YYm" (es. 8.5 → "8h 30m").
/// Restituisce '—' se null.
String formatOre(double? ore) {
  if (ore == null) return '—';
  final h = ore.floor();
  final m = ((ore - h) * 60).round();
  if (m == 0) return '${h}h';
  return '${h}h ${m.toString().padLeft(2, '0')}m';
}

/// Converte "Xh YYm" o "X,Y" o "X.Y" in ore decimali.
/// Usato nel form per parsare il campo ore.
double? parseOre(String? input) {
  if (input == null || input.trim().isEmpty) return null;
  final s = input.trim().replaceAll(',', '.');
  // Formato "Xh Ym" o "Xh"
  final hm = RegExp(r'^(\d+)h\s*(\d+)?m?$').firstMatch(s);
  if (hm != null) {
    final h = int.parse(hm.group(1)!);
    final m = int.tryParse(hm.group(2) ?? '0') ?? 0;
    return h + m / 60;
  }
  return double.tryParse(s);
}

/// Restituisce la data ISO di oggi (YYYY-MM-DD).
String todayIso() {
  final now = DateTime.now();
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}
