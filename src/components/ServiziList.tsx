import React, { useCallback, useEffect, useState } from 'react';
import { StyleSheet, View } from 'react-native';
import {
  Button,
  Card,
  IconButton,
  Modal,
  Portal,
  Text,
  TouchableRipple,
} from 'react-native-paper';
import {
  addOspedale,
  addServizio,
  deleteServizio,
  getOspedaliLookup,
  getServiziByTurno,
  type CodiceChiamata,
  type CodiceUscita,
  type LookupItem,
  type ServizioRow,
} from '../db/helpers';
import { colors, getCodiceColor } from '../utils/theme';
import SelectableField from './SelectableField';

interface ServiziListProps {
  turnoId: string | null;
  /** Salva il turno (se nuovo) e restituisce l'id da usare per i servizi. */
  ensureTurnoId: () => Promise<string>;
  onServiziChanged?: (count: number) => void;
}

const CODICI_CHIAMATA: CodiceChiamata[] = ['VERDE', 'GIALLO', 'ROSSO'];
const CODICI_USCITA: CodiceUscita[] = ['verde', 'giallo', 'rosso', 'nero', 'vuoto', 'rifiuta'];

export default function ServiziList({
  turnoId,
  ensureTurnoId,
  onServiziChanged,
}: ServiziListProps) {
  const [servizi, setServizi] = useState<ServizioRow[]>([]);
  const [formVisible, setFormVisible] = useState(false);

  const load = useCallback(async () => {
    if (!turnoId) {
      setServizi([]);
      return;
    }
    const rows = await getServiziByTurno(turnoId);
    setServizi(rows);
    onServiziChanged?.(rows.length);
  }, [turnoId, onServiziChanged]);

  useEffect(() => {
    load();
  }, [load]);

  const handleAdd = useCallback(
    async (
      codiceChiamata: CodiceChiamata,
      codiceUscita: CodiceUscita,
      ospedaleId: string | null
    ) => {
      const id = await ensureTurnoId();
      await addServizio(id, codiceChiamata, codiceUscita, ospedaleId);
      setFormVisible(false);
      const rows = await getServiziByTurno(id);
      setServizi(rows);
      onServiziChanged?.(rows.length);
    },
    [ensureTurnoId, onServiziChanged]
  );

  const handleDelete = useCallback(
    async (servizioId: string) => {
      if (!turnoId) return;
      await deleteServizio(servizioId, turnoId);
      await load();
    },
    [turnoId, load]
  );

  return (
    <View style={styles.wrapper}>
      <View style={styles.header}>
        <Text variant="titleMedium" style={styles.heading}>
          Servizi ({servizi.length})
        </Text>
        <Button mode="contained-tonal" icon="plus" onPress={() => setFormVisible(true)} compact>
          Aggiungi
        </Button>
      </View>

      {servizi.map((s) => (
        <Card key={s.id} style={styles.card} mode="contained">
          <View style={styles.cardRow}>
            <View
              style={[styles.stripe, { backgroundColor: getCodiceColor(s.codice_chiamata) }]}
            />
            <View style={styles.cardBody}>
              <View style={styles.badgeRow}>
                <View
                  style={[styles.badge, { backgroundColor: getCodiceColor(s.codice_chiamata) }]}
                >
                  <Text style={styles.badgeText}>{s.codice_chiamata}</Text>
                </View>
                <Text style={styles.arrow}>→</Text>
                <View style={[styles.badge, { backgroundColor: getCodiceColor(s.codice_uscita) }]}>
                  <Text style={styles.badgeText}>{s.codice_uscita?.toUpperCase()}</Text>
                </View>
              </View>
              {s.ospedale_nome ? (
                <Text style={styles.ospedale}>🏥 {s.ospedale_nome}</Text>
              ) : null}
            </View>
            <IconButton icon="delete" size={20} onPress={() => handleDelete(s.id)} />
          </View>
        </Card>
      ))}

      {servizi.length === 0 ? (
        <Text style={styles.empty}>Nessun servizio registrato.</Text>
      ) : null}

      <Portal>
        <Modal
          visible={formVisible}
          onDismiss={() => setFormVisible(false)}
          contentContainerStyle={styles.modal}
        >
          <ServizioForm onAdd={handleAdd} onCancel={() => setFormVisible(false)} />
        </Modal>
      </Portal>
    </View>
  );
}

