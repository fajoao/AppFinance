export interface RateLimits {
  /** Limite geral por IP. */
  global: number;
  login: number;
  register: number;
  join: number;
  sync: number;
  /** Janela em milissegundos. */
  windowMs: number;
}

export interface Config {
  databaseUrl: string;
  jwtSecret: string;
  accessTtlSec: number;
  refreshTtlDays: number;
  corsOrigins: string[];
  trustProxy: boolean;
  rateLimits: RateLimits;
  /** Falhas de login toleradas antes do bloqueio progressivo. */
  lockoutFreeAttempts: number;
  lockoutBaseSec: number;
  lockoutMaxSec: number;
  bodyLimitBytes: number;
  migrationsDir: string;
  logLevel: string;
  port: number;
}

function int(env: NodeJS.ProcessEnv, key: string, def: number): number {
  const raw = env[key];
  if (raw === undefined || raw === '') return def;
  const n = Number(raw);
  if (!Number.isInteger(n) || n < 0) throw new Error(`Config inválida: ${key} deve ser inteiro >= 0`);
  return n;
}

/** Lê a configuração do ambiente. Falha cedo se faltar segredo: nenhum segredo vive no código. */
export function loadConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const databaseUrl = env.DATABASE_URL;
  if (!databaseUrl) throw new Error('DATABASE_URL é obrigatório');
  const jwtSecret = env.JWT_SECRET;
  if (!jwtSecret || jwtSecret.length < 32) throw new Error('JWT_SECRET é obrigatório (mínimo 32 caracteres)');
  return {
    databaseUrl,
    jwtSecret,
    accessTtlSec: int(env, 'ACCESS_TOKEN_TTL_SEC', 15 * 60),
    refreshTtlDays: int(env, 'REFRESH_TOKEN_TTL_DAYS', 30),
    corsOrigins: (env.CORS_ORIGINS ?? '').split(',').map((s) => s.trim()).filter(Boolean),
    trustProxy: (env.TRUST_PROXY ?? 'true') === 'true',
    rateLimits: {
      global: int(env, 'RATE_LIMIT_GLOBAL', 300),
      login: int(env, 'RATE_LIMIT_LOGIN', 10),
      register: int(env, 'RATE_LIMIT_REGISTER', 5),
      join: int(env, 'RATE_LIMIT_JOIN', 10),
      sync: int(env, 'RATE_LIMIT_SYNC', 120),
      windowMs: int(env, 'RATE_LIMIT_WINDOW_SEC', 60) * 1000,
    },
    lockoutFreeAttempts: int(env, 'LOCKOUT_FREE_ATTEMPTS', 5),
    lockoutBaseSec: int(env, 'LOCKOUT_BASE_SEC', 30),
    lockoutMaxSec: int(env, 'LOCKOUT_MAX_SEC', 3600),
    bodyLimitBytes: int(env, 'BODY_LIMIT_BYTES', 2 * 1024 * 1024),
    migrationsDir: env.MIGRATIONS_DIR ?? '/app/db/migrations',
    logLevel: env.LOG_LEVEL ?? 'info',
    port: int(env, 'PORT', 3000),
  };
}
