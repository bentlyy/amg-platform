import { createHash } from 'node:crypto';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import path from 'node:path';
import { logger } from './logger.js';

export function assetVersion(dir: string): string {
  const hash = createHash('sha1');
  let entradas: string[];
  try {
    entradas = readdirSync(dir).sort();
  } catch {
    return '0';
  }
  for (const nombre of entradas) {
    try {
      const info = statSync(path.join(dir, nombre));
      if (!info.isFile()) continue;
      hash.update(`${nombre}:${info.size}:${Math.floor(info.mtimeMs)}`);
    } catch {
      // Un archivo que no se puede leer no debe tumbar el arranque.
    }
  }
  return hash.digest('hex').slice(0, 10);
}

export function versionAssets(html: string, version: string): string {
  return html.replace(
    /(\s(?:src|href))="\/(?!\/)([^"?#]+\.(?:js|css|woff2?|svg|png|jpe?g|webp|gif|ico))((?:\?[^"#]*)?)(#[^"]*)?"/g,
    (todo, attr, archivo, query, fragmento) => (query ? todo : `${attr}="/${archivo}?v=${version}${fragmento ?? ''}"`),
  );
}

export const HTML_CACHE_CONTROL = 'no-cache';
export const ASSET_MAX_AGE_MS = 365 * 24 * 60 * 60 * 1000;
export const ASSET_CACHE_CONTROL = 'public, max-age=31536000, immutable';

export function assetHeaders(res: { setHeader: (k: string, v: string) => void }): void {
  res.setHeader('cache-control', ASSET_CACHE_CONTROL);
}

export function htmlPages(dir: string, version: string): (nombre: string) => string {
  const cache = new Map<string, string>();
  return (nombre: string) => {
    const guardado = cache.get(nombre);
    if (guardado !== undefined) return guardado;
    let crudo: string;
    try {
      crudo = readFileSync(path.join(dir, nombre), 'utf8');
    } catch (err) {
      logger.error(`No se pudo leer ${nombre} de ${dir}`, err);
      throw err;
    }
    const conVersion = versionAssets(crudo, version);
    cache.set(nombre, conVersion);
    return conVersion;
  };
}
