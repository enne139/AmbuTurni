// Bootstrap del server Express: rotte di auth e di sincronizzazione.
import cors from 'cors';
import express from 'express';
import { authMiddleware, createUser, login, seedAdmin } from './auth.js';
import { initSchema } from './db.js';
import { pull, push } from './sync.js';

const app = express();
app.use(cors()); // l'app (web/native) chiama il backend da un'origine diversa
app.use(express.json({ limit: '20mb' }));

// Healthcheck (usato anche da docker-compose / monitoraggio).
app.get('/health', (_req, res) => res.json({ status: 'ok' }));

// --- AUTENTICAZIONE ---

// Login: restituisce un token JWT da usare come Bearer nelle chiamate di sync.
app.post('/auth/login', async (req, res) => {
  const { username, password } = req.body ?? {};
  if (!username || !password) {
    return res.status(400).json({ error: 'username e password richiesti' });
  }
  const token = await login(username, password);
  if (!token) return res.status(401).json({ error: 'Credenziali non valide' });
  res.json({ token });
});

// Creazione di nuovi utenti: protetta (solo chi è già autenticato può aggiungere account).
app.post('/auth/users', authMiddleware, async (req, res) => {
  const { username, password } = req.body ?? {};
  if (!username || !password) {
    return res.status(400).json({ error: 'username e password richiesti' });
  }
  await createUser(username, password);
  res.status(201).json({ ok: true });
});

// --- SINCRONIZZAZIONE (tutte protette da JWT) ---

// Push: il client invia le righe modificate localmente.
app.post('/sync/push', authMiddleware, async (req, res) => {
  const changes = Array.isArray(req.body?.changes) ? req.body.changes : [];
  res.json(await push(changes));
});

// Pull: il client scarica le modifiche avvenute dopo `since`.
app.get('/sync/pull', authMiddleware, async (req, res) => {
  const since = typeof req.query.since === 'string' ? req.query.since : '1970-01-01T00:00:00Z';
  res.json(await pull(since));
});

const port = Number(process.env.PORT || 3000);

// Inizializza lo schema, crea l'admin, poi avvia il server.
initSchema()
  .then(seedAdmin)
  .then(() => {
    app.listen(port, () => console.log(`[api] in ascolto sulla porta ${port}`));
  })
  .catch((e) => {
    console.error('[api] avvio fallito:', e);
    process.exit(1);
  });
