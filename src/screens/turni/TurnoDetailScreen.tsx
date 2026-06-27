import { useFocusEffect } from '@react-navigation/native';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import React, { useCallback, useState } from 'react';
import { ScrollView, StyleSheet, View } from 'react-native';
import { Button, Card, Dialog, Divider, Portal, Text } from 'react-native-paper';
import ServiziManager from '../../components/ServiziManager';
import {
  deleteTurno,
  getPersone,
  getTipologieTurnoLookup,
  getTurnoById,
  type EquipaggioFields,
  type TurnoRow,
} from '../../db/helpers';
import type { TurniStackParamList } from '../../navigation/AppNavigator';
import { formatDate, formatOre } from '../../utils/format';
import { colors } from '../../utils/theme';

type Props = NativeStackScreenProps<TurniStackParamList, 'TurnoDetail'>;

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

export default function TurnoDetailScreen({ route, navigation }: Props) {
  const { id } = route.params;
  const [turno, setTurno] = useState<TurnoRow | null>(null);
  const [persone, setPersone] = useState<Record<string, string>>({});
  const [tipologie, setTipologie] = useState<Record<string, string>>({});
  const [confirmDelete, setConfirmDelete] = useState(false);

  const load = useCallback(async () => {
    const [t, p, tip] = await Promise.all([
      getTurnoById(id),
      getPersone(),
      getTipologieTurnoLookup(),
    ]);
    setTurno(t);
    setPersone(Object.fromEntries(p.map((x) => [x.id, `${x.cognome} ${x.nome}`.trim()])));
    setTipologie(Object.fromEntries(tip.map((x) => [x.id, x.label])));
  }, [id]);

  useFocusEffect(
    useCallback(() => {
      load();
    }, [load])
  );

  if (!turno) {
    return (
      <View style={styles.container}>
        <Text style={styles.empty}>Caricamento…</Text>
      </View>
    );
  }

  const extra: string[] = JSON.parse(turno.tipologie_extra || '[]');
  const tipologieAll = [turno.tipologia_id, ...extra]
    .filter((x): x is string => !!x)
    .map((tid) => tipologie[tid] ?? '?');

  const hasSecond = RUOLI2.some((r) => turno[r.key]);

  const renderEquipaggio = (ruoli: typeof RUOLI) =>
    ruoli
      .filter((r) => turno[r.key])
      .map((r) => (
        <View key={r.key} style={styles.eqRow}>
          <Text style={styles.eqLabel}>{r.label}</Text>
          <Text style={styles.eqValue}>{persone[turno[r.key] as string] ?? '—'}</Text>
        </View>
      ));

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      <View style={styles.headerRow}>
        <Text variant="headlineSmall" style={styles.title}>
          {turno.associazione_nome ?? 'Senza associazione'}
        </Text>
        <Text style={styles.progressivo}>#{turno.numero_progressivo ?? '—'}</Text>
      </View>
      <Text style={styles.meta}>
        {formatDate(turno.data)} · {formatOre(turno.ore)}
      </Text>
      {tipologieAll.length > 0 ? (
        <Text style={styles.meta}>Tipo: {tipologieAll.join(', ')}</Text>
      ) : null}

      {turno.descrizione ? (
        <Card style={styles.block} mode="contained">
          <Card.Content>
            <Text style={styles.blockLabel}>Descrizione</Text>
            <Text style={styles.blockText}>{turno.descrizione}</Text>
          </Card.Content>
        </Card>
      ) : null}
      {turno.note ? (
        <Card style={styles.block} mode="contained">
          <Card.Content>
            <Text style={styles.blockLabel}>Note</Text>
            <Text style={styles.blockText}>{turno.note}</Text>
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
      <ServiziManager turnoId={id} onChanged={load} />

      <Divider style={styles.divider} />
      <Button
        mode="contained"
        icon="pencil"
        onPress={() => navigation.navigate('TurnoForm', { id: turno.id })}
        style={styles.editBtn}
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
        Elimina turno
      </Button>

      <Portal>
        <Dialog visible={confirmDelete} onDismiss={() => setConfirmDelete(false)}>
          <Dialog.Title>Elimina turno</Dialog.Title>
          <Dialog.Content>
            <Text>
              Eliminare il turno #{turno.numero_progressivo} di{' '}
              {turno.associazione_nome ?? 'questa associazione'}? Verranno eliminati anche tutti
              i suoi servizi.
            </Text>
          </Dialog.Content>
          <Dialog.Actions>
            <Button onPress={() => setConfirmDelete(false)}>Annulla</Button>
            <Button
              textColor="#F44336"
              onPress={async () => {
                await deleteTurno(turno.id);
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
  headerRow: { flexDirection: 'row', justifyContent: 'space-between', alignItems: 'center' },
  title: { color: colors.textPrimary, flex: 1 },
  progressivo: { color: colors.primary, fontWeight: '700', fontSize: 18 },
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
  servCard: { backgroundColor: colors.surfaceVariant, marginBottom: 8, overflow: 'hidden' },
  servRow: { flexDirection: 'row', alignItems: 'center' },
  stripe: { width: 6, alignSelf: 'stretch' },
  servBody: { flex: 1, padding: 12 },
  badgeRow: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  badge: { borderRadius: 6, paddingHorizontal: 8, paddingVertical: 2 },
  badgeText: { color: '#000000', fontWeight: '700', fontSize: 12 },
  arrow: { color: colors.textSecondary, fontSize: 16 },
  ospedale: { color: colors.textSecondary, marginTop: 6 },
  servDescrizione: { color: colors.textPrimary, marginTop: 6 },
  empty: { color: colors.textSecondary, textAlign: 'center', marginTop: 12 },
  divider: { marginVertical: 20, backgroundColor: colors.border },
  editBtn: { backgroundColor: colors.primary },
  deleteBtn: { marginTop: 12, borderColor: '#F44336' },
});
