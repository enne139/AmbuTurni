/**
 * Stub di sincronizzazione con il server remoto.
 *
 * La sincronizzazione vera e propria verrà implementata in futuro:
 * pull/push REST verso un backend Node.js + PostgreSQL, usando i campi
 * `is_synced` e `updated_at` presenti su tutte le tabelle per stabilire
 * quali record sono stati modificati localmente (is_synced = 0).
 */
export async function syncWithServer(serverUrl: string): Promise<void> {
  console.log('[Sync] Not yet implemented. Server URL:', serverUrl);
  // TODO: pull/push REST con il backend Node.js + PostgreSQL
}
