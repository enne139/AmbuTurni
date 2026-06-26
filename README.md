# Ambulanza Turni

App **React Native + Expo (SDK 52)** per la gestione di **turni** e **assistenze** in
ambulanza. Funziona su **Android** e **Web**, in **modalità offline completa** con database
locale **SQLite** (`expo-sqlite`). È predisposta per una sincronizzazione futura con un
backend remoto.

---

## Caratteristiche

- **Turni**: associazione, data, ore, tipologie (multi-valore), servizi figli, doppio equipaggio.
- **Assistenze**: associazione, data, ore, doppio equipaggio.
- **Servizi** per turno: codice chiamata (`VERDE/GIALLO/ROSSO`), codice uscita
  (`verde/giallo/rosso/nero/vuoto/rifiuta`), ospedale opzionale.
- **Numero progressivo** automatico per associazione.
- Campi **"####" selezionabili** con ricerca + creazione al volo (associazioni, persone,
  ospedali, tipologie).
- **Tema scuro operativo** (Material Design 3).
- **Offline-first**: nessuna chiamata di rete bloccante.

---

## Stack

| Ruolo | Libreria |
|---|---|
| Framework | React Native + Expo SDK 52 |
| Database locale | expo-sqlite (API async) |
| Navigazione | @react-navigation (native, bottom-tabs, native-stack) |
| UI | react-native-paper (MD3 dark) |
| Icone | @expo/vector-icons (MaterialCommunityIcons) |
| Date picker | @react-native-community/datetimepicker |
| ID univoci | uuid (+ react-native-get-random-values) |
| Linguaggio | TypeScript strict |
| Build | EAS Build |

---

## Struttura

```
ambulanza-turni/
├── App.tsx                  ← entry point (init DB + provider)
├── index.ts                 ← registerRootComponent
├── app.json / eas.json / babel.config.js / tsconfig.json
└── src/
    ├── db/                  ← apertura DB, schema, CRUD + tipi
    ├── components/          ← SelectableField, MultiSelectableField, EquipaggioBlock, ServiziList
    ├── screens/             ← turni / assistenze / impostazioni
    ├── navigation/          ← AppNavigator (tabs + stacks)
    ├── sync/                ← syncManager (stub)
    └── utils/               ← theme, format
```

---

## Setup

> Richiede **Node.js 18+** e **npm**.

```bash
# 1. Installa le dipendenze
npm install

# 2. Avvia in sviluppo
npm start          # Metro bundler (scegli a/w per Android/Web)
npm run android    # apre direttamente su Android
npm run web        # apre nel browser

# 3. Controllo tipi
npm run tsc
```

Al primo avvio il database `ambulanza.db` viene creato automaticamente con tutto lo schema.

---

## Build APK (EAS)

```bash
npm install -g eas-cli
eas login
eas init        # genera il projectId → inseriscilo in app.json (extra.eas.projectId)

# APK di test interno
eas build --platform android --profile preview

# App Bundle per il Play Store
eas build --platform android --profile production
```

Profili definiti in `eas.json`:

| Profilo | Output |
|---|---|
| `preview` | `apk` (test interni) |
| `production` | `app-bundle` (Play Store) |

---

## Database

- Apertura: `SQLite.openDatabaseAsync('ambulanza.db')` con `PRAGMA journal_mode = WAL` e
  `PRAGMA foreign_keys = ON`.
- Tutte le query usano l'API asincrona (`getAllAsync`, `getFirstAsync`, `runAsync`, `execAsync`).
- Ogni tabella ha `created_at`, `updated_at`, `is_synced` per la sincronizzazione futura
  (`is_synced = 0` ⇒ record modificato localmente).
- `turni.num_servizi` viene ricalcolato a ogni aggiunta/rimozione di un servizio.

### Tabelle

`associazioni`, `persone`, `ospedali`, `tipologie_turno`, `tipologie_assistenza`,
`turni`, `servizi` (figli di `turni`, `ON DELETE CASCADE`), `assistenze`.

---

## Sincronizzazione (futura)

`src/sync/syncManager.ts` contiene lo stub `syncWithServer(serverUrl)`. L'implementazione
prevista è un pull/push REST verso un backend **Node.js + PostgreSQL**, basato sui campi
`is_synced` / `updated_at`.

---

## Workflow Git

Branch:

| Branch | Scopo |
|---|---|
| `main` | stabile / release |
| `develop` | sviluppo |
| `feature/<nome>` | nuove funzionalità |
| `fix/<nome>` | bug fix |

Convenzione commit (Conventional Commits):

```
feat:  nuova funzionalità
fix:   correzione bug
chore: manutenzione / build / deps
docs:  documentazione
```

Esempio:

```bash
git checkout -b feature/export-pdf develop
# ... modifiche ...
git add .
git commit -m "feat: esportazione turni in PDF"
```

---

## Note

- Codice in **TypeScript strict** con tipi espliciti.
- I form usano `ScrollView` per gestire la tastiera; le liste si ricaricano con
  `useFocusEffect` al ritorno in focus.
- App pensata per uso **completamente offline**.
```
