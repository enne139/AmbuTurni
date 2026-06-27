// Entry point dell'app: inizializza il database e monta provider + navigazione.
//
// `react-native-get-random-values` DEVE essere importato per primo: fornisce
// crypto.getRandomValues, richiesto da `uuid` per generare gli ID.
import 'react-native-get-random-values';

import { NavigationContainer, type Theme } from '@react-navigation/native';
import { StatusBar } from 'expo-status-bar';
import React, { useEffect, useState } from 'react';
import { StyleSheet, View } from 'react-native';
import { ActivityIndicator, PaperProvider, Text } from 'react-native-paper';
import { SafeAreaProvider } from 'react-native-safe-area-context';
import { initDatabase } from './src/db';
import AppNavigator from './src/navigation/AppNavigator';
import { colors, paperTheme } from './src/utils/theme';

// Tema per React Navigation (allineato ai colori del tema Paper).
const navTheme: Theme = {
  dark: true,
  colors: {
    primary: colors.primary,
    background: colors.background,
    card: colors.surface,
    text: colors.textPrimary,
    border: colors.border,
    notification: colors.primary,
  },
  fonts: {
    regular: { fontFamily: 'System', fontWeight: '400' },
    medium: { fontFamily: 'System', fontWeight: '500' },
    bold: { fontFamily: 'System', fontWeight: '700' },
    heavy: { fontFamily: 'System', fontWeight: '900' },
  },
};

export default function App() {
  // `ready` diventa true quando lo schema DB è pronto; `error` mostra eventuali
  // problemi di inizializzazione (es. SQLite non disponibile).
  const [ready, setReady] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // Inizializza il database una sola volta all'avvio.
  useEffect(() => {
    initDatabase()
      .then(() => setReady(true))
      .catch((e: unknown) => setError(String(e)));
  }, []);

  return (
    <SafeAreaProvider>
      <PaperProvider theme={paperTheme}>
        <StatusBar style="light" />
        {/* Tre stati: errore DB → schermata errore; pronto → app; altrimenti spinner. */}
        {error ? (
          <View style={styles.center}>
            <Text style={styles.error}>Errore inizializzazione DB:{'\n'}{error}</Text>
          </View>
        ) : ready ? (
          <NavigationContainer theme={navTheme}>
            <AppNavigator />
          </NavigationContainer>
        ) : (
          <View style={styles.center}>
            <ActivityIndicator size="large" color={colors.primary} />
          </View>
        )}
      </PaperProvider>
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  center: { flex: 1, alignItems: 'center', justifyContent: 'center', backgroundColor: colors.background },
  error: { color: '#F44336', textAlign: 'center', padding: 24 },
});
