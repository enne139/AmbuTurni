import { MD3DarkTheme } from 'react-native-paper';

/**
 * Palette dell'app — "scuro operativo".
 * Vedi specifica DESIGN.
 */
export const colors = {
  background: '#121212',
  surface: '#1E1E1E',
  surfaceVariant: '#2A2A2A',
  border: '#333333',
  primary: '#FF6B00', // turni
  secondary: '#1565C0', // assistenze
  textPrimary: '#FFFFFF',
  textSecondary: '#9E9E9E',
} as const;

/** Colori semantici dei codici chiamata / uscita. */
export const codiceColors: Record<string, string> = {
  VERDE: '#4CAF50',
  GIALLO: '#FFC107',
  ROSSO: '#F44336',
  verde: '#4CAF50',
  giallo: '#FFC107',
  rosso: '#F44336',
  nero: '#424242',
  vuoto: '#9E9E9E',
  rifiuta: '#9C27B0',
};

/** Ritorna il colore semantico di un codice, con fallback grigio. */
export function getCodiceColor(codice?: string | null): string {
  if (!codice) return colors.textSecondary;
  return codiceColors[codice] ?? colors.textSecondary;
}

/** Tema Paper MD3 dark con override dei token principali. */
export const paperTheme = {
  ...MD3DarkTheme,
  colors: {
    ...MD3DarkTheme.colors,
    primary: colors.primary,
    secondary: colors.secondary,
    background: colors.background,
    surface: colors.surface,
    surfaceVariant: colors.surfaceVariant,
    onSurface: colors.textPrimary,
    onBackground: colors.textPrimary,
    outline: colors.border,
    elevation: {
      ...MD3DarkTheme.colors.elevation,
      level0: 'transparent',
      level1: colors.surface,
      level2: colors.surfaceVariant,
      level3: colors.surfaceVariant,
      level4: colors.surfaceVariant,
      level5: colors.surfaceVariant,
    },
  },
};

export type AppTheme = typeof paperTheme;
