import type { NextFunction, Request, Response } from 'express';

declare global {
  namespace Express {
    interface Request {
      cookies?: Record<string, string>;
    }
  }
}

export function parseCookies(cookieHeader: string | undefined): Record<string, string> {
  const out: Record<string, string> = {};
  if (!cookieHeader) return out;
  for (const part of cookieHeader.split(';')) {
    const idx = part.indexOf('=');
    if (idx === -1) continue;
    const key = part.slice(0, idx).trim();
    const value = decodeURIComponent(part.slice(idx + 1).trim());
    out[key] = value;
  }
  return out;
}

export const cookieParser = (req: Request, _res: Response, next: NextFunction): void => {
  req.cookies = req.cookies ?? parseCookies(req.headers.cookie);
  next();
};
