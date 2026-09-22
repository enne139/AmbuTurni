import 'package:flutter/material.dart';

// Colori principali dell'app — stessa palette del branch React Native.
const Color kBackground = Color(0xFF1a1a2e);

// Palette predefinita per colorare associazioni e tipologie.
const List<String> kColorPalette = [
  '#E53935', '#FB8C00', '#FDD835', '#43A047',
  '#00897B', '#1E88E5', '#3949AB', '#8E24AA',
  '#D81B60', '#6D4C41', '#757575',
];

/// Converte un colore esadecimale ("#RRGGBB", con o senza "#") in Color.
/// Restituisce null se hex è null o non è esattamente 6 (RGB, alpha
/// implicito FF) o 8 (ARGB) cifre esadecimali — senza questa validazione un
/// valore senza "#" (es. "123456") veniva interpretato come decimale invece
/// che rifiutato, producendo un colore quasi trasparente invece del
/// fallback null atteso dai chiamanti.
Color? colorFromHex(String? hex) {
  if (hex == null || hex.isEmpty) return null;
  final normalizzato = hex.startsWith('#') ? hex.substring(1) : hex;
  if (!RegExp(r'^[0-9a-fA-F]{6}$|^[0-9a-fA-F]{8}$').hasMatch(normalizzato)) {
    return null;
  }
  final argb = normalizzato.length == 6 ? 'FF$normalizzato' : normalizzato;
  try {
    return Color(int.parse(argb, radix: 16));
  } catch (_) {
    return null;
  }
}

const Color kSurface = Color(0xFF16213e);
const Color kPrimary = Color(0xFFe94560);
const Color kOnBackground = Colors.white;
const Color kCardBorder = Color(0xFF2a2a4e);

// Palette del tema chiaro ("modalità bianca", Impostazioni → Aspetto):
// kPrimary resta lo stesso su entrambi i temi (identità del brand), cambiano
// solo sfondo/superficie/testo. kOnBackgroundLight riusa il blu navy di
// kBackground come "colore d'inchiostro" del tema chiaro — stessa identità
// cromatica dell'app, invertita.
const Color kBackgroundLight = Color(0xFFF2F2F7);
const Color kSurfaceLight = Colors.white;
const Color kOnBackgroundLight = Color(0xFF1A1A2E);
const Color kCardBorderLight = Color(0xFFE0E0E8);

/// Colore del testo/icone "principale" sul colore di sfondo/superficie
/// corrente del tema attivo (bianco nello scuro, blu navy nel chiaro).
/// Sostituisce i vecchi riferimenti diretti a Colors.white/white70/white54/...
/// sparsi nei widget, scritti quando l'app aveva un solo tema scuro fisso:
/// senza questo indiretto sarebbero rimasti bianchi anche col tema chiaro
/// attivo (testo bianco su sfondo bianco, illeggibile). [alpha] riproduce le
/// vecchie sfumature Colors.white70/54/38/24/12 (testo secondario,
/// disabilitato, bordo sottile...) restando coerente col tema attivo.
Color coloreTesto(BuildContext context, [double alpha = 1]) =>
    Theme.of(context).colorScheme.onSurface.withValues(alpha: alpha);

// Colori dei codici chiamata / uscita (case-insensitive via getCodiceColor).
const Map<String, Color> _codiceColors = {
  'verde': Color(0xFF4CAF50),
  'giallo': Color(0xFFFFEB3B),
  'rosso': Color(0xFFF44336),
  'dimissione': Color(0xFF2196F3),
  'nero': Color(0xFF424242),
  'vuoto': Color(0xFF757575),
  'rifiuto': Color(0xFFFF9800),
};

/// Restituisce il colore associato al codice (case-insensitive).
/// Se il codice non è riconosciuto restituisce un grigio neutro.
Color getCodiceColor(String? codice) {
  if (codice == null) return const Color(0xFF9E9E9E);
  return _codiceColors[codice.toLowerCase()] ?? const Color(0xFF9E9E9E);
}

/// Tema scuro Material 3 usato da tutta l'app.
ThemeData buildDarkTheme() {
  final colorScheme = ColorScheme.dark(
    primary: kPrimary,
    onPrimary: Colors.white,
    secondary: kPrimary.withValues(alpha: 0.7),
    surface: kSurface,
    onSurface: kOnBackground,
    error: const Color(0xFFCF6679),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: kBackground,
    appBarTheme: const AppBarTheme(
      backgroundColor: kSurface,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: kSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: kCardBorder, width: 1),
      ),
      elevation: 2,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: kSurface,
      indicatorColor: kPrimary.withValues(alpha: 0.2),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: kPrimary);
        }
        return const IconThemeData(color: Colors.white54);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(color: kPrimary, fontSize: 12, fontWeight: FontWeight.w600);
        }
        return const TextStyle(color: Colors.white54, fontSize: 12);
      }),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kPrimary,
      foregroundColor: Colors.white,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kSurface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: kCardBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: kCardBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: kPrimary),
      ),
      labelStyle: const TextStyle(color: Colors.white70),
      hintStyle: const TextStyle(color: Colors.white38),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: kCardBorder,
      labelStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    dividerColor: kCardBorder,
    dialogTheme: DialogThemeData(
      backgroundColor: kSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: kSurface,
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: kPrimary),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
  );
}

/// Tema chiaro Material 3 ("modalità bianca"), stessa struttura di
/// buildDarkTheme() con la palette kXxxLight al posto di kXxx — kPrimary e i
/// pulsanti restano invariati (identità del brand, contrasto già verificato
/// su sfondo chiaro). Attivabile da Impostazioni → Aspetto (TemaProvider).
ThemeData buildLightTheme() {
  final colorScheme = ColorScheme.light(
    primary: kPrimary,
    onPrimary: Colors.white,
    secondary: kPrimary.withValues(alpha: 0.7),
    surface: kSurfaceLight,
    onSurface: kOnBackgroundLight,
    error: const Color(0xFFB00020),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: kBackgroundLight,
    appBarTheme: const AppBarTheme(
      backgroundColor: kSurfaceLight,
      foregroundColor: kOnBackgroundLight,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: kSurfaceLight,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: kCardBorderLight, width: 1),
      ),
      elevation: 1,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: kSurfaceLight,
      indicatorColor: kPrimary.withValues(alpha: 0.15),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const IconThemeData(color: kPrimary);
        }
        return IconThemeData(color: kOnBackgroundLight.withValues(alpha: 0.54));
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const TextStyle(color: kPrimary, fontSize: 12, fontWeight: FontWeight.w600);
        }
        return TextStyle(color: kOnBackgroundLight.withValues(alpha: 0.54), fontSize: 12);
      }),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: kPrimary,
      foregroundColor: Colors.white,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: kSurfaceLight,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: kCardBorderLight),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: kCardBorderLight),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: kPrimary),
      ),
      labelStyle: TextStyle(color: kOnBackgroundLight.withValues(alpha: 0.7)),
      hintStyle: TextStyle(color: kOnBackgroundLight.withValues(alpha: 0.38)),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: kCardBorderLight,
      labelStyle: const TextStyle(color: kOnBackgroundLight),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    dividerColor: kCardBorderLight,
    dialogTheme: DialogThemeData(
      backgroundColor: kSurfaceLight,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: kSurfaceLight,
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: kPrimary),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
  );
}
