import { useFocusEffect } from '@react-navigation/native';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import React, { useCallback, useMemo, useState } from 'react';
import { FlatList, StyleSheet, View } from 'react-native';
import { Button, Card, Dialog, FAB, Portal, Searchbar, Text } from 'react-native-paper';
import { deleteAssistenza, getAssistenze, type AssistenzaRow } from '../../db/helpers';
import type { AssistenzeStackParamList } from '../../navigation/AppNavigator';
import { formatDate, formatOre } from '../../utils/format';
import { colors } from '../../utils/theme';

type Props = NativeStackScreenProps<AssistenzeStackParamList, 'AssistenzeList'>;

/** Lista delle assistenze (data decrescente) con ricerca, FAB e long-press per eliminare. */
export default function AssistezeListScreen({ navigation }: Props) {
  const [items, setItems] = useState<AssistenzaRow[]>([]);
  const [query, setQuery] = useState(''); // testo della Searchbar
  const [toDelete, setToDelete] = useState<AssistenzaRow | null>(null); // assistenza da confermare

  const load = useCallback(async () => {
    setItems(await getAssistenze());
  }, []);

  // Ricarica quando la schermata torna in focus.
  useFocusEffect(
    useCallback(() => {
      load();
    }, [load])
  );

  // Filtro per nome associazione o descrizione.
  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return items;
    return items.filter(
      (a) =>
        (a.associazione_nome ?? '').toLowerCase().includes(q) ||
        (a.descrizione ?? '').toLowerCase().includes(q)
    );
  }, [items, query]);

  // Conferma eliminazione dal dialog.
  const confirmDelete = useCallback(async () => {
    if (!toDelete) return;
    await deleteAssistenza(toDelete.id);
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
        keyExtractor={(a) => a.id}
        contentContainerStyle={styles.list}
        renderItem={({ item }) => (
          <Card
            style={styles.card}
            mode="contained"
            onPress={() => navigation.navigate('AssistenzaDetail', { id: item.id })}
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
                </Text>
              </View>
            </View>
          </Card>
        )}
        ListEmptyComponent={
          <Text style={styles.empty}>Nessuna assistenza. Tocca + per aggiungerne una.</Text>
        }
      />
      <FAB
        icon="plus"
        style={styles.fab}
        color="#FFFFFF"
        onPress={() => navigation.navigate('AssistenzaForm', {})}
      />

      <Portal>
        <Dialog visible={!!toDelete} onDismiss={() => setToDelete(null)}>
          <Dialog.Title>Elimina assistenza</Dialog.Title>
          <Dialog.Content>
            <Text>
              Eliminare l’assistenza #{toDelete?.numero_progressivo} di{' '}
              {toDelete?.associazione_nome ?? 'questa associazione'}?
            </Text>
          </Dialog.Content>
          <Dialog.Actions>
            <Button onPress={() => setToDelete(null)}>Annulla</Button>
            <Button textColor={colors.secondary} onPress={confirmDelete}>
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
  stripe: { width: 6, backgroundColor: colors.secondary, alignSelf: 'stretch' },
  cardBody: { flex: 1, padding: 12 },
  titleRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  assoc: { color: colors.textPrimary, flex: 1 },
  progressivo: { color: colors.secondary, fontWeight: '700' },
  meta: { color: colors.textSecondary, marginTop: 4 },
  empty: { color: colors.textSecondary, textAlign: 'center', marginTop: 48 },
  fab: {
    position: 'absolute',
    right: 16,
    bottom: 16,
    backgroundColor: colors.secondary,
  },
});
