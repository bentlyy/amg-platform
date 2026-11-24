import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import request from 'supertest';
import type { Express } from 'express';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { createPlatformApp } from '../src/app.js';
import { getCoreDb } from '../src/db/init.js';
import { seedCatalog } from '../src/seed.js';
import { upsertPrototype } from '../src/domain/prototypes.js';

let app: Express;
let dir: string;
const PASSWORD = 'UnaClaveLarga1';

function cookieDe(res: request.Response): string {
  const raw = res.headers['set-cookie'] as unknown as string[] | undefined;
  const found = (raw ?? []).find((c) => c.startsWith('amg_session='));
  if (!found) throw new Error('sin cookie de sesión');
  return found.split(';')[0] as string;
}

async function crearOrg(email: string, slug: string) {
  const res = await request(app)
    .post('/api/auth/register')
    .send({ name: 'Cliente', email, password: PASSWORD, organizationName: `Org ${slug}`, organizationSlug: slug })
    .expect(201);
  return { cookie: cookieDe(res), orgId: res.body.organization.id as string };
}

beforeAll(() => {
  getCoreDb();
  seedCatalog();
  dir = mkdtempSync(path.join(tmpdir(), 'amg-prototipos-'));
  writeFileSync(path.join(dir, 'demo.html'), '<!doctype html><title>Prototype</title><p>visible</p>');
  writeFileSync(path.join(dir, 'prototipos-publicos.html'), '<!doctype html><body data-page="prototipos-publicos"></body>');
  app = createPlatformApp({ prototypeDir: dir, staticDir: dir });
});

afterAll(() => {
  rmSync(dir, { recursive: true, force: true });
});

describe('prototipos privados', () => {
  it('exige sesión', async () => {
    await request(app).get('/api/prototypes').expect(401);
    await request(app).get('/api/prototypes/demo/html').expect(401);
    await request(app).get('/prototipos').set('Accept', 'text/html').expect(302);
    await request(app).get('/prototipos.html').expect(301);
  });

  it('solo muestra los prototipos de la organización de la sesión', async () => {
    const a = await crearOrg('proto-a@test.cl', 'proto-a');
    const b = await crearOrg('proto-b@test.cl', 'proto-b');
    upsertPrototype({
      slug: 'proto-de-a',
      name: 'Prototipo A',
      clientName: 'Cliente A',
      description: '',
      filePath: 'demo.html',
      organizationIds: [a.orgId],
    });

    const resA = await request(app).get('/api/prototypes').set('Cookie', a.cookie).expect(200);
    expect(resA.body.prototypes.map((p: { slug: string }) => p.slug)).toEqual(['proto-de-a']);

    const resB = await request(app).get('/api/prototypes').set('Cookie', b.cookie).expect(200);
    expect(resB.body.prototypes).toEqual([]);

    await request(app).get('/api/prototypes/proto-de-a/html').set('Cookie', b.cookie).expect(404);
    const html = await request(app).get('/api/prototypes/proto-de-a/html').set('Cookie', a.cookie).expect(200);
    expect(html.text).toContain('visible');
    expect(html.headers['cache-control']).toContain('no-store');
    expect(html.headers['content-security-policy']).toContain("frame-ancestors 'self'");
  });

  it('bloquea rutas que salen de la carpeta privada', async () => {
    const c = await crearOrg('proto-c@test.cl', 'proto-c');
    upsertPrototype({
      slug: 'proto-traversal',
      name: 'Traversal',
      clientName: 'Cliente C',
      description: '',
      filePath: '../secreto.html',
      organizationIds: [c.orgId],
    });
    await request(app).get('/api/prototypes/proto-traversal/html').set('Cookie', c.cookie).expect(404);
  });

  it('no publica prototipos en el catálogo', async () => {
    const res = await request(app).get('/api/products').expect(200);
    expect(res.body.products.map((p: { slug: string }) => p.slug)).not.toContain('proto-de-a');
  });
});

describe('prototipos públicos', () => {
  it('/prototipos-publicos sirve la vista pública sin sesión', async () => {
    const res = await request(app).get('/prototipos-publicos').expect(200);
    expect(res.text).toContain('data-page="prototipos-publicos"');
    await request(app).get('/demos').expect(404);
  });

  it('lista y sirve solo los marcados como públicos, sin sesión', async () => {
    const d = await crearOrg('proto-d@test.cl', 'proto-d');
    upsertPrototype({
      slug: 'proto-publico',
      name: 'Prototipo público',
      clientName: 'Cliente P',
      description: '',
      filePath: 'demo.html',
      organizationIds: [d.orgId],
      publicAccess: true,
    });

    const list = await request(app).get('/api/prototypes/public').expect(200);
    const slugs = list.body.prototypes.map((p: { slug: string }) => p.slug);
    expect(slugs).toContain('proto-publico');
    expect(slugs).not.toContain('proto-de-a');

    const html = await request(app).get('/api/prototypes/public/proto-publico/html').expect(200);
    expect(html.text).toContain('visible');
    expect(html.headers['content-security-policy']).toContain("frame-ancestors 'self'");

    await request(app).get('/api/prototypes/public/proto-de-a/html').expect(404);
  });
});
