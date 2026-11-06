const ts = () => new Date().toISOString();

const NIVELES = ['error', 'warn', 'info'] as const;

function nivelActivo(): (typeof NIVELES)[number] {
  const bruto = (process.env.LOG_LEVEL ?? 'info').toLowerCase();
  return NIVELES.includes(bruto as (typeof NIVELES)[number]) ? (bruto as (typeof NIVELES)[number]) : 'info';
}

export const logger = {
  info: (...args: unknown[]) => {
    if (nivelActivo() === 'info') console.log(`[${ts()}] INFO `, ...args);
  },
  warn: (...args: unknown[]) => {
    if (nivelActivo() !== 'error') console.warn(`[${ts()}] WARN `, ...args);
  },
  error: (...args: unknown[]) => console.error(`[${ts()}] ERROR`, ...args),
};
