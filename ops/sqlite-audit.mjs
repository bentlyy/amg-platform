import { readFileSync, statSync } from 'node:fs';
import Database from 'better-sqlite3';

const args = process.argv.slice(2);
const dbPath = args[0];
const envPath = args[1] && !args[1].startsWith('--') ? args[1] : null;
const requireSso = args.includes('--require-sso');
const strict = args.includes('--strict');

if (!dbPath) {
  console.error('uso: node sqlite-audit.mjs <core.db> [.env] [--require-sso] [--strict]');
  process.exit(2);
}

const leerEnv = (archivo) => {
  const valores = new Map();
  for (const linea of readFileSync(archivo, 'utf8').split(/\r?\n/)) {
    const limpia = linea.trim();
    if (!limpia || limpia.startsWith('#')) continue;
    const igual = limpia.indexOf('=');
    if (igual < 0) continue;
    let clave = limpia.slice(0, igual).trim();
    if (clave.startsWith('export ')) clave = clave.slice(7).trim();
    let valor = limpia.slice(igual + 1).trim();
    const comilla = valor[0];
    if ((comilla === '"' || comilla === "'") && valor.endsWith(comilla)) {
      valor = valor.slice(1, -1);
    }
    valores.set(clave, valor);
  }
  return valores;
};

const db = new Database(dbPath, { readonly: true, fileMustExist: true });
const integridad = db.pragma('integrity_check', { simple: true });
const tablas = db
  .prepare("select name from sqlite_master where type = 'table' and name not like 'sqlite_%' order by name")
  .all()
  .map((fila) => fila.name);

const conteos = {};
for (const tabla of tablas) {
  const nombre = '"' + tabla.replaceAll('"', '""') + '"';
  conteos[tabla] = db.prepare(`select count(*) as n from ${nombre}`).get().n;
}

const clientes = db.prepare('select client_id, secret from sso_clients order by client_id').all();
const env = envPath ? leerEnv(envPath) : new Map();
const sso = clientes.map((cliente) => {
  const envKey = 'AMG_SSO_' + cliente.client_id.toUpperCase().replace(/[^A-Z0-9]/g, '_') + '_SECRET';
  const envPresente = env.has(envKey);
  const envValor = env.get(envKey);
  return {
    client_id: cliente.client_id,
    env_key: envKey,
    env_present: envPresente,
    matches: envPresente ? envValor === cliente.secret : null,
  };
});

const ssoMismatches = sso.filter((item) => item.matches === false).map((item) => item.client_id);
const ssoMissing = sso.filter((item) => !item.env_present).map((item) => item.client_id);

const salida = {
  db: dbPath,
  bytes: statSync(dbPath).size,
  integrity: integridad,
  user_version: db.pragma('user_version', { simple: true }),
  tables: tablas.length,
  counts: conteos,
  sso_clients: clientes.length,
  sso_env_file: envPath,
  sso_ok: sso.length - ssoMismatches.length - ssoMissing.length,
  sso_mismatches: ssoMismatches,
  sso_missing: ssoMissing,
  sso,
};

db.close();
console.log(JSON.stringify(salida, null, 2));

if (envPath) {
  const noCoinciden = ssoMismatches.length ? ssoMismatches.join(', ') : 'ninguno';
  const faltan = ssoMissing.length ? ssoMissing.join(', ') : 'ninguno';
  console.error(`SSO: ${sso.length - ssoMismatches.length - ssoMissing.length}/${sso.length} coinciden; no coinciden: ${noCoinciden}; faltan: ${faltan}`);
}

if (integridad !== 'ok') process.exit(1);
if (requireSso && ssoMismatches.length > 0) process.exit(1);
if (strict && ssoMissing.length > 0) process.exit(1);
