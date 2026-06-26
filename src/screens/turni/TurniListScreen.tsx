import { MaterialCommunityIcons } from '@expo/vector-icons';
import { useFocusEffect } from '@react-navigation/native';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import React, { useCallback, useMemo, useState } from 'react';
import { FlatList, StyleSheet, View } from 'react-native';
import { Button, Card, Dialog, FAB, Portal, Searchbar, Text } from 'react-native-paper';
import { deleteTurno, getTurni, type TurnoRow } from '../../db/helpers';
import type { TurniStackParamList } from '../../navigation/AppNavigator';
import { colors } from '../../utils/theme';
import { formatDate, formatOre } from '../../utils/format';

type Props = NativeStackScreenProps<TurniStackParamList, 'TurniList'>;

export default function TurniListScreen({ navigation }: Props) {
  const [turni, setTurni] = useState<TurnoRow[]>([]);
  const [query, setQuery] = useState('');
  const [toDelete, setToDelete] = useState<TurnoRow | null>(null);

  const load = useCallback(async () => {
    setTurni(await getTurni());
  }, []);

  useFocusEffect(
    useCallback(() => {
      load();
    }, [load])
  );

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return turni;
    return turni.filter(
      (t) =>
        (t.associazione_nome ?? '').toLowerCase().includes(q) ||
        (t.descrizione ?? '').toLowerCase().includes(q)
    );
  }, [turni, query]);

  const confirmDelete = useCallback(async () => {
    if (!toDelete) return;
    await deleteTurno(toDelete.id);
    setToDelete(null);
    load();
  }, [toDelete, load]);

  return (
    <View style={styles.container}>
      <Searchbar
        placeholder="Cerca per associazione o descrizione"
        value={query}
        onChangeText={setQuery}
        style={styles.search}
      />
      <FlatList
        data={filtered}
        keyExtractor={(t) => t.id}
        contentContainerStyle={styles.list}
        renderItem={({ item }) => (
          <Card
            style={styles.card}
            mode="contained"
            onPress={() => navigation.navigate('TurnoDetail', { id: item.id })}
            onLongPress={() => setToDelete(item)}
          >
            <View style={styles.cardRow}>
              <View style={styles.stripe} />
              <View style={styles.cardBody}>
                <View style={styles.titleRow}>
                  <Text variant="titleMedium" style={styles.assoc}>
                    {item.associazione_nome ?? 'Senza associazione'}
                  </Text>
                  <Text style={styles.progressivo}>#{item.numero_progressivo ?? '—'}</Text>
                </View>
                <Text style={styles.meta}>
                  {formatDate(item.data)} · {formatOre(item.ore)}
                  {item.tipologia_nome ? ` · ${item.tipologia_nome}` : ''}
                </Text>
                <View style={styles.badgeRow}>
                  <View style={styles.servBadge}>
                    <MaterialCommunityIcons
                      name="clipboard-list-outline"
                      size={14}
                      color={colors.primary}
                    />
                    <Text style={styles.servBadgeText}>{item.num_servizi} servizi</Text>
                  </View>
                </View>
              </View>
            </View>
          </Card>
        )}
        ListEmptyComponent={
          <Text style={styles.empty}>Nessun turno. Tocca + per aggiungerne uno.</Text>
        }
      />
      <FAB
        icon="plus"
        style={styles.fab}
        color="#FFFFFF"
        onPress={() => navigation.navigate('TurnoForm', {})}
      />

      <Portal>
        <Dialog visible={!!toDelete} onDismiss={() => setToDelete(null)}>
          <Dialog.Title>Elimina turno</Dialog.Title>
          <Dialog.Content>
            <Text>
              Eliminare il turno #{toDelete?.numero_progressivo} di{' '}
              {toDelete?.associazione_nome ?? 'questa associazione'}?
            </Text>
          </Dialog.Content>
          <Dialog.Actions>
            <Button onPress={() => setToDelete(null)}>Annulla</Button>
            <Button textColor={colors.primary} onPress={confirmDelete}>
              Elimina
            </Button>
          </Dialog.Actions>
        </Dialog>
      </Portal>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  search: { margin: 12, backgroundColor: colors.surfaceVariant },
  list: { paddingHorizontal: 12, paddingBottom: 96 },
  card: { backgroundColor: colors.surface, marginBottom: 10, overflow: 'hidden' },
  cardRow: { flexDirection: 'row' },
  stripe: { width: 6, backgroundColor: colors.primary, alignSelf: 'stretch' },
  cardBody: { flex: 1, padding: 12 },
  titleRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  assoc: { color: colors.textPrimary, flex: 1 },
  progressivo: { color: colors.primary, fontWeight: '700' },
  meta: { color: colors.textSecondary, marginTop: 4 },
  badgeRow: { flexDirection: 'row', marginTop: 8 },
  servBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    backgroundColor: colors.surfaceVariant,
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 6,
  },
  servBadgeText: { color: colors.textPrimary, fontSize: 12 },
  empty: { color: colors.textSecondary, textAlign: 'center', marginTop: 48 },
  fab: {
    position: 'absolute',
    right: 16,
    bottom: 16,
    backgroundColor: colors.primary,
  },
});
