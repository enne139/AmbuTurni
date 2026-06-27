import { useFocusEffect } from '@react-navigation/native';
import React, { useCallback, useState } from 'react';
import { Alert, ScrollView, StyleSheet, View } from 'react-native';
import {
  Button,
  Dialog,
  Divider,
  IconButton,
  List,
  Portal,
  Snackbar,
  Text,
  TextInput,
} from 'react-native-paper';
import { countRecords, exportData, importData, parseBackup } from '../../db/backup';
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
  updateAssociazione,
  updateOspedale,
  updatePersona,
  updateTipologiaTurno,
  type Associazione,
  type Ospedale,
  type Persona,
  type Tipologia,
} from '../../db/helpers';
import { pickBackup, saveBackup } from '../../utils/backupIO';
import { colors } from '../../utils/theme';

function backupFilename(): string {
  const d = new Date();
  const p = (n: number) => String(n).padStart(2, '0');
  return `ambulanza-backup-${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(
    d.getHours()
  )}${p(d.getMinutes())}.json`;
}

/** Elemento in modifica (discriminato per tipo di tabella). */
type EditTarget =
  | { kind: 'assoc'; id: string; title: string }
  | { kind: 'persona'; id: string; title: string }
  | { kind: 'ospedale'; id: string; title: string }
  | { kind: 'tipologia'; id: string; title: string };

