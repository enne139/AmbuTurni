import { useFocusEffect } from '@react-navigation/native';
import React, { useCallback, useState } from 'react';
import { ScrollView, StyleSheet, View } from 'react-native';
import { Card, Chip, Text } from 'react-native-paper';
import {
  getAssociazioni,
  getStatistiche,
  type Associazione,
  type Statistiche,
} from '../../db/helpers';
import { colors } from '../../utils/theme';

/** Arrotonda a 2 decimali e rimuove gli zeri inutili. */
function fmtOre(n: number): string {
  return `${Math.round(n * 100) / 100} h`;
}

interface StatCard {
  label: string;
  value: string;
  accent: string;
}

export default function StatisticheScreen() {
  const [associazioni, setAssociazioni] = useState<Associazione[]>([]);
  const [assocId, setAssocId] = useState<string | null>(null);
  const [stats, setStats] = useState<Statistiche | null>(null);

  const load = useCallback(async () => {
    const [assoc, s] = await Promise.all([getAssociazioni(), getStatistiche(assocId)]);
    setAssociazioni(assoc);
    setStats(s);
  }, [assocId]);

  useFocusEffect(
    useCallback(() => {
      load();
    }, [load])
  );

  const cards: StatCard[] = stats
    ? [
        { label: 'Turni totali', value: String(stats.turniTotali), accent: colors.primary },
        { label: 'Servizi totali', value: String(stats.serviziTotali), accent: colors.primary },
        { label: 'Ore turni', value: fmtOre(stats.oreTurni), accent: colors.primary },
        {
          label: 'Assistenze totali',
          value: String(stats.assistenzeTotali),
          accent: colors.secondary,
        },
        { label: 'Ore assistenze', value: fmtOre(stats.oreAssistenze), accent: colors.secondary },
        { label: 'Ore totali', value: fmtOre(stats.oreTotali), accent: '#26A69A' },
      ]
    : [];

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      <Text variant="titleMedium" style={styles.filterTitle}>
        Filtra per associazione
      </Text>
      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        contentContainerStyle={styles.chipsRow}
      >
        <Chip
          selected={assocId === null}
          onPress={() => setAssocId(null)}
          style={styles.chip}
          showSelectedCheck
        >
          Tutte
        </Chip>
        {associazioni.map((a) => (
          <Chip
            key={a.id}
            selected={assocId === a.id}
            onPress={() => setAssocId(a.id)}
            style={styles.chip}
            showSelectedCheck
          >
            {a.nome}
          </Chip>
        ))}
      </ScrollView>

      <View style={styles.grid}>
        {cards.map((c) => (
          <Card key={c.label} style={styles.card} mode="contained">
            <View style={[styles.accent, { backgroundColor: c.accent }]} />
            <Card.Content style={styles.cardContent}>
              <Text style={styles.cardValue}>{c.value}</Text>
              <Text style={styles.cardLabel}>{c.label}</Text>
            </Card.Content>
          </Card>
        ))}
      </View>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { padding: 16, paddingBottom: 48 },
  filterTitle: { color: colors.textSecondary, marginBottom: 8 },
  chipsRow: { gap: 8, paddingBottom: 4, paddingRight: 8 },
  chip: { backgroundColor: colors.surfaceVariant },
  grid: { flexDirection: 'row', flexWrap: 'wrap', gap: 12, marginTop: 16 },
  card: {
    backgroundColor: colors.surface,
    width: '47%',
    overflow: 'hidden',
    flexGrow: 1,
  },
  accent: { height: 4, width: '100%' },
  cardContent: { paddingVertical: 16 },
  cardValue: { color: colors.textPrimary, fontSize: 28, fontWeight: '800' },
  cardLabel: { color: colors.textSecondary, marginTop: 4 },
});
