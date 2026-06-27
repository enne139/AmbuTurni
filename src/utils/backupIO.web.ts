/**
 * I/O file di backup — implementazione WEB (browser).
 * Usa le API DOM (Blob, anchor download, input file) tramite globalThis,
 * per non dipendere dalla lib DOM in tsconfig.
 */

interface WebGlobals {
  Blob: new (parts: string[], options?: { type?: string }) => unknown;
  URL: { createObjectURL(obj: unknown): string; revokeObjectURL(url: string): void };
  FileReader: new () => {
    onload: (() => void) | null;
    onerror: (() => void) | null;
    result: unknown;
    readAsText(blob: unknown): void;
  };
  document: {
    createElement(tag: string): any;
    body: { appendChild(n: unknown): void; removeChild(n: unknown): void };
  };
}

const g = globalThis as unknown as WebGlobals;

/** Genera e scarica il file JSON nel browser. */
export async function saveBackup(filename: string, json: string): Promise<string> {
  const blob = new g.Blob([json], { type: 'application/json' });
  const url = g.URL.createObjectURL(blob);
  const a = g.document.createElement('a');
  a.href = url;
  a.download = filename;
  g.document.body.appendChild(a);
  a.click();
  g.document.body.removeChild(a);
  g.URL.revokeObjectURL(url);
  return 'Download avviato.';
}

/** Apre il selettore file del browser e legge il testo del file scelto. */
export async function pickBackup(): Promise<string | null> {
  return new Promise<string | null>((resolve) => {
    const input = g.document.createElement('input');
    input.type = 'file';
    input.accept = 'application/json,.json';
    input.onchange = () => {
      const file = input.files && input.files[0];
      if (!file) {
        resolve(null);
        return;
      }
      const reader = new g.FileReader();
      reader.onload = () => resolve(String(reader.result));
      reader.onerror = () => resolve(null);
      reader.readAsText(file);
    };
    input.click();
  });
}
