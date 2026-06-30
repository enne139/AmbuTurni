import 'package:flutter/material.dart';

// Colori principali dell'app — stessa palette del branch React Native.
const Color kBackground = Color(0xFF1a1a2e);
const Color kSurface = Color(0xFF16213e);
const Color kPrimary = Color(0xFFe94560);
const Color kOnBackground = Colors.white;
const Color kCardBorder = Color(0xFF2a2a4e);

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
    secondary: kPrimary.withOpacity(0.7),
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
    cardTheme: CardTheme(
      color: kSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: kCardBorder, width: 1),
      ),
      elevation: 2,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: kSurface,
      indicatorColor: kPrimary.withOpacity(0.2),
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
    dialogTheme: DialogTheme(
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