export default function ImpostazioniScreen() {
  const [associazioni, setAssociazioni] = useState<Associazione[]>([]);
  const [persone, setPersone] = useState<Persona[]>([]);
  const [ospedali, setOspedali] = useState<Ospedale[]>([]);
  const [tipologie, setTipologie] = useState<Tipologia[]>([]);

  // Campi di input (aggiunta)
  const [nuovaAssoc, setNuovaAssoc] = useState('');
  const [nuovoCognome, setNuovoCognome] = useState('');
  const [nuovoNome, setNuovoNome] = useState('');
  const [nuovoOspedale, setNuovoOspedale] = useState('');
  const [nuovoOspedaleCitta, setNuovoOspedaleCitta] = useState('');
  const [nuovaTipologia, setNuovaTipologia] = useState('');

  // Stato di modifica
  const [edit, setEdit] = useState<EditTarget | null>(null);
  const [editNome, setEditNome] = useState('');
  const [editCognome, setEditCognome] = useState('');
  const [editCitta, setEditCitta] = useState('');

  // Stato backup
  const [busy, setBusy] = useState(false);
  const [snack, setSnack] = useState<string | null>(null);
  const [pendingImport, setPendingImport] = useState<{ json: string; count: number } | null>(null);

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

  // --- apertura dialog di modifica per i vari tipi ---
  const openEditAssoc = (a: Associazione) => {
    setEditNome(a.nome);
    setEdit({ kind: 'assoc', id: a.id, title: 'Modifica associazione' });
  };
  const openEditPersona = (p: Persona) => {
    setEditCognome(p.cognome);
    setEditNome(p.nome);
    setEdit({ kind: 'persona', id: p.id, title: 'Modifica persona' });
  };
  const openEditOspedale = (o: Ospedale) => {
    setEditNome(o.nome);
    setEditCitta(o.citta ?? '');
    setEdit({ kind: 'ospedale', id: o.id, title: 'Modifica ospedale' });
  };
  const openEditTipologia = (t: Tipologia) => {
    setEditNome(t.nome);
    setEdit({ kind: 'tipologia', id: t.id, title: 'Modifica tipologia turno' });
  };

  const canSaveEdit =
    edit?.kind === 'persona' ? editCognome.trim().length > 0 : editNome.trim().length > 0;

  const saveEdit = async () => {
    if (!edit) return;
    try {
      switch (edit.kind) {
        case 'assoc':
          await updateAssociazione(edit.id, editNome);
          break;
        case 'persona':
          await updatePersona(edit.id, editCognome, editNome);
          break;
        case 'ospedale':
          await updateOspedale(edit.id, editNome, editCitta);
          break;
        case 'tipologia':
          await updateTipologiaTurno(edit.id, editNome);
          break;
      }
      setEdit(null);
      load();
    } catch (e) {
      Alert.alert('Errore', 'Nome non valido o già esistente.');
    }
  };

  // --- Backup: esporta / importa ---
  const handleExport = async () => {
    setBusy(true);
    try {
      const json = await exportData();
      const msg = await saveBackup(backupFilename(), json);
      setSnack(msg);
    } catch (e) {
      console.warn('[backup] export error:', e);
      setSnack('Errore durante l’esportazione.');
    } finally {
      setBusy(false);
    }
  };

  const handleImportPick = async () => {
    setBusy(true);
    try {
      const text = await pickBackup();
      if (text === null) return; // annullato
      const data = parseBackup(text); // valida
      setPendingImport({ json: text, count: countRecords(data) });
    } catch (e) {
      console.warn('[backup] import parse error:', e);
      setSnack('File di backup non valido.');
    } finally {
      setBusy(false);
    }
  };

  const handleImportConfirm = async () => {
    if (!pendingImport) return;
    setBusy(true);
    try {
      const n = await importData(pendingImport.json);
      setPendingImport(null);
      await load();
      setSnack(`Importati ${n} record. Riapri le altre schede per vederli.`);
    } catch (e) {
      console.warn('[backup] import error:', e);
      setSnack('Errore durante l’importazione.');
    } finally {
      setBusy(false);
    }
  };

  return (
    <View style={styles.root}>
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
              right={() => (
                <View style={styles.actions}>
                  <IconButton icon="pencil" size={20} onPress={() => openEditAssoc(a)} />
                  <IconButton
                    icon="delete"
                    size={20}
                    onPress={async () => {
                      await deleteAssociazione(a.id);
                      load();
                    }}
                  />
                </View>
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
              right={() => (
                <View style={styles.actions}>
                  <IconButton icon="pencil" size={20} onPress={() => openEditPersona(p)} />
                  <IconButton
                    icon="delete"
                    size={20}
                    onPress={async () => {
                      await deletePersona(p.id);
                      load();
                    }}
                  />
                </View>
              )}
            />
          ))}
        </List.Accordion>

        <Divider />

        {/* OSPEDALI */}
        <List.Accordion title="Ospedali" id="ospedali" titleStyle={styles.accTitle}>
          <View style={styles.addColumn}>
            <View style={styles.addRow}>
              <TextInput
                label="Nome ospedale"
                value={nuovoOspedale}
                onChangeText={setNuovoOspedale}
                mode="outlined"
                style={styles.flexInput}
                dense
              />
              <TextInput
                label="Città"
                value={nuovoOspedaleCitta}
                onChangeText={setNuovoOspedaleCitta}
                mode="outlined"
                style={styles.flexInput}
                dense
              />
            </View>
            <Button
              mode="contained"
              disabled={!nuovoOspedale.trim()}
              onPress={async () => {
                await addOspedale(nuovoOspedale, nuovoOspedaleCitta);
                setNuovoOspedale('');
                setNuovoOspedaleCitta('');
                load();
              }}
              style={styles.addBtnFull}
            >
              Aggiungi ospedale
            </Button>
          </View>
          {ospedali.map((o) => (
            <List.Item
              key={o.id}
              title={o.nome}
              description={o.citta ?? undefined}
              titleStyle={styles.itemText}
              right={() => (
                <View style={styles.actions}>
                  <IconButton icon="pencil" size={20} onPress={() => openEditOspedale(o)} />
                  <IconButton
                    icon="delete"
                    size={20}
                    onPress={async () => {
                      await deleteOspedale(o.id);
                      load();
                    }}
                  />
                </View>
              )}
            />
          ))}
        </List.Accordion>

        <Divider />

        {/* TIPOLOGIE TURNO (modificabili, non eliminabili) */}
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
            <List.Item
              key={t.id}
              title={t.nome}
              titleStyle={styles.itemText}
              right={() => (
                <View style={styles.actions}>
                  <IconButton icon="pencil" size={20} onPress={() => openEditTipologia(t)} />
                </View>
              )}
            />
          ))}
          <Text style={styles.hint}>
            Le tipologie non sono eliminabili per preservare i turni esistenti, ma possono essere
            rinominate.
          </Text>
        </List.Accordion>

        <Divider />

        {/* BACKUP / DATI */}
        <List.Accordion title="Backup / Dati (JSON)" id="backup" titleStyle={styles.accTitle}>
          <View style={styles.backupBox}>
            <Button
              mode="contained"
              icon="download"
              onPress={handleExport}
              disabled={busy}
              style={styles.backupBtn}
            >
              Esporta dati
            </Button>
            <Button
              mode="contained-tonal"
              icon="upload"
              onPress={handleImportPick}
              disabled={busy}
              style={styles.backupBtn}
            >
              Importa dati
            </Button>
            <Text style={styles.hint}>
              L’esportazione crea un file JSON con tutti i dati. L’importazione
              sostituisce completamente i dati attuali con quelli del file scelto.
            </Text>
          </View>
        </List.Accordion>
      </List.AccordionGroup>

      {/* DIALOG DI MODIFICA */}
      <Portal>
        <Dialog visible={!!edit} onDismiss={() => setEdit(null)}>
          <Dialog.Title>{edit?.title}</Dialog.Title>
          <Dialog.Content>
            {edit?.kind === 'persona' ? (
              <>
                <TextInput
                  label="Cognome"
                  value={editCognome}
                  onChangeText={setEditCognome}
                  mode="outlined"
                  style={styles.dialogInput}
                />
                <TextInput
                  label="Nome"
                  value={editNome}
                  onChangeText={setEditNome}
                  mode="outlined"
                  style={styles.dialogInput}
                />
              </>
            ) : edit?.kind === 'ospedale' ? (
              <>
                <TextInput
                  label="Nome"
                  value={editNome}
                  onChangeText={setEditNome}
                  mode="outlined"
                  style={styles.dialogInput}
                />
                <TextInput
                  label="Città"
                  value={editCitta}
                  onChangeText={setEditCitta}
                  mode="outlined"
                  style={styles.dialogInput}
                />
              </>
            ) : (
              <TextInput
                label="Nome"
                value={editNome}
                onChangeText={setEditNome}
                mode="outlined"
                style={styles.dialogInput}
              />
            )}
          </Dialog.Content>
          <Dialog.Actions>
            <Button onPress={() => setEdit(null)}>Annulla</Button>
            <Button onPress={saveEdit} disabled={!canSaveEdit}>
              Salva
            </Button>
          </Dialog.Actions>
        </Dialog>

        {/* CONFERMA IMPORTAZIONE */}
        <Dialog visible={!!pendingImport} onDismiss={() => setPendingImport(null)}>
          <Dialog.Title>Importare i dati?</Dialog.Title>
          <Dialog.Content>
            <Text>
              Il file contiene {pendingImport?.count ?? 0} record. Tutti i dati attualmente
              presenti verranno sostituiti. L’operazione non è reversibile.
            </Text>
          </Dialog.Content>
          <Dialog.Actions>
            <Button onPress={() => setPendingImport(null)}>Annulla</Button>
            <Button textColor={colors.primary} disabled={busy} onPress={handleImportConfirm}>
              Importa
            </Button>
          </Dialog.Actions>
        </Dialog>
      </Portal>
    </ScrollView>

      <Snackbar visible={!!snack} onDismiss={() => setSnack(null)} duration={4000}>
        {snack ?? ''}
      </Snackbar>
    </View>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: colors.background },
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
  backupBox: { paddingHorizontal: 16, paddingVertical: 8, gap: 10 },
  backupBtn: { marginBottom: 2 },
  actions: { flexDirection: 'row', alignItems: 'center' },
  hint: {
    color: colors.textSecondary,
    fontSize: 12,
    paddingHorizontal: 16,
    paddingVertical: 8,
    fontStyle: 'italic',
  },
  dialogInput: { backgroundColor: colors.surface, marginBottom: 8 },
});
