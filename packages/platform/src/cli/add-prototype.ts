import { getCoreDb } from '../db/init.js';
import { findOrganizationBySlug } from '../domain/organizations.js';
import { upsertPrototype } from '../domain/prototypes.js';

function bandera(nombre: string): string | undefined {
  const args = process.argv.slice(2);
  const i = args.indexOf(`--${nombre}`);
  return i >= 0 ? args[i + 1] : undefined;
}

const slug = bandera('slug');
const name = bandera('name');
const client = bandera('client');
const file = bandera('file');
const orgs = bandera('orgs');

if (!slug || !name || !client || !file || !orgs) {
  console.error('Uso: prototype:add --slug <slug> --name <nombre> --client <cliente> --file <ruta/relativa.html> --orgs <slug1,slug2>');
  process.exit(1);
}

getCoreDb();

const organizationIds: string[] = [];
const missing: string[] = [];
for (const value of orgs.split(',').map((s) => s.trim()).filter(Boolean)) {
  const org = findOrganizationBySlug(value);
  if (org) organizationIds.push(org.id);
  else missing.push(value);
}

if (missing.length > 0) {
  console.error(`Organizaciones no encontradas: ${missing.join(', ')}`);
  process.exit(1);
}

const id = upsertPrototype({
  slug,
  name,
  clientName: client,
  description: bandera('description') ?? '',
  filePath: file,
  organizationIds,
});

console.log(`Prototipo ${slug} -> ${id} (${organizationIds.length} organización(es))`);
