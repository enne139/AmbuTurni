import React, { useState } from 'react';
import { StyleSheet, View } from 'react-native';
import { Button, Text, TextInput, TouchableRipple } from 'react-native-paper';
import {
  addOspedale,
  getOspedaliLookup,
  type CodiceChiamata,
  type CodiceUscita,
} from '../db/helpers';
import { colors, getCodiceColor } from '../utils/theme';
import SelectableField from './SelectableField';

const CODICI_CHIAMATA: CodiceChiamata[] = ['VERDE', 'GIALLO', 'ROSSO', 'DIMISSIONE'];
const CODICI_USCITA: CodiceUscita[] = ['VERDE', 'GIALLO', 'ROSSO', 'NERO', 'VUOTO', 'RIFIUTO'];

export interface ServizioInitial {
  codiceChiamata: CodiceChiamata | null;
  codiceUscita: CodiceUscita | null;
  ospedaleId: string | null;
  ospedaleLabel?: string;
  descrizione: string | null;
}

interface ServizioFormProps {
  title: string;
  submitLabel: string;
  initial?: ServizioInitial;
  onSubmit: (
    codiceChiamata: CodiceChiamata,
    codiceUscita: CodiceUscita,
    ospedaleId: string | null,
    descrizione: string | null
  ) => Promise<void>;
  onCancel: () => void;
}

/** Form per creare o modificare un servizio (codici, ospedale, descrizione). */
export default function ServizioForm({
  title,
  submitLabel,
  initial,
  onSubmit,
  onCancel,
}: ServizioFormProps) {
  const [chiamata, setChiamata] = useState<CodiceChiamata | null>(initial?.codiceChiamata ?? null);
  const [uscita, setUscita] = useState<CodiceUscita | null>(initial?.codiceUscita ?? null);
  const [ospedaleId, setOspedaleId] = useState<string | null>(initial?.ospedaleId ?? null);
  const [ospedaleLabel, setOspedaleLabel] = useState<string | undefined>(initial?.ospedaleLabel);
  const [descrizione, setDescrizione] = useState(initial?.descrizione ?? '');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const canSave = chiamata !== null && uscita !== null && !saving;

  const submit = async () => {
    if (!chiamata || !uscita) return;
    setSaving(true);
    setError(null);
    try {
      await onSubmit(chiamata, uscita, ospedaleId, descrizione.trim() || null);
    } catch (e) {
      setError('Operazione non riuscita. Riprova.');
      console.warn('[servizio] submit error:', e);
    } finally {
      setSaving(false);
    }
  };

  return (
    <View>
      <Text variant="titleMedium" style={styles.title}>
        {title}
      </Text>

      <Text variant="labelMedium" style={styles.label}>
        Codice chiamata
      </Text>
      <View style={styles.toggleRow}>
        {CODICI_CHIAMATA.map((c) => (
          <Toggle
            key={c}
            label={c}
            color={getCodiceColor(c)}
            selected={chiamata === c}
            onPress={() => setChiamata(c)}
          />
        ))}
      </View>

      <Text variant="labelMedium" style={styles.label}>
        Codice uscita
      </Text>
      <View style={styles.toggleRow}>
        {CODICI_USCITA.map((c) => (
          <Toggle
            key={c}
            label={c}
            color={getCodiceColor(c)}
            selected={uscita === c}
            onPress={() => setUscita(c)}
          />
        ))}
      </View>

      <View style={styles.ospedaleField}>
        <SelectableField
          label="Ospedale"
          value={ospedaleId ?? undefined}
          displayValue={ospedaleLabel}
          fetchItems={getOspedaliLookup}
          onAddNew={(t) => addOspedale(t)}
          onSelect={(id, lbl) => {
            setOspedaleId(id);
            setOspedaleLabel(lbl);
          }}
          nullable
          onClear={() => {
            setOspedaleId(null);
            setOspedaleLabel(undefined);
          }}
          placeholder="—"
        />
      </View>

      <TextInput
        label="Descrizione"
        value={descrizione}
        onChangeText={setDescrizione}
        mode="outlined"
        multiline
        numberOfLines={4}
        style={styles.descrizioneInput}
      />

      {error ? <Text style={styles.error}>{error}</Text> : null}
      {!canSave && !saving ? (
        <Text style={styles.hint}>Seleziona codice chiamata e codice uscita.</Text>
      ) : null}

      <Button
        mode="contained"
        onPress={submit}
        disabled={!canSave}
        loading={saving}
        style={styles.submitBtn}
      >
        {submitLabel}
      </Button>
      <Button onPress={onCancel}>Annulla</Button>
    </View>
  );
}

interface ToggleProps {
  label: string;
  color: string;
  selected: boolean;
  onPress: () => void;
}

function Toggle({ label, color, selected, onPress }: ToggleProps) {
  return (
    <TouchableRipple
      onPress={onPress}
      style={[styles.toggle, { borderColor: color }, selected ? { backgroundColor: color } : null]}
    >
      <Text style={[styles.toggleText, selected ? styles.toggleTextSelected : { color }]}>
        {label}
      </Text>
    </TouchableRipple>
  );
}

const styles = StyleSheet.create({
  title: { color: colors.textPrimary, marginBottom: 12 },
  label: { color: colors.textSecondary, marginTop: 8, marginBottom: 6 },
  toggleRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  toggle: {
    borderWidth: 2,
    borderRadius: 8,
    paddingHorizontal: 14,
    paddingVertical: 8,
    marginBottom: 4,
  },
  toggleText: { fontWeight: '700' },
  toggleTextSelected: { color: '#000000' },
  ospedaleField: { marginTop: 16 },
  descrizioneInput: { marginTop: 16, backgroundColor: colors.surface, minHeight: 96 },
  error: { color: '#F44336', marginTop: 12 },
  hint: { color: colors.textSecondary, fontStyle: 'italic', marginTop: 8, marginBottom: 4 },
  submitBtn: { marginTop: 12 },
});
