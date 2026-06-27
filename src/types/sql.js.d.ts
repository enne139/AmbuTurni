/**
 * Dichiarazione minima per `sql.js` (usato solo dal backend web `src/db/index.web.ts`).
 * Il pacchetto non include tipi TypeScript: li dichiariamo come `any` per non bloccare tsc.
 */
declare module 'sql.js' {
  const initSqlJs: (config?: {
    locateFile?: (file: string) => string;
  }) => Promise<any>;
  export default initSqlJs;
}
