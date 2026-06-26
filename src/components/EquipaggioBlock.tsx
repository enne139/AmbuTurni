import React, { useEffect, useState } from 'react';
import { StyleSheet, View } from 'react-native';
import { Switch, Text } from 'react-native-paper';
import {
  addPersonaFromText,
  getPersone,
  getPersoneLookup,
  type EquipaggioFields,
  type LookupItem,
} from '../db/helpers';
import { colors } from '../utils/theme';
import SelectableField from './SelectableField';

interface EquipaggioBlockProps {
  value: EquipaggioFields;
  onChange: (value: EquipaggioFields) => void;
}

type EqKey = keyof EquipaggioFields;

const RUOLI: { key: string; label: string }[] = [
  { key: 'autista', label: 'Autista' },
  { key: 'cs', label: 'CS' },
  { key: 'terzo', label: 'Terzo' },
  { key: 'quarto', label: 'Quarto' },
  { key: 'centralinista', label: 'Centralinista' },
];

/** Blocco doppio equipaggio (1a parte + 2a parte opzionale). */
export default function EquipaggioBlock({ value, onChange }: EquipaggioBlockProps) {
  const [labels, setLabels] = useState<Record<string, string>>({});
  const [showSecond, setShowSecond] = useState<boolean>(false);

  // Carica la mappa id -> "Cognome Nome" per mostrare i valori selezionati.
  const refreshLabels = async () => {
    const persone = await getPersone();
    const map: Record<string, string> = {};
    persone.forEach((p) => {
      map[p.id] = `${p.cognome} ${p.nome}`.trim();
    });
    setLabels(map);
  };

  useEffect(() => {
    refreshLabels();
    // Mostra la 2a parte se ha già dei dati.
    const hasSecond =
      !!value.eq2_autista_id ||
      !!value.eq2_cs_id ||
      !!value.eq2_terzo_id ||
      !!value.eq2_quarto_id ||
      !!value.eq2_centralinista_id;
    if (hasSecond) setShowSecond(true);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const fetchItems = (): Promise<LookupItem[]> => getPersoneLookup();

  const handleAddNew = async (text: string): Promise<LookupItem> => {
    const created = await addPersonaFromText(text);
    setLabels((prev) => ({ ...prev, [created.id]: created.label }));
    return created;
  };

  const setField = (key: EqKey, id: string | null) => {
    onChange({ ...value, [key]: id });
  };

  const toggleSecond = (on: boolean) => {
    setShowSecond(on);
    if (!on) {
      onChange({
        ...value,
        eq2_autista_id: null,
        eq2_cs_id: null,
        eq2_terzo_id: null,
        eq2_quarto_id: null,
        eq2_centralinista_id: null,
      });
    }
  };

  const renderSection = (prefix: 'eq1' | 'eq2') => (
    <View>
      {RUOLI.map((ruolo) => {
        const key = `${prefix}_${ruolo.key}_id` as EqKey;
        const id = value[key];
        return (
          <SelectableField
            key={key}
            label={ruolo.label}
            value={id ?? undefined}
            displayValue={id ? labels[id] : undefined}
            fetchItems={fetchItems}
            onAddNew={handleAddNew}
            onSelect={(selId, selLabel) => {
              setLabels((prev) => ({ ...prev, [selId]: selLabel }));
              setField(key, selId);
            }}
            nullable
            onClear={() => setField(key, null)}
            placeholder="—"
          />
        );
      })}
    </View>
  );

  return (
    <View style={styles.wrapper}>
      <Text variant="titleMedium" style={styles.heading}>
        Equipaggio — 1ª parte
      </Text>
      {renderSection('eq1')}

      <View style={styles.switchRow}>
        <Text style={styles.switchLabel}>Cambio a metà turno</Text>
        <Switch value={showSecond} onValueChange={toggleSecond} color={colors.primary} />
      </View>

      {showSecond ? (
        <View>
          <Text variant="titleMedium" style={styles.heading}>
            Equipaggio — 2ª parte
          </Text>
          {renderSection('eq2')}
        </View>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  wrapper: { marginTop: 8 },
  heading: { color: colors.textPrimary, marginBottom: 8, marginTop: 8 },
  switchRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: 8,
  },
  switchLabel: { color: colors.textPrimary },
});
