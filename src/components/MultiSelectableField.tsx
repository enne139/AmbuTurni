import React, { useCallback, useMemo, useState } from 'react';
import { FlatList, StyleSheet, View } from 'react-native';
import {
  Button,
  Chip,
  Divider,
  List,
  Modal,
  Portal,
  Searchbar,
  Text,
  TouchableRipple,
} from 'react-native-paper';
import type { LookupItem } from '../db/helpers';
import { colors } from '../utils/theme';

export interface MultiSelectableFieldProps {
  label: string;
  values: string[];
  displayValues: string[];
  onChange: (ids: string[], labels: string[]) => void;
  fetchItems: () => Promise<LookupItem[]>;
  onAddNew: (text: string) => Promise<LookupItem>;
  placeholder?: string;
}

/** Come SelectableField, ma a selezione multipla con chip rimovibili. */
export default function MultiSelectableField({
  label,
  values,
  displayValues,
  onChange,
  fetchItems,
  onAddNew,
  placeholder,
}: MultiSelectableFieldProps) {
  const [visible, setVisible] = useState(false);
  const [query, setQuery] = useState('');
  const [items, setItems] = useState<LookupItem[]>([]);

  const open = useCallback(async () => {
    setQuery('');
    setVisible(true);
    setItems(await fetchItems());
  }, [fetchItems]);

  const close = useCallback(() => setVisible(false), []);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return items;
    return items.filter((it) => it.label.toLowerCase().includes(q));
  }, [items, query]);

  const exactMatch = useMemo(
    () => items.some((it) => it.label.toLowerCase() === query.trim().toLowerCase()),
    [items, query]
  );

  // Aggiunge o rimuove un valore dalla selezione (mantenendo allineati id e label).
  const toggle = useCallback(
    (item: LookupItem) => {
      const idx = values.indexOf(item.id);
      if (idx >= 0) {
        // Già selezionato → lo rimuovo da entrambi gli array paralleli.
        const newIds = values.filter((v) => v !== item.id);
        const newLabels = displayValues.filter((_, i) => i !== idx);
        onChange(newIds, newLabels);
      } else {
        // Non selezionato → lo aggiungo in coda.
        onChange([...values, item.id], [...displayValues, item.label]);
      }
    },
    [values, displayValues, onChange]
  );

  // Rimuove la selezione tramite la "x" del chip.
  const removeChip = useCallback(
    (id: string) => {
      const idx = values.indexOf(id);
      if (idx < 0) return;
      onChange(
        values.filter((v) => v !== id),
        displayValues.filter((_, i) => i !== idx)
      );
    },
    [values, displayValues, onChange]
  );

  // Crea un nuovo valore nel DB, lo aggiunge alla selezione e ricarica la lista.
  const handleAdd = useCallback(async () => {
    const text = query.trim();
    if (!text) return;
    const created = await onAddNew(text);
    if (!values.includes(created.id)) {
      onChange([...values, created.id], [...displayValues, created.label]);
    }
    setQuery('');
    setItems(await fetchItems());
  }, [query, onAddNew, values, displayValues, onChange, fetchItems]);

  return (
    <View style={styles.wrapper}>
      <Text variant="labelMedium" style={styles.label}>
        {label}
      </Text>
      <TouchableRipple style={styles.field} onPress={open}>
        {values.length > 0 ? (
          <View style={styles.chipRow}>
            {displayValues.map((lbl, i) => (
              <Chip
                key={values[i]}
                style={styles.chip}
                onClose={() => removeChip(values[i])}
                compact
              >
                {lbl}
              </Chip>
            ))}
          </View>
        ) : (
          <Text style={styles.placeholderText}>{placeholder || 'Seleziona…'}</Text>
        )}
      </TouchableRipple>

      <Portal>
        <Modal visible={visible} onDismiss={close} contentContainerStyle={styles.modal}>
          <Text variant="titleMedium" style={styles.modalTitle}>
            {label}
          </Text>
          <Searchbar
            placeholder="Cerca o aggiungi…"
            value={query}
            onChangeText={setQuery}
            autoFocus
            style={styles.search}
          />
          <FlatList
            data={filtered}
            keyExtractor={(it) => it.id}
            keyboardShouldPersistTaps="handled"
            style={styles.list}
            ItemSeparatorComponent={Divider}
            renderItem={({ item }) => {
              const selected = values.includes(item.id);
              return (
                <List.Item
                  title={item.label}
                  onPress={() => toggle(item)}
                  titleStyle={styles.itemText}
                  left={(props) => (
                    <List.Icon
                      {...props}
                      icon={selected ? 'checkbox-marked' : 'checkbox-blank-outline'}
                    />
                  )}
                />
              );
            }}
          />
          {query.trim() !== '' && !exactMatch ? (
            <Button mode="contained" icon="plus" onPress={handleAdd} style={styles.addBtn}>
              Aggiungi: {query.trim()}
            </Button>
          ) : null}
          <Button mode="contained-tonal" onPress={close} style={styles.doneBtn}>
            Fatto ({values.length} selezionati)
          </Button>
        </Modal>
      </Portal>
    </View>
  );
}

const styles = StyleSheet.create({
  wrapper: { marginBottom: 12 },
  label: { color: colors.textSecondary, marginBottom: 4 },
  field: {
    backgroundColor: colors.surfaceVariant,
    borderColor: colors.border,
    borderWidth: 1,
    borderRadius: 8,
    paddingHorizontal: 12,
    paddingVertical: 12,
    minHeight: 48,
    justifyContent: 'center',
  },
  chipRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 6 },
  chip: { backgroundColor: colors.surface },
  placeholderText: { color: colors.textSecondary },
  modal: {
    backgroundColor: colors.surface,
    margin: 20,
    borderRadius: 12,
    padding: 16,
    maxHeight: '80%',
  },
  modalTitle: { color: colors.textPrimary, marginBottom: 12 },
  search: { backgroundColor: colors.surfaceVariant, marginBottom: 8 },
  list: { flexGrow: 0, maxHeight: 320 },
  itemText: { color: colors.textPrimary },
  addBtn: { marginTop: 8 },
  doneBtn: { marginTop: 4 },
});
