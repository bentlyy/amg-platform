import { readFileSync } from 'node:fs';
import path from 'node:path';
import { AppError } from '../shared/http.js';
import { createId, getCoreDb } from '../db/index.js';

export interface PrototypeListItem {
  slug: string;
  name: string;
  client_name: string;
  description: string;
}

export interface PrototypeRow extends PrototypeListItem {
  id: string;
  file_path: string;
}

export interface UpsertPrototypeInput {
  slug: string;
  name: string;
  clientName: string;
  description: string;
  filePath: string;
  organizationIds: string[];
  publicAccess?: boolean;
}

export function listVisiblePrototypes(organizationId: string): PrototypeListItem[] {
  return getCoreDb()
    .sqlite.prepare(
      `SELECT p.slug, p.name, p.client_name, p.description
         FROM prototypes p
         JOIN prototype_access a ON a.prototype_id = p.id
        WHERE a.organization_id = ? AND p.active = 1
        ORDER BY p.client_name, p.name`,
    )
    .all(organizationId) as PrototypeListItem[];
}

export function findVisiblePrototype(slug: string, organizationId: string): PrototypeRow | undefined {
  return getCoreDb()
    .sqlite.prepare(
      `SELECT p.id, p.slug, p.name, p.client_name, p.description, p.file_path
         FROM prototypes p
         JOIN prototype_access a ON a.prototype_id = p.id
        WHERE p.slug = ? AND a.organization_id = ? AND p.active = 1`,
    )
    .get(slug, organizationId) as PrototypeRow | undefined;
}

export function listPublicPrototypes(): PrototypeListItem[] {
  return getCoreDb()
    .sqlite.prepare(
      `SELECT p.slug, p.name, p.client_name, p.description
         FROM prototypes p
        WHERE p.active = 1 AND p.public_access = 1
        ORDER BY p.client_name, p.name`,
    )
    .all() as PrototypeListItem[];
}

export function findPublicPrototype(slug: string): PrototypeRow | undefined {
  return getCoreDb()
    .sqlite.prepare(
      `SELECT p.id, p.slug, p.name, p.client_name, p.description, p.file_path
         FROM prototypes p
        WHERE p.slug = ? AND p.active = 1 AND p.public_access = 1`,
    )
    .get(slug) as PrototypeRow | undefined;
}

export function readPrototypeHtml(baseDir: string, filePath: string): string {
  const root = path.resolve(baseDir);
  const target = path.resolve(root, filePath);
  if (target !== root && !target.startsWith(root + path.sep)) throw new AppError(404, 'Prototipo no encontrado.');
  try {
    return readFileSync(target, 'utf8');
  } catch {
    throw new AppError(404, 'Prototipo no encontrado.');
  }
}

export function upsertPrototype(input: UpsertPrototypeInput): string {
  if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(input.slug)) {
    throw new AppError(400, 'El slug solo acepta letras minúsculas, números y guiones.');
  }
  if (!input.name.trim() || !input.clientName.trim() || !input.filePath.trim()) {
    throw new AppError(400, 'Faltan datos del prototipo.');
  }
  const db = getCoreDb().sqlite;
  const now = new Date().toISOString();
  return db.transaction(() => {
    db.prepare(
      `INSERT INTO prototypes (id, slug, name, client_name, description, file_path, active, public_access, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?, ?)
       ON CONFLICT(slug) DO UPDATE SET
         name = excluded.name,
         client_name = excluded.client_name,
         description = excluded.description,
         file_path = excluded.file_path,
         active = 1,
         public_access = excluded.public_access,
         updated_at = excluded.updated_at`,
    ).run(createId(), input.slug, input.name.trim(), input.clientName.trim(), input.description.trim(), input.filePath, input.publicAccess ? 1 : 0, now, now);
    const row = db.prepare('SELECT id FROM prototypes WHERE slug = ?').get(input.slug) as { id: string };
    db.prepare('DELETE FROM prototype_access WHERE prototype_id = ?').run(row.id);
    const grant = db.prepare('INSERT OR IGNORE INTO prototype_access (prototype_id, organization_id) VALUES (?, ?)');
    for (const organizationId of input.organizationIds) grant.run(row.id, organizationId);
    return row.id;
  })();
}
