import { Router } from 'express';
import { authRequired } from './middleware.js';
import { asyncHandler } from '../shared/http.js';
import { findVisiblePrototype, listVisiblePrototypes, readPrototypeHtml } from '../domain/prototypes.js';

const PROTOTYPE_CSP = [
  "default-src 'none'",
  "img-src data: blob:",
  "style-src 'unsafe-inline'",
  "script-src 'unsafe-inline'",
  "connect-src 'none'",
  "form-action 'none'",
  "base-uri 'none'",
  "frame-ancestors 'self'",
].join('; ');

export function createPrototypesRouter(baseDir: string): Router {
  const router = Router();
  router.use(authRequired);

  router.get(
    '/',
    asyncHandler(async (req, res) => {
      return res.json({ prototypes: listVisiblePrototypes(req.amg!.organizationId) });
    }),
  );

  router.get(
    '/:slug/html',
    asyncHandler(async (req, res) => {
      const prototype = findVisiblePrototype(req.params.slug, req.amg!.organizationId);
      if (!prototype) return res.status(404).json({ error: 'Prototipo no encontrado.' });
      const html = readPrototypeHtml(baseDir, prototype.file_path);
      res.setHeader('Content-Type', 'text/html; charset=utf-8');
      res.setHeader('Cache-Control', 'private, no-store');
      res.setHeader('Referrer-Policy', 'no-referrer');
      res.setHeader('Content-Security-Policy', PROTOTYPE_CSP);
      return res.send(html);
    }),
  );

  return router;
}
