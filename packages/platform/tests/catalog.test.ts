import { describe, expect, it } from 'vitest';
import { CATALOG, EXPECTED_SLUGS, PLATFORM_URL, RETIRED_SLUGS, seedCatalog } from '../src/seed.js';
import { listProducts, findProductBySlug } from '../src/domain/products.js';

/**
 * La regla ahora es identidad: el subdominio ES el slug. Los nombres viejos
 * (agenda, canchas, ordenes, stock, presupuestos) se retiraron del DNS y del
 * código, y los registros de Cloudflare se renombraron a los nombres de producto.
 * El compose, el nginx, la zona de Cloudflare y el catalogo tienen que decir lo
 * mismo, y el test de mas abajo lo verifica contra el compose.
 */
const ESPERADO: Record<string, string> = {
  espacios: 'espacios',
  citas: 'citas',
  inventario: 'inventario',
  solicitudes: 'solicitudes',
  cotizaciones: 'cotizaciones',
  crm: 'crm',
  activos: 'activos',
  checklists: 'checklists',
  pagos: 'pagos',
  taller: 'taller',
  vitaria: 'vitaria',
};

/**
 * El catálogo es un contrato con tres cosas a la vez: lo que se vende, lo que
 * tiene subdominio y lo que tiene base de datos propia. Si el número o los
 * nombres se desvían, el que se desvía es el despliegue, y acá se ve antes.
 */
describe('catálogo de productos', () => {
  it('son los del catalogo declarado, ni uno mas', () => {
    expect(CATALOG).toHaveLength(EXPECTED_SLUGS.length);
  });

  it('son los acordados, sin repetidos', () => {
    const slugs = CATALOG.map((p) => p.slug);
    expect([...slugs].sort()).toEqual([...EXPECTED_SLUGS].sort());
    expect(new Set(slugs).size).toBe(EXPECTED_SLUGS.length);
  });

  it('cada producto tiene su subdominio y todos cuelgan de amgdeveloper.cl', () => {
    for (const p of CATALOG) {
      expect(p.appUrl).toMatch(/^https:\/\/[a-z-]+\.amgdeveloper\.cl$/);
    }
  });

  it('el subdominio es el slug, que es lo que vive en el DNS y en el servidor', () => {
    // La regla de antes era 'slug y subdominio distintos' (citas en agenda).
    // Hoy el registro DNS se llama igual que el producto: citas abre en
    // citas.amgdeveloper.cl. Si eso se rompe, el Core manda al navegador a un
    // host que no existe despues de autenticar.
    for (const p of CATALOG) {
      expect(p.appUrl, `${p.slug} deberia abrir en ${ESPERADO[p.slug]}`).toBe(
        `https://${ESPERADO[p.slug]}.amgdeveloper.cl`,
      );
    }
  });

  it('ningún producto vendible usa un subdominio viejo ni el de la plataforma', () => {
    // Nombres que YA NO existen en el nginx de produccion. `agenda`, `canchas`,
    // `ordenes`, `stock` y `presupuestos` son los viejos, retirados a favor de
    // los slugs: que un producto vuelva a apuntar a uno es señal de DNS en el
    // estado anterior.
    const nombresViejos = new Set([
      'agenda',
      'canchas',
      'ordenes',
      'stock',
      'presupuestos',
      'docs',
      'recordatorios',
      'inv-v2',
      'desarrollo',
    ]);
    for (const p of CATALOG) {
      const host = new URL(p.appUrl).hostname.split('.')[0];
      expect(nombresViejos.has(host), `${p.slug} apunta a ${host}, que ya no existe`).toBe(false);
    }
  });

  it('cada producto tiene nombre, precio y periodo', () => {
    for (const p of CATALOG) {
      expect(p.name.length).toBeGreaterThan(0);
      expect(p.tagline.length).toBeGreaterThan(0);
      expect(p.price).toBeGreaterThan(0);
      expect(['monthly', 'yearly', 'one_time']).toContain(p.billingPeriod);
    }
  });

  it('lo retirado no vuelve al catálogo', () => {
    const vendibles = new Set(CATALOG.map((p) => p.slug));
    for (const gone of RETIRED_SLUGS) {
      expect(vendibles.has(gone.slug), `${gone.slug} sigue a la venta`).toBe(false);
    }
  });
});

describe('siembra del catálogo', () => {
  it('deja activos todos los productos del catalogo en la base', () => {
    seedCatalog();
    const activos = listProducts();
    expect(activos).toHaveLength(EXPECTED_SLUGS.length);
    expect(activos.map((p) => p.slug).sort()).toEqual([...EXPECTED_SLUGS].sort());
  });

  it('retira lo que ya no se vende, sin borrarlo', () => {
    seedCatalog();
    for (const gone of RETIRED_SLUGS) {
      const fila = findProductBySlug(gone.slug);
      if (!fila) continue; // nunca estuvo sembrado: no hay nada que retirar
      expect(fila.status, `${gone.slug} debería quedar inactivo`).toBe('inactive');
    }
  });

  it('los slugs nuevos quedan con su URL final', () => {
    seedCatalog();
    const citas = findProductBySlug('citas');
    expect(citas?.app_url).toBe('https://citas.amgdeveloper.cl');
    const espacios = findProductBySlug('espacios');
    expect(espacios?.app_url).toBe('https://espacios.amgdeveloper.cl');
  });

  it('es idempotente: sembrar dos veces no duplica', () => {
    seedCatalog();
    seedCatalog();
    expect(listProducts()).toHaveLength(EXPECTED_SLUGS.length);
  });

  it('guarda los precios en centavos, sin decimales', () => {
    seedCatalog();
    for (const p of listProducts()) {
      expect(Number.isInteger(p.price), `${p.slug} tiene precio con decimales`).toBe(true);
    }
  });
});
