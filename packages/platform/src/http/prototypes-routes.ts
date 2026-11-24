import { Router, type Response } from 'express';
import { authRequired } from './middleware.js';
import { asyncHandler } from '../shared/http.js';
import {
  findPublicPrototype,
  findVisiblePrototype,
  listPublicPrototypes,
  listVisiblePrototypes,
  readPrototypeHtml,
  type PrototypeRow,
} from '../domain/prototypes.js';

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

function sendHtml(res: Response, prototype: PrototypeRow, baseDir: string) {
  const html = readPrototypeHtml(baseDir, prototype.file_path);
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.setHeader('Cache-Control', 'private, no-store');
  res.setHeader('Referrer-Policy', 'no-referrer');
  res.setHeader('Content-Security-Policy', PROTOTYPE_CSP);
  return res.send(html);
}

export function createPrototypesRouter(baseDir: string): Router {
  const router = Router();

  router.get(
    '/public',
    asyncHandler(async (_req, res) => {
      return res.json({ prototypes: listPublicPrototypes() });
    }),
  );

  router.get(
    '/public/:slug/html',
    asyncHandler(async (req, res) => {
      const prototype = findPublicPrototype(req.params.slug);
      if (!prototype) return res.status(404).json({ error: 'Prototipo no encontrado.' });
      return sendHtml(res, prototype, baseDir);
    }),
  );

  router.get(
    '/',
    authRequired,
    asyncHandler(async (req, res) => {
      return res.json({ prototypes: listVisiblePrototypes(req.amg!.organizationId) });
    }),
  );

  router.get(
    '/:slug/html',
    authRequired,
    asyncHandler(async (req, res) => {
      const prototype = findVisiblePrototype(req.params.slug, req.amg!.organizationId);
      if (!prototype) return res.status(404).json({ error: 'Prototipo no encontrado.' });
      return sendHtml(res, prototype, baseDir);
    }),
  );

  return router;
}
