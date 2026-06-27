import React, { useCallback, useEffect, useState } from 'react';
import { StyleSheet, View } from 'react-native';
import { Button, Card, IconButton, Text } from 'react-native-paper';
import {
  addServizio,
  deleteServizio,
  getServiziByTurno,
  moveServizio,
  ospedaleLabel,
  updateServizio,
  type CodiceChiamata,
  type CodiceUscita,
  type ServizioRow,
} from '../db/helpers';
import { colors, getCodiceColor } from '../utils/theme';
import ServizioForm from './ServizioForm';

interface ServiziManagerProps {
  turnoId: string;
  onChanged?: () => void;
}

type Mode = { type: 'none' } | { type: 'add' } | { type: 'edit'; id: string };

/** Gestione completa dei servizi di un turno: lista, aggiunta, modifica, riordino. */
export default function ServiziManager({ turnoId, onChanged }: ServiziManagerProps) {
  const [servizi, setServizi] = useState<ServizioRow[]>([]);
  const [mode, setMode] = useState<Mode>({ type: 'none' });

  const load = useCallback(async () => {
    setServizi(await getServiziByTurno(turnoId));
  }, [turnoId]);

  useEffect(() => {
    load();
  }, [load]);

  const refresh = useCallback(async () => {
    await load();
    onChanged?.();
  }, [load, onChanged]);

  const handleAdd = useCallback(
    async (
      c: CodiceChiamata,
      u: CodiceUscita,
      ospedaleId: string | null,
      descrizione: string | null
    ) => {
      await addServizio(turnoId, c, u, ospedaleId, descrizione);
      setMode({ type: 'none' });
      await refresh();
    },
    [turnoId, refresh]
  );

  const handleEdit = useCallback(
    async (
      servizioId: string,
      c: CodiceChiamata,
      u: CodiceUscita,
      ospedaleId: string | null,
      descrizione: string | null
    ) => {
      await updateServizio(servizioId, c, u, ospedaleId, descrizione);
      setMode({ type: 'none' });
      await refresh();
    },
    [refresh]
  );

  const handleDelete = useCallback(
    async (servizioId: string) => {
      await deleteServizio(servizioId, turnoId);
      await refresh();
    },
    [turnoId, refresh]
  );

  const handleMove = useCallback(
    async (servizioId: string, direction: 'up' | 'down') => {
      await moveServizio(turnoId, servizioId, direction);
      await refresh();
    },
    [turnoId, refresh]
  );

  const formOpen = mode.type !== 'none';

  return (
    <View style={styles.wrapper}>
      <View style={styles.header}>
        <Text variant="titleMedium" style={styles.heading}>
          Servizi ({servizi.length})
        </Text>
        <Button
          mode="contained-tonal"
          icon="plus"
          onPress={() => setMode({ type: 'add' })}
          disabled={formOpen}
          compact
        >
          Aggiungi
        </Button>
      </View>

      {servizi.map((s, idx) => {
        if (mode.type === 'edit' && mode.id === s.id) {
          return (
            <Card key={s.id} style={styles.formCard} mode="contained">
              <Card.Content>
                <ServizioForm
                  title={`Modifica servizio #${idx + 1}`}
                  submitLabel="Salva modifiche"
                  initial={{
                    codiceChiamata: s.codice_chiamata,
                    codiceUscita: s.codice_uscita,
                    ospedaleId: s.ospedale_id,
                    ospedaleLabel: s.ospedale_nome
                      ? ospedaleLabel(s.ospedale_nome, s.ospedale_citta)
                      : undefined,
                    descrizione: s.descrizione,
                  }}
                  onSubmit={(c, u, osp, desc) => handleEdit(s.id, c, u, osp, desc)}
                  onCancel={() => setMode({ type: 'none' })}
                />
              </Card.Content>
            </Card>
          );
        }
        return (
          <Card key={s.id} style={styles.card} mode="contained">
            <View style={styles.cardRow}>
              <View style={[styles.stripe, { backgroundColor: getCodiceColor(s.codice_chiamata) }]} />
              <View style={styles.progressivoBox}>
                <Text style={styles.progressivo}>#{idx + 1}</Text>
              </View>
              <View style={styles.cardBody}>
                <View style={styles.badgeRow}>
                  <View
                    style={[styles.badge, { backgroundColor: getCodiceColor(s.codice_chiamata) }]}
                  >
                    <Text style={styles.badgeText}>{s.codice_chiamata}</Text>
                  </View>
                  <Text style={styles.arrow}>→</Text>
                  <View style={[styles.badge, { backgroundColor: getCodiceColor(s.codice_uscita) }]}>
                    <Text style={styles.badgeText}>{s.codice_uscita}</Text>
                  </View>
                </View>
                {s.ospedale_nome ? (
                  <Text style={styles.ospedale}>
                    🏥 {s.ospedale_nome}
                    {s.ospedale_citta ? ` (${s.ospedale_citta})` : ''}
                  </Text>
                ) : null}
                {s.descrizione ? <Text style={styles.descrizione}>{s.descrizione}</Text> : null}
              </View>
              <View style={styles.actions}>
                <IconButton
                  icon="arrow-up"
                  size={18}
                  disabled={idx === 0 || formOpen}
                  onPress={() => handleMove(s.id, 'up')}
                  style={styles.actionBtn}
                />
                <IconButton
                  icon="arrow-down"
                  size={18}
                  disabled={idx === servizi.length - 1 || formOpen}
                  onPress={() => handleMove(s.id, 'down')}
                  style={styles.actionBtn}
                />
                <IconButton
                  icon="pencil"
                  size={18}
                  disabled={formOpen}
                  onPress={() => setMode({ type: 'edit', id: s.id })}
                  style={styles.actionBtn}
                />
                <IconButton
                  icon="delete"
                  size={18}
                  disabled={formOpen}
                  onPress={() => handleDelete(s.id)}
                  style={styles.actionBtn}
                />
              </View>
            </View>
          </Card>
        );
      })}

      {servizi.length === 0 && mode.type !== 'add' ? (
        <Text style={styles.empty}>Nessun servizio. Tocca “Aggiungi” per inserirne uno.</Text>
      ) : null}

      {mode.type === 'add' ? (
        <Card style={styles.formCard} mode="contained">
          <Card.Content>
            <ServizioForm
              title={`Nuovo servizio #${servizi.length + 1}`}
              submitLabel="Aggiungi servizio"
              onSubmit={handleAdd}
              onCancel={() => setMode({ type: 'none' })}
            />
          </Card.Content>
        </Card>
      ) : null}
    </View>
  );
}

const styles = StyleSheet.create({
  wrapper: { marginTop: 8 },
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
  progressivoBox: { paddingHorizontal: 8, justifyContent: 'center' },
  progressivo: { color: colors.textSecondary, fontWeight: '700', fontSize: 13 },
  cardBody: { flex: 1, paddingVertical: 10, paddingHorizontal: 4 },
  badgeRow: { flexDirection: 'row', alignItems: 'center', gap: 8 },
  badge: { borderRadius: 6, paddingHorizontal: 8, paddingVertical: 2 },
  badgeText: { color: '#000000', fontWeight: '700', fontSize: 12 },
  arrow: { color: colors.textSecondary, fontSize: 16 },
  ospedale: { color: colors.textSecondary, marginTop: 6 },
  descrizione: { color: colors.textPrimary, marginTop: 6 },
  actions: { flexDirection: 'column', alignItems: 'center' },
  actionBtn: { margin: 0 },
  empty: { color: colors.textSecondary, textAlign: 'center', paddingVertical: 12 },
  formCard: {
    backgroundColor: colors.surface,
    marginBottom: 8,
    borderWidth: 1,
    borderColor: colors.border,
  },
});
