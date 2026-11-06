import { statSync, rmSync, existsSync } from 'node:fs';
import Database from 'better-sqlite3';

const [, , origen, destino] = process.argv;
if (!origen || !destino) {
  console.error('uso: node sqlite-snapshot.mjs <origen.db> <destino.db>');
  process.exit(2);
}

const contar = (db, tabla) => {
  try {
    return db.prepare(`select count(*) as n from ${tabla}`).get().n;
  } catch {
    return null;
  }
};

const origenDb = new Database(origen, { readonly: true, fileMustExist: true });
try {
  await origenDb.backup(destino);
} finally {
  origenDb.close();
}

const copia = new Database(destino, { readonly: true, fileMustExist: true });
const integridad = copia.pragma('integrity_check', { simple: true });
const info = {
  origen,
  destino,
  integridad,
  bytes: statSync(destino).size,
  usuarios: contar(copia, 'users'),
  organizaciones: contar(copia, 'organizations'),
  productos: contar(copia, 'products'),
  suscripciones: contar(copia, 'subscriptions'),
};
copia.close();

const wal = destino + '-wal';
const shm = destino + '-shm';
let walPendiente = 0;
if (existsSync(wal)) {
  walPendiente = statSync(wal).size;
  rmSync(wal, { force: true });
}
if (existsSync(shm)) rmSync(shm, { force: true });
info.walPendiente = walPendiente;

console.log(JSON.stringify(info));

const malo = integridad !== 'ok' || walPendiente > 0;
if (malo) {
  console.error(
    walPendiente > 0
      ? `el WAL de destino tenia ${walPendiente} bytes pendientes; la copia no es autonoma`
      : `integrity_check devolvio: ${integridad}`,
  );
}
process.exit(malo ? 1 : 0);
