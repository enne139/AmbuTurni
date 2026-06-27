// Autenticazione: login con username/password (bcrypt) e token JWT.
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { pool } from './db.js';

const JWT_SECRET = process.env.JWT_SECRET || 'cambia-questa-chiave';
const TOKEN_TTL = process.env.TOKEN_TTL || '30d';

/** Crea l'utente admin iniziale dalle variabili d'ambiente, se non esiste già. */
export async function seedAdmin() {
  const username = process.env.ADMIN_USERNAME;
  const password = process.env.ADMIN_PASSWORD;
  if (!username || !password) {
    console.warn('[auth] ADMIN_USERNAME/ADMIN_PASSWORD non impostati: nessun utente creato.');
    return;
  }
  const exists = await pool.query('SELECT 1 FROM users WHERE username = $1', [username]);
  if (exists.rowCount === 0) {
    await createUser(username, password);
    console.log(`[auth] utente admin '${username}' creato.`);
  }
}

/** Inserisce (o ignora se esiste) un utente con password hashata. */
export async function createUser(username, password) {
  const hash = await bcrypt.hash(password, 10);
  await pool.query(
    'INSERT INTO users (username, password_hash) VALUES ($1, $2) ON CONFLICT (username) DO NOTHING',
    [username, hash]
  );
}

/** Verifica le credenziali e restituisce un token JWT, oppure null se non valide. */
export async function login(username, password) {
  const r = await pool.query('SELECT password_hash FROM users WHERE username = $1', [username]);
  if (r.rowCount === 0) return null;
  const ok = await bcrypt.compare(password, r.rows[0].password_hash);
  if (!ok) return null;
  return jwt.sign({ sub: username }, JWT_SECRET, { expiresIn: TOKEN_TTL });
}

/** Middleware Express: richiede un token JWT valido nell'header Authorization. */
export function authMiddleware(req, res, next) {
  const header = req.headers.authorization || '';
  const token = header.startsWith('Bearer ') ? header.slice(7) : null;
  if (!token) return res.status(401).json({ error: 'Token mancante' });
  try {
    req.user = jwt.verify(token, JWT_SECRET);
    next();
  } catch {
    res.status(401).json({ error: 'Token non valido o scaduto' });
  }
}
