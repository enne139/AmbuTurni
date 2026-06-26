/** Formatta una data ISO in "gg/mm/aaaa". */
export function formatDate(iso?: string | null): string {
  if (!iso) return '—';
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  const gg = String(d.getDate()).padStart(2, '0');
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const aaaa = d.getFullYear();
  return `${gg}/${mm}/${aaaa}`;
}

/** Formatta le ore decimali (es. 4.5 → "4.5 h"). */
export function formatOre(ore?: number | null): string {
  if (ore === null || ore === undefined) return '—';
  return `${ore} h`;
}

/** Converte una stringa "4,5" o "4.5" in numero, o null se vuota/non valida. */
export function parseOre(text: string): number | null {
  const t = text.trim().replace(',', '.');
  if (t === '') return null;
  const n = Number(t);
  return Number.isNaN(n) ? null : n;
}
