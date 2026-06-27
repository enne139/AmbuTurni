import * as DocumentPicker from 'expo-document-picker';
import * as FileSystem from 'expo-file-system';
import * as Sharing from 'expo-sharing';

/**
 * I/O file di backup — implementazione NATIVE (Android/iOS).
 * Su web Metro usa automaticamente `backupIO.web.ts`.
 */

/** Salva il JSON su file e apre il foglio di condivisione. Ritorna un messaggio. */
export async function saveBackup(filename: string, json: string): Promise<string> {
  const uri = (FileSystem.documentDirectory ?? FileSystem.cacheDirectory ?? '') + filename;
  await FileSystem.writeAsStringAsync(uri, json, {
    encoding: FileSystem.EncodingType.UTF8,
  });
  if (await Sharing.isAvailableAsync()) {
    await Sharing.shareAsync(uri, {
      mimeType: 'application/json',
      dialogTitle: 'Esporta backup',
    });
    return 'Backup pronto per la condivisione.';
  }
  return `Backup salvato in: ${uri}`;
}

/** Apre il selettore file e ritorna il testo JSON scelto (o null se annullato). */
export async function pickBackup(): Promise<string | null> {
  const res = await DocumentPicker.getDocumentAsync({
    type: 'application/json',
    copyToCacheDirectory: true,
  });
  if (res.canceled || !res.assets || res.assets.length === 0) return null;
  return FileSystem.readAsStringAsync(res.assets[0].uri, {
    encoding: FileSystem.EncodingType.UTF8,
  });
}
