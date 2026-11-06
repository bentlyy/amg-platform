import type { NextFunction, Request, Response } from 'express';

export class AppError extends Error {
  status: number;
  errors?: unknown;

  constructor(status: number, message: string, errors?: unknown) {
    super(message);
    this.status = status;
    this.errors = errors;
  }
}

type Handler = (req: Request, res: Response, next: NextFunction) => unknown;

export const asyncHandler =
  (fn: Handler) =>
  (req: Request, res: Response, next: NextFunction): Promise<unknown> =>
    Promise.resolve(fn(req, res, next)).catch(next);

export function notFound(req: Request, _res: Response, next: NextFunction): void {
  next(new AppError(404, `No existe ${req.method} ${req.path}`));
}

export function errorHandler(err: unknown, _req: Request, res: Response, _next: NextFunction): Response {
  if (err instanceof AppError) {
    return res.status(err.status).json({ error: err.message, errors: err.errors });
  }
  if (isZodError(err)) {
    return res.status(400).json({ error: 'Datos inválidos', errors: err.flatten() });
  }
  if (isEntityTooLarge(err)) {
    return res.status(413).json({ error: 'La petición es demasiado grande' });
  }
  if (isMalformedJson(err)) {
    return res.status(400).json({ error: 'El cuerpo de la petición no es JSON válido' });
  }
  console.error(err);
  return res.status(500).json({ error: 'Error interno del servidor' });
}

function isZodError(e: unknown): e is { name: string; flatten: () => unknown } {
  return typeof (e as { name?: unknown })?.name === 'string' && (e as { name: string }).name === 'ZodError';
}

function isEntityTooLarge(e: unknown): boolean {
  return (e as { type?: unknown })?.type === 'entity.too.large';
}

function isMalformedJson(e: unknown): boolean {
  const type = (e as { type?: unknown })?.type;
  return type === 'entity.parse.failed' || (e instanceof SyntaxError && 'body' in e);
}
