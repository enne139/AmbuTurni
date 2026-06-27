import React, { useCallback, useMemo, useState } from 'react';
import { FlatList, StyleSheet, View } from 'react-native';
import {
  Button,
  Divider,
  IconButton,
  List,
  Modal,
  Portal,
  Searchbar,
  Text,
  TouchableRipple,
} from 'react-native-paper';
import type { LookupItem } from '../db/helpers';
import { colors } from '../utils/theme';

export interface SelectableFieldProps {
  label: string;
  value?: string;
  displayValue?: string;
  onSelect: (id: string, label: string) => void;
  onClear?: () => void;
  fetchItems: () => Promise<LookupItem[]>;
  onAddNew: (text: string) => Promise<LookupItem>;
  nullable?: boolean;
  placeholder?: string;
}

/**
 * Campo "####": al tap apre un modal con ricerca e lista filtrata.
 * Se la ricerca non trova corrispondenza esatta, mostra "Aggiungi: [testo]".
 */
export default function SelectableField({
  label,
  value,
  displayValue,
  onSelect,
  onClear,
  fetchItems,
  onAddNew,
  nullable,
  placeholder,
}: SelectableFieldProps) {
  const [visible, setVisible] = useState(false); // modal aperto?
  const [query, setQuery] = useState(''); // testo di ricerca
  const [items, setItems] = useState<LookupItem[]>([]); // valori caricati dal DB
  const [loading, setLoading] = useState(false);

  // Apre il modal e (ri)carica la lista dei valori dal DB.
  const open = useCallback(async () => {
    setQuery('');
    setVisible(true);
    setLoading(true);
    try {
      setItems(await fetchItems());
    } finally {
      setLoading(false);
    }
  }, [fetchItems]);

  const close = useCallback(() => setVisible(false), []);

  // Lista filtrata in base al testo di ricerca (case-insensitive).
  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return items;
    return items.filter((it) => it.label.toLowerCase().includes(q));
  }, [items, query]);

  // True se la ricerca corrisponde esattamente a un valore già esistente:
  // in tal caso non mostriamo il bottone "Aggiungi: …".
  const exactMatch = useMemo(
    () => items.some((it) => it.label.toLowerCase() === query.trim().toLowerCase()),
    [items, query]
  );

  // Seleziona un valore esistente e chiude.
  const handleSelect = useCallback(
    (item: LookupItem) => {
      onSelect(item.id, item.label);
      close();
    },
    [onSelect, close]
  );

  // Crea un nuovo valore nel DB lookup, lo seleziona e chiude.
  const handleAdd = useCallback(async () => {
    const text = query.trim();
    if (!text) return;
    const created = await onAddNew(text);
    onSelect(created.id, created.label);
    close();
  }, [query, onAddNew, onSelect, close]);

  return (
    <View style={styles.wrapper}>
      <Text variant="labelMedium" style={styles.label}>
        {label}
      </Text>
      <View style={styles.fieldRow}>
        <TouchableRipple style={styles.field} onPress={open} borderless={false}>
          <Text style={value ? styles.valueText : styles.placeholderText} numberOfLines={1}>
            {displayValue || placeholder || 'Seleziona…'}
          </Text>
        </TouchableRipple>
        {nullable && value && onClear ? (
          <IconButton icon="close" size={18} onPress={onClear} style={styles.clearBtn} />
        ) : null}
      </View>

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
            renderItem={({ item }) => (
              <List.Item
                title={item.label}
                onPress={() => handleSelect(item)}
                titleStyle={styles.itemText}
                right={(props) =>
                  item.id === value ? <List.Icon {...props} icon="check" /> : null
                }
              />
            )}
            ListEmptyComponent={
              !loading && query.trim() === '' ? (
                <Text style={styles.empty}>Nessun valore. Digita per aggiungerne uno.</Text>
              ) : null
            }
          />
          {query.trim() !== '' && !exactMatch ? (
            <Button mode="contained" icon="plus" onPress={handleAdd} style={styles.addBtn}>
              Aggiungi: {query.trim()}
            </Button>
          ) : null}
          <Button onPress={close} style={styles.closeBtn}>
            Chiudi
          </Button>
        </Modal>
      </Portal>
    </View>
  );
}

const styles = StyleSheet.create({
  wrapper: { marginBottom: 12 },
  label: { color: colors.textSecondary, marginBottom: 4 },
  fieldRow: { flexDirection: 'row', alignItems: 'center' },
  field: {
    flex: 1,
    backgroundColor: colors.surfaceVariant,
    borderColor: colors.border,
    borderWidth: 1,
    borderRadius: 8,
    paddingHorizontal: 12,
    paddingVertical: 14,
  },
  valueText: { color: colors.textPrimary },
  placeholderText: { color: colors.textSecondary },
  clearBtn: { margin: 0 },
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
  empty: { color: colors.textSecondary, textAlign: 'center', padding: 24 },
  addBtn: { marginTop: 8 },
  closeBtn: { marginTop: 4 },
});
