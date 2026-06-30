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
  runApp(const AmbulanzaTurniApp());
}

/// Widget radice dell'app.
class AmbulanzaTurniApp extends StatelessWidget {
  const AmbulanzaTurniApp({super.key});

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
        title: 'Ambulanza Turni',
        debugShowCheckedModeBanner: false,
        theme: buildDarkTheme(),
        home: const AppNavigator(),
      ),
    );
  }
}
