import { useFocusEffect } from '@react-navigation/native';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import React, { useCallback, useEffect, useRef, useState } from 'react';
import { ScrollView, StyleSheet, View } from 'react-native';
import { Button, Card, Dialog, Divider, Portal, Text, TextInput } from 'react-native-paper';
import DateField from '../../components/DateField';
import EquipaggioBlock from '../../components/EquipaggioBlock';
import SelectableField from '../../components/SelectableField';
import {
  addAssociazione,
  deleteAssistenza,
  emptyEquipaggio,
  getAssistenzaById,
  getAssociazioniLookup,
  getPersone,
  previewProgressivoAssistenza,
  saveAssistenza,
  type AssistenzaInput,
  type AssistenzaRow,
  type EquipaggioFields,
} from '../../db/helpers';
import type { AssistenzeStackParamList } from '../../navigation/AppNavigator';
import { formatDate, formatOre, parseOre } from '../../utils/format';
import { colors } from '../../utils/theme';

// ===========================================================================
// FORM
// ===========================================================================

type FormProps = NativeStackScreenProps<AssistenzeStackParamList, 'AssistenzaForm'>;

export function AssistenzaFormScreen({ route, navigation }: FormProps) {
  const editId = route.params?.id;

  const [assistenzaId, setAssistenzaId] = useState<string | null>(editId ?? null);
  const [associazioneId, setAssociazioneId] = useState<string | null>(null);
  const [associazioneLabel, setAssociazioneLabel] = useState<string | undefined>(undefined);
  const [data, setData] = useState<string>(new Date().toISOString());
  const [oreText, setOreText] = useState('');
  const [progressivo, setProgressivo] = useState<number | null>(null);
  const [descrizione, setDescrizione] = useState('');
  const [note, setNote] = useState('');
  const [equipaggio, setEquipaggio] = useState<EquipaggioFields>(emptyEquipaggio());
  const [saving, setSaving] = useState(false);

  const isExisting = useRef<boolean>(!!editId);

  useEffect(() => {
    if (!editId) return;
    (async () => {
      const a = await getAssistenzaById(editId);
      if (!a) return;
      setAssociazioneId(a.associazione_id);
      setAssociazioneLabel(a.associazione_nome ?? undefined);
      setData(a.data);
      setOreText(a.ore !== null ? String(a.ore) : '');
      setProgressivo(a.numero_progressivo);
      setDescrizione(a.descrizione ?? '');
      setNote(a.note ?? '');
      setEquipaggio({
        eq1_autista_id: a.eq1_autista_id,
        eq1_cs_id: a.eq1_cs_id,
        eq1_terzo_id: a.eq1_terzo_id,
        eq1_quarto_id: a.eq1_quarto_id,
        eq1_centralinista_id: a.eq1_centralinista_id,
        eq2_autista_id: a.eq2_autista_id,
        eq2_cs_id: a.eq2_cs_id,
        eq2_terzo_id: a.eq2_terzo_id,
        eq2_quarto_id: a.eq2_quarto_id,
        eq2_centralinista_id: a.eq2_centralinista_id,
      });
    })();
  }, [editId]);

  useEffect(() => {
    if (isExisting.current) return;
    previewProgressivoAssistenza(associazioneId, data).then(setProgressivo);
  }, [associazioneId, data]);

  const handleSave = useCallback(async () => {
    if (!associazioneId) return;
    setSaving(true);
    try {
      const input: AssistenzaInput = {
        id: assistenzaId ?? undefined,
        associazione_id: associazioneId,
        data,
        ore: parseOre(oreText),
        descrizione: descrizione.trim() || null,
        note: note.trim() || null,
        ...equipaggio,
      };
      await saveAssistenza(input);
      navigation.goBack();
    } finally {
      setSaving(false);
    }
  }, [assistenzaId, associazioneId, data, oreText, descrizione, note, equipaggio, navigation]);

  return (
    <ScrollView
      style={styles.container}
      contentContainerStyle={styles.content}
      keyboardShouldPersistTaps="handled"
    >
      <SelectableField
        label="Associazione *"
        value={associazioneId ?? undefined}
        displayValue={associazioneLabel}
        fetchItems={getAssociazioniLookup}
        onAddNew={(t) => addAssociazione(t)}
        onSelect={(id, lbl) => {
          setAssociazioneId(id);
          setAssociazioneLabel(lbl);
        }}
        placeholder="Seleziona associazione"
      />

      <DateField label="Data" value={data} onChange={setData} />

      <TextInput
        label="Ore"
        value={oreText}
        onChangeText={setOreText}
        keyboardType="decimal-pad"
        mode="outlined"
        style={styles.input}
      />

      <View style={styles.readonlyBox}>
        <Text style={styles.readonlyLabel}>N° progressivo</Text>
        <Text style={styles.readonlyValue}>{progressivo ?? '—'}</Text>
      </View>

      <TextInput
        label="Descrizione"
        value={descrizione}
        onChangeText={setDescrizione}
        mode="outlined"
        multiline
        numberOfLines={4}
        style={[styles.input, styles.multiline]}
      />
      <TextInput
        label="Note"
        value={note}
        onChangeText={setNote}
        mode="outlined"
        multiline
        numberOfLines={4}
        style={[styles.input, styles.multiline]}
      />

      <Divider style={styles.divider} />
      <EquipaggioBlock value={equipaggio} onChange={setEquipaggio} />

      <Button
        mode="contained"
        onPress={handleSave}
        disabled={!associazioneId || saving}
        loading={saving}
        style={styles.saveBtn}
      >
        Salva assistenza
      </Button>
    </ScrollView>
  );
}

