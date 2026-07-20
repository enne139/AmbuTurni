import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'db/database.dart';
import 'navigation/app_navigator.dart';
import 'providers/app_provider.dart';
import 'utils/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Inizializza il database locale (SQLite) prima di avviare l'app.
  await getDb();
  runApp(const AmbuTurniApp());
}

/// Widget radice dell'app.
class AmbuTurniApp extends StatelessWidget {
  const AmbuTurniApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Provider separati per scope diversi: Anagrafiche è globale e cambia
    // poco; Turni, Assistenze e Statistiche hanno ciascuno il proprio filtro
    // e ciclo di vita.
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AnagraficheProvider()),
        ChangeNotifierProvider(create: (_) => TurniProvider()),
        ChangeNotifierProvider(create: (_) => AssistenzeProvider()),
        ChangeNotifierProvider(create: (_) => StatisticheProvider()),
        ChangeNotifierProvider(create: (_) => ToolsProvider()),
        ChangeNotifierProvider(create: (_) => NavigazioneProvider()),
        ChangeNotifierProvider(create: (_) => TutorialProvider()),
      ],
      child: MaterialApp(
        title: 'AmbuTurni',
        debugShowCheckedModeBanner: false,
        theme: buildDarkTheme(),
        // Solo per i widget Material nativi (es. showDatePicker in
        // turno_form.dart/assistenza_form.dart): il resto dell'app non usa
        // flutter_localizations, tutte le stringhe sono già fisse in
        // italiano (vedi CLAUDE.md). locale fissato a 'it' invece di seguire
        // quella del sistema, coerente col resto dell'app che non segue mai
        // la lingua del device.
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('it')],
        locale: const Locale('it'),
        home: const AppNavigator(),
      ),
    );
  }
}
