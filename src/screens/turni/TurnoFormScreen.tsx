import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import React, { useCallback, useEffect, useRef, useState } from 'react';
import { ScrollView, StyleSheet, View } from 'react-native';
import { Button, Divider, Text, TextInput } from 'react-native-paper';
import DateField from '../../components/DateField';
import EquipaggioBlock from '../../components/EquipaggioBlock';
import MultiSelectableField from '../../components/MultiSelectableField';
import SelectableField from '../../components/SelectableField';
import {
  addAssociazione,
  addTipologiaTurno,
  emptyEquipaggio,
  getAssociazioniLookup,
  getTipologieTurnoLookup,
  getTurnoById,
  previewProgressivoTurno,
  saveTurno,
  type EquipaggioFields,
  type TurnoInput,
} from '../../db/helpers';
import type { TurniStackParamList } from '../../navigation/AppNavigator';
import { parseOre } from '../../utils/format';
import { colors } from '../../utils/theme';

type Props = NativeStackScreenProps<TurniStackParamList, 'TurnoForm'>;

/**
 * Form di creazione/modifica turno. I servizi NON si gestiscono qui ma nel
 * dettaglio: dopo aver salvato un turno nuovo si naviga al dettaglio.
 */
export default function TurnoFormScreen({ route, navigation }: Props) {
  const editId = route.params?.id; // presente → modifica; assente → nuovo

  const [turnoId, setTurnoId] = useState<string | null>(editId ?? null);
  const [associazioneId, setAssociazioneId] = useState<string | null>(null);
  const [associazioneLabel, setAssociazioneLabel] = useState<string | undefined>(undefined);
  const [data, setData] = useState<string>(new Date().toISOString());
  const [oreText, setOreText] = useState(''); // ore come testo (decimale)
  // "Tipo turno" è multi-valore: array paralleli di id e label.
  const [tipoIds, setTipoIds] = useState<string[]>([]);
  const [tipoLabels, setTipoLabels] = useState<string[]>([]);
  const [progressivo, setProgressivo] = useState<number | null>(null); // anteprima sola lettura
  const [numServizi, setNumServizi] = useState(0);
  const [descrizione, setDescrizione] = useState('');
  const [note, setNote] = useState('');
  const [equipaggio, setEquipaggio] = useState<EquipaggioFields>(emptyEquipaggio());
  const [saving, setSaving] = useState(false);

  // True se stiamo modificando un turno esistente: evita di ricalcolare l'anteprima del progressivo.
  const isExisting = useRef<boolean>(!!editId);

  // Carica il turno esistente (in modifica).
  useEffect(() => {
    if (!editId) return;
    (async () => {
      const t = await getTurnoById(editId);
      if (!t) return;
      setAssociazioneId(t.associazione_id);
      setAssociazioneLabel(t.associazione_nome ?? undefined);
      setData(t.data);
      setOreText(t.ore !== null ? String(t.ore) : '');
      setProgressivo(t.numero_progressivo);
      setNumServizi(t.num_servizi);
      setDescrizione(t.descrizione ?? '');
      setNote(t.note ?? '');
      setEquipaggio({
        eq1_autista_id: t.eq1_autista_id,
        eq1_cs_id: t.eq1_cs_id,
        eq1_terzo_id: t.eq1_terzo_id,
        eq1_quarto_id: t.eq1_quarto_id,
        eq1_centralinista_id: t.eq1_centralinista_id,
        eq2_autista_id: t.eq2_autista_id,
        eq2_cs_id: t.eq2_cs_id,
        eq2_terzo_id: t.eq2_terzo_id,
        eq2_quarto_id: t.eq2_quarto_id,
        eq2_centralinista_id: t.eq2_centralinista_id,
      });

      // Ricostruisce le tipologie selezionate (tipologia_id + extra).
      const extra: string[] = JSON.parse(t.tipologie_extra || '[]');
      const allIds = [t.tipologia_id, ...extra].filter((x): x is string => !!x);
      const lookup = await getTipologieTurnoLookup();
      const map = new Map(lookup.map((l) => [l.id, l.label]));
      setTipoIds(allIds);
      setTipoLabels(allIds.map((id) => map.get(id) ?? '?'));
    })();
  }, [editId]);

  // Anteprima del progressivo (rango per data) quando cambia associazione o data (solo nuovi).
  useEffect(() => {
    if (isExisting.current) return;
    previewProgressivoTurno(associazioneId, data).then(setProgressivo);
  }, [associazioneId, data]);

  // Costruisce l'oggetto da salvare. Le tipologie selezionate (multi) sono mappate
  // sullo schema: la prima va in tipologia_id, le restanti in tipologie_extra.
  const buildInput = useCallback(
    (): TurnoInput => ({
      id: turnoId ?? undefined,
      associazione_id: associazioneId,
      data,
      ore: parseOre(oreText),
      tipologia_id: tipoIds[0] ?? null,
      tipologie_extra: tipoIds.slice(1),
      descrizione: descrizione.trim() || null,
      note: note.trim() || null,
      ...equipaggio,
    }),
    [turnoId, associazioneId, data, oreText, tipoIds, descrizione, note, equipaggio]
  );

  const handleSave = useCallback(async () => {
    if (!associazioneId) return;
    setSaving(true);
    try {
      const savedId = await saveTurno(buildInput());
      if (editId) {
        // Modifica di un turno esistente: torna al dettaglio.
        navigation.goBack();
      } else {
        // Nuovo turno: vai al dettaglio per gestire i servizi.
        navigation.replace('TurnoDetail', { id: savedId });
      }
    } finally {
      setSaving(false);
    }
  }, [associazioneId, buildInput, navigation, editId]);

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

      <MultiSelectableField
        label="Tipo turno"
        values={tipoIds}
        displayValues={tipoLabels}
        onChange={(ids, labels) => {
          setTipoIds(ids);
          setTipoLabels(labels);
        }}
        fetchItems={getTipologieTurnoLookup}
        onAddNew={(t) => addTipologiaTurno(t)}
        placeholder="Seleziona tipologie"
      />

      <View style={styles.readonlyRow}>
        <View style={styles.readonlyBox}>
          <Text style={styles.readonlyLabel}>N° progressivo</Text>
          <Text style={styles.readonlyValue}>{progressivo ?? '—'}</Text>
        </View>
        <View style={styles.readonlyBox}>
          <Text style={styles.readonlyLabel}>N° servizi</Text>
          <Text style={styles.readonlyValue}>{numServizi}</Text>
        </View>
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

      <Divider style={styles.divider} />
      <Text style={styles.serviziHint}>
        {editId
          ? 'I servizi si gestiscono dalla schermata di dettaglio del turno.'
          : 'Dopo aver salvato potrai aggiungere e ordinare i servizi nella schermata di dettaglio.'}
      </Text>

      <Button
        mode="contained"
        onPress={handleSave}
        disabled={!associazioneId || saving}
        loading={saving}
        style={styles.saveBtn}
      >
        Salva turno
      </Button>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { padding: 16, paddingBottom: 48 },
  label: { color: colors.textSecondary, marginBottom: 4 },
  input: { marginBottom: 12, backgroundColor: colors.surface },
  multiline: { minHeight: 96 },
  serviziHint: { color: colors.textSecondary, fontStyle: 'italic', marginBottom: 4 },
  readonlyRow: { flexDirection: 'row', gap: 12, marginBottom: 12 },
  readonlyBox: {
    flex: 1,
    backgroundColor: colors.surfaceVariant,
    borderRadius: 8,
    padding: 12,
  },
  readonlyLabel: { color: colors.textSecondary, fontSize: 12 },
  readonlyValue: { color: colors.textPrimary, fontSize: 20, fontWeight: '700', marginTop: 2 },
  divider: { marginVertical: 16, backgroundColor: colors.border },
  saveBtn: { marginTop: 24, backgroundColor: colors.primary },
});
