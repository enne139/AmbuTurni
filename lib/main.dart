import 'package:flutter/material.dart';
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
    // Tre provider separati per scope diversi: Anagrafiche è globale e cambia
    // poco; Turni e Assistenze hanno ciascuno il proprio filtro e ciclo di vita.
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AnagraficheProvider()),
        ChangeNotifierProvider(create: (_) => TurniProvider()),
        ChangeNotifierProvider(create: (_) => AssistezeProvider()),
      ],
      child: MaterialApp(
        title: 'AmbuTurni',
        debugShowCheckedModeBanner: false,
        theme: buildDarkTheme(),
        home: const AppNavigator(),
      ),
    );
  }
}
