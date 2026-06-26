import { useFocusEffect } from '@react-navigation/native';
import React, { useCallback, useState } from 'react';
import { ScrollView, StyleSheet, View } from 'react-native';
import { Button, Divider, IconButton, List, Text, TextInput } from 'react-native-paper';
import {
  addAssociazione,
  addOspedale,
  addPersona,
  addTipologiaTurno,
  deleteAssociazione,
  deleteOspedale,
  deletePersona,
  getAssociazioni,
  getOspedali,
  getPersone,
  getTipologieTurno,
  type Associazione,
  type Ospedale,
  type Persona,
  type Tipologia,
} from '../../db/helpers';
import { colors } from '../../utils/theme';

export default function ImpostazioniScreen() {
  const [associazioni, setAssociazioni] = useState<Associazione[]>([]);
  const [persone, setPersone] = useState<Persona[]>([]);
  const [ospedali, setOspedali] = useState<Ospedale[]>([]);
  const [tipologie, setTipologie] = useState<Tipologia[]>([]);

  // Campi di input
  const [nuovaAssoc, setNuovaAssoc] = useState('');
  const [nuovoCognome, setNuovoCognome] = useState('');
  const [nuovoNome, setNuovoNome] = useState('');
  const [nuovoOspedale, setNuovoOspedale] = useState('');
  const [nuovaTipologia, setNuovaTipologia] = useState('');

  const load = useCallback(async () => {
    const [a, p, o, t] = await Promise.all([
      getAssociazioni(),
      getPersone(),
      getOspedali(),
      getTipologieTurno(),
    ]);
    setAssociazioni(a);
    setPersone(p);
    setOspedali(o);
    setTipologie(t);
  }, []);

  useFocusEffect(
    useCallback(() => {
      load();
    }, [load])
  );

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      <List.AccordionGroup>
        {/* ASSOCIAZIONI */}
        <List.Accordion title="Associazioni" id="assoc" titleStyle={styles.accTitle}>
          <View style={styles.addRow}>
            <TextInput
              label="Nome associazione"
              value={nuovaAssoc}
              onChangeText={setNuovaAssoc}
              mode="outlined"
              style={styles.flexInput}
              dense
            />
            <Button
              mode="contained"
              disabled={!nuovaAssoc.trim()}
              onPress={async () => {
                await addAssociazione(nuovaAssoc);
                setNuovaAssoc('');
                load();
              }}
            >
              +
            </Button>
          </View>
          {associazioni.map((a) => (
            <List.Item
              key={a.id}
              title={a.nome}
              titleStyle={styles.itemText}
              right={(props) => (
                <IconButton
                  {...props}
                  icon="delete"
                  onPress={async () => {
                    await deleteAssociazione(a.id);
                    load();
                  }}
                />
              )}
            />
          ))}
        </List.Accordion>

        <Divider />

        {/* PERSONE */}
        <List.Accordion title="Persone / Equipaggio" id="persone" titleStyle={styles.accTitle}>
          <View style={styles.addColumn}>
            <View style={styles.addRow}>
              <TextInput
                label="Cognome"
                value={nuovoCognome}
                onChangeText={setNuovoCognome}
                mode="outlined"
                style={styles.flexInput}
                dense
              />
              <TextInput
                label="Nome"
                value={nuovoNome}
                onChangeText={setNuovoNome}
                mode="outlined"
                style={styles.flexInput}
                dense
              />
            </View>
            <Button
              mode="contained"
              disabled={!nuovoCognome.trim()}
              onPress={async () => {
                await addPersona(nuovoCognome, nuovoNome);
                setNuovoCognome('');
                setNuovoNome('');
                load();
              }}
              style={styles.addBtnFull}
            >
              Aggiungi persona
            </Button>
          </View>
          {persone.map((p) => (
            <List.Item
              key={p.id}
              title={`${p.cognome} ${p.nome}`.trim()}
              titleStyle={styles.itemText}
              right={(props) => (
                <IconButton
                  {...props}
                  icon="delete"
                  onPress={async () => {
                    await deletePersona(p.id);
                    load();
                  }}
                />
              )}
            />
          ))}
        </List.Accordion>

        <Divider />

        {/* OSPEDALI */}
        <List.Accordion title="Ospedali" id="ospedali" titleStyle={styles.accTitle}>
          <View style={styles.addRow}>
            <TextInput
              label="Nome ospedale"
              value={nuovoOspedale}
              onChangeText={setNuovoOspedale}
              mode="outlined"
              style={styles.flexInput}
              dense
            />
            <Button
              mode="contained"
              disabled={!nuovoOspedale.trim()}
              onPress={async () => {
                await addOspedale(nuovoOspedale);
                setNuovoOspedale('');
                load();
              }}
            >
              +
            </Button>
          </View>
          {ospedali.map((o) => (
            <List.Item
              key={o.id}
              title={o.nome}
              description={o.citta ?? undefined}
              titleStyle={styles.itemText}
              right={(props) => (
                <IconButton
                  {...props}
                  icon="delete"
                  onPress={async () => {
                    await deleteOspedale(o.id);
                    load();
                  }}
                />
              )}
            />
          ))}
        </List.Accordion>

        <Divider />

        {/* TIPOLOGIE TURNO (no delete) */}
        <List.Accordion title="Tipologie turno" id="tipologie" titleStyle={styles.accTitle}>
          <View style={styles.addRow}>
            <TextInput
              label="Nome tipologia"
              value={nuovaTipologia}
              onChangeText={setNuovaTipologia}
              mode="outlined"
              style={styles.flexInput}
              dense
            />
            <Button
              mode="contained"
              disabled={!nuovaTipologia.trim()}
              onPress={async () => {
                await addTipologiaTurno(nuovaTipologia);
                setNuovaTipologia('');
                load();
              }}
            >
              +
            </Button>
          </View>
          {tipologie.map((t) => (
            <List.Item key={t.id} title={t.nome} titleStyle={styles.itemText} />
          ))}
          <Text style={styles.hint}>
            Le tipologie non sono eliminabili per preservare i turni esistenti.
          </Text>
        </List.Accordion>
      </List.AccordionGroup>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: colors.background },
  content: { paddingBottom: 48 },
  accTitle: { color: colors.textPrimary },
  addRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    paddingHorizontal: 16,
    paddingVertical: 8,
  },
  addColumn: { paddingBottom: 4 },
  flexInput: { flex: 1, backgroundColor: colors.surface },
  addBtnFull: { marginHorizontal: 16, marginTop: 4 },
  itemText: { color: colors.textPrimary },
  hint: {
    color: colors.textSecondary,
    fontSize: 12,
    paddingHorizontal: 16,
    paddingVertical: 8,
    fontStyle: 'italic',
  },
});