// ===========================================================================
// DETTAGLIO
// ===========================================================================

type DetailProps = NativeStackScreenProps<AssistenzeStackParamList, 'AssistenzaDetail'>;

const RUOLI: { key: keyof EquipaggioFields; label: string }[] = [
  { key: 'eq1_autista_id', label: 'Autista' },
  { key: 'eq1_cs_id', label: 'CS' },
  { key: 'eq1_terzo_id', label: 'Terzo' },
  { key: 'eq1_quarto_id', label: 'Quarto' },
  { key: 'eq1_centralinista_id', label: 'Centralinista' },
];
const RUOLI2: { key: keyof EquipaggioFields; label: string }[] = [
  { key: 'eq2_autista_id', label: 'Autista' },
  { key: 'eq2_cs_id', label: 'CS' },
  { key: 'eq2_terzo_id', label: 'Terzo' },
  { key: 'eq2_quarto_id', label: 'Quarto' },
  { key: 'eq2_centralinista_id', label: 'Centralinista' },
];

export function AssistenzaDetailScreen({ route, navigation }: DetailProps) {
  const { id } = route.params;
  const [assistenza, setAssistenza] = useState<AssistenzaRow | null>(null);
  const [persone, setPersone] = useState<Record<string, string>>({});
  const [confirmDelete, setConfirmDelete] = useState(false);

  const load = useCallback(async () => {
    const [a, p] = await Promise.all([getAssistenzaById(id), getPersone()]);
    setAssistenza(a);
    setPersone(Object.fromEntries(p.map((x) => [x.id, `${x.cognome} ${x.nome}`.trim()])));
  }, [id]);

  useFocusEffect(
    useCallback(() => {
      load();
    }, [load])
  );

  if (!assistenza) {
    return (
      <View style={styles.container}>
        <Text style={styles.empty}>Caricamento…</Text>
      </View>
    );
  }

  const hasSecond = RUOLI2.some((r) => assistenza[r.key]);

  const renderEquipaggio = (ruoli: typeof RUOLI) =>
    ruoli
      .filter((r) => assistenza[r.key])
      .map((r) => (
        <View key={r.key} style={styles.eqRow}>
          <Text style={styles.eqLabel}>{r.label}</Text>
          <Text style={styles.eqValue}>{persone[assistenza[r.key] as string] ?? '—'}</Text>
        </View>
      ));

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      <View style={styles.headerRow}>
        <Text variant="headlineSmall" style={styles.title}>
          {assistenza.associazione_nome ?? 'Senza associazione'}
        </Text>
        <Text style={styles.progressivo}>#{assistenza.numero_progressivo ?? '—'}</Text>
      </View>
      <Text style={styles.meta}>
        {formatDate(assistenza.data)} · {formatOre(assistenza.ore)}
      </Text>

      {assistenza.descrizione ? (
        <Card style={styles.block} mode="contained">
          <Card.Content>
            <Text style={styles.blockLabel}>Descrizione</Text>
            <Text style={styles.blockText}>{assistenza.descrizione}</Text>
          </Card.Content>
        </Card>
      ) : null}
      {assistenza.note ? (
        <Card style={styles.block} mode="contained">
          <Card.Content>
            <Text style={styles.blockLabel}>Note</Text>
            <Text style={styles.blockText}>{assistenza.note}</Text>
          </Card.Content>
        </Card>
      ) : null}

      <Text variant="titleMedium" style={styles.section}>
        Equipaggio — 1ª parte
      </Text>
      {renderEquipaggio(RUOLI)}
      {hasSecond ? (
        <>
          <Text variant="titleMedium" style={styles.section}>
            Equipaggio — 2ª parte
          </Text>
          {renderEquipaggio(RUOLI2)}
        </>
      ) : null}

      <Divider style={styles.divider} />
      <Button
        mode="contained"
        icon="pencil"
        onPress={() => navigation.navigate('AssistenzaForm', { id: assistenza.id })}
        style={styles.editBtnSecondary}
      >
        Modifica
      </Button>
      <Button
        mode="outlined"
        icon="delete"
        textColor="#F44336"
        onPress={() => setConfirmDelete(true)}
        style={styles.deleteBtn}
      >
        Elimina assistenza
      </Button>

      <Portal>
        <Dialog visible={confirmDelete} onDismiss={() => setConfirmDelete(false)}>
          <Dialog.Title>Elimina assistenza</Dialog.Title>
          <Dialog.Content>
            <Text>
              Eliminare l’assistenza #{assistenza.numero_progressivo} di{' '}
              {assistenza.associazione_nome ?? 'questa associazione'}?
            </Text>
          </Dialog.Content>
          <Dialog.Actions>
            <Button onPress={() => setConfirmDelete(false)}>Annulla</Button>
            <Button
              textColor="#F44336"
              onPress={async () => {
                await deleteAssistenza(assistenza.id);
                setConfirmDelete(false);
                navigation.goBack();
              }}
            >
              Elimina
            </Button>
          </Dialog.Actions>
        </Dialog>
      </Portal>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { padding: 16, paddingBottom: 48 },
  label: { color: colors.textSecondary, marginBottom: 4 },
  dateBtn: { marginBottom: 12, borderColor: colors.border },
  input: { marginBottom: 12, backgroundColor: colors.surface },
  multiline: { minHeight: 96 },
  readonlyBox: {
    backgroundColor: colors.surfaceVariant,
    borderRadius: 8,
    padding: 12,
    marginBottom: 12,
  },
  readonlyLabel: { color: colors.textSecondary, fontSize: 12 },
  readonlyValue: { color: colors.textPrimary, fontSize: 20, fontWeight: '700', marginTop: 2 },
  divider: { marginVertical: 16, backgroundColor: colors.border },
  saveBtn: { marginTop: 24, backgroundColor: colors.secondary },
  // dettaglio
  headerRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  title: { color: colors.textPrimary, flex: 1 },
  progressivo: { color: colors.secondary, fontWeight: '700', fontSize: 18 },
  meta: { color: colors.textSecondary, marginTop: 4 },
  block: { backgroundColor: colors.surface, marginTop: 12 },
  blockLabel: { color: colors.textSecondary, fontSize: 12, marginBottom: 4 },
  blockText: { color: colors.textPrimary },
  section: { color: colors.textPrimary, marginTop: 20, marginBottom: 8 },
  eqRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingVertical: 6,
    borderBottomWidth: StyleSheet.hairlineWidth,
    borderBottomColor: colors.border,
  },
  eqLabel: { color: colors.textSecondary },
  eqValue: { color: colors.textPrimary },
  empty: { color: colors.textSecondary, textAlign: 'center', marginTop: 48 },
  editBtnSecondary: { backgroundColor: colors.secondary },
  deleteBtn: { marginTop: 12, borderColor: '#F44336' },
});