interface ServizioFormProps {
  onAdd: (
    codiceChiamata: CodiceChiamata,
    codiceUscita: CodiceUscita,
    ospedaleId: string | null
  ) => Promise<void>;
  onCancel: () => void;
}

function ServizioForm({ onAdd, onCancel }: ServizioFormProps) {
  const [chiamata, setChiamata] = useState<CodiceChiamata | null>(null);
  const [uscita, setUscita] = useState<CodiceUscita | null>(null);
  const [ospedaleId, setOspedaleId] = useState<string | null>(null);
  const [ospedaleLabel, setOspedaleLabel] = useState<string | undefined>(undefined);
  const [saving, setSaving] = useState(false);

  const canSave = chiamata !== null && uscita !== null && !saving;

  const submit = async () => {
    if (!chiamata || !uscita) return;
    setSaving(true);
    try {
      await onAdd(chiamata, uscita, ospedaleId);
    } finally {
      setSaving(false);
    }
  };

  return (
    <View>
      <Text variant="titleMedium" style={styles.modalTitle}>
        Nuovo servizio
      </Text>

      <Text variant="labelMedium" style={styles.formLabel}>
        Codice chiamata
      </Text>
      <View style={styles.toggleRow}>
        {CODICI_CHIAMATA.map((c) => (
          <ToggleButton
            key={c}
            label={c}
            color={getCodiceColor(c)}
            selected={chiamata === c}
            onPress={() => setChiamata(c)}
          />
        ))}
      </View>

      <Text variant="labelMedium" style={styles.formLabel}>
        Codice uscita
      </Text>
      <View style={styles.toggleRow}>
        {CODICI_USCITA.map((c) => (
          <ToggleButton
            key={c}
            label={c.charAt(0).toUpperCase() + c.slice(1)}
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

      <Button mode="contained" onPress={submit} disabled={!canSave} style={styles.submitBtn}>
        Aggiungi servizio
      </Button>
      <Button onPress={onCancel}>Annulla</Button>
    </View>
  );
}

interface ToggleButtonProps {
  label: string;
  color: string;
  selected: boolean;
  onPress: () => void;
}

function ToggleButton({ label, color, selected, onPress }: ToggleButtonProps) {
  return (
    <TouchableRipple
      onPress={onPress}
      style={[
        styles.toggle,
        { borderColor: color },
        selected ? { backgroundColor: color } : null,
      ]}
    >
      <Text style={[styles.toggleText, selected ? styles.toggleTextSelected : { color }]}>
        {label}
      </Text>
    </TouchableRipple>
  );
}

const styles = StyleSheet.create({
  wrapper: { marginTop: 16 },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 8,
  },
  heading: { color: colors.textPrimary },
  card: { backgroundColor: colors.surfaceVariant, marginBottom: 8, overflow: 'hidden' },
  cardRow: { flexDirection: 'row', alignItems: 'center' },
  stripe: { width: 6, alignSelf: 'stretch' },
  cardBody: { flex: 1, paddingVertical: 10, paddingHorizontal: 12 },
  badgeRow: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  badge: { borderRadius: 6, paddingHorizontal: 8, paddingVertical: 2 },
  badgeText: { color: '#000000', fontWeight: '700', fontSize: 12 },
  arrow: { color: colors.textSecondary, fontSize: 16 },
  ospedale: { color: colors.textSecondary, marginTop: 6 },
  empty: { color: colors.textSecondary, textAlign: 'center', paddingVertical: 12 },
  modal: {
    backgroundColor: colors.surface,
    margin: 20,
    borderRadius: 12,
    padding: 16,
  },
  modalTitle: { color: colors.textPrimary, marginBottom: 12 },
  formLabel: { color: colors.textSecondary, marginTop: 8, marginBottom: 6 },
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
  submitBtn: { marginTop: 16 },
});
