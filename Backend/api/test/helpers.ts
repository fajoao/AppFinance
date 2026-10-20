import { randomUUID } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import pg from 'pg';
import { buildApp } from '../src/app.js';
import { loadConfig, type Config } from '../src/config.js';
import { migrate } from '../src/migrate.js';

const baseUrl = process.env.DATABASE_URL;
if (!baseUrl) throw new Error('DATABASE_URL é obrigatório para os testes (Postgres real)');
const TEST_DB = 'finance_test';

export interface Ctx {
  app: FastifyInstance;
  pool: pg.Pool;
  cfg: Config;
  close: () => Promise<void>;
}

/** Cria (se preciso) o banco finance_test, aplica as migrações, limpa os dados e sobe o app. */
export async function setup(overrides: Partial<Record<string, string>> = {}): Promise<Ctx> {
  const admin = new pg.Client({ connectionString: baseUrl });
  await admin.connect();
  const exists = await admin.query('SELECT 1 FROM pg_database WHERE datname = $1', [TEST_DB]);
  if (!exists.rowCount) await admin.query(`CREATE DATABASE ${TEST_DB}`);
  await admin.end();

  const u = new URL(baseUrl!);
  u.pathname = `/${TEST_DB}`;
  const cfg = loadConfig({
    DATABASE_URL: u.toString(),
    JWT_SECRET: 'test-secret-test-secret-test-secret-123456',
    MIGRATIONS_DIR: process.env.MIGRATIONS_DIR ?? '/app/db/migrations',
    LOG_LEVEL: 'silent',
    RATE_LIMIT_GLOBAL: '100000',
    RATE_LIMIT_LOGIN: '100000',
    RATE_LIMIT_REGISTER: '100000',
    RATE_LIMIT_JOIN: '100000',
    RATE_LIMIT_SYNC: '100000',
    LOCKOUT_BASE_SEC: '30',
    ...overrides,
  });
  const pool = new pg.Pool({ connectionString: cfg.databaseUrl, max: 5 });
  await migrate(pool, cfg.migrationsDir);
  await pool.query('TRUNCATE users, households, login_throttle, audit_log RESTART IDENTITY CASCADE');
  const app = await buildApp(cfg, pool);
  await app.ready();
  return { app, pool, cfg, close: async () => { await app.close(); await pool.end(); } };
}

export interface Session { email: string; accessToken: string; refreshToken: string; householdId: string; userId: string }

export const PASSWORD = 'Correct-Horse-9';

export async function register(app: FastifyInstance, name = 'Ana'): Promise<Session> {
  const email = `${name.toLowerCase()}-${randomUUID().slice(0, 8)}@example.com`;
  const res = await app.inject({ method: 'POST', url: '/api/auth/register', payload: { email, password: PASSWORD, name } });
  if (res.statusCode !== 201) throw new Error(`register falhou: ${res.statusCode} ${res.body}`);
  const b = res.json();
  return { email, accessToken: b.accessToken, refreshToken: b.refreshToken, householdId: b.household.id, userId: b.user.id };
}

export const bearer = (s: Session) => ({ authorization: `Bearer ${s.accessToken}` });

export function rec(type: string, updatedAt: string, data: Record<string, unknown> = {}, extra: Record<string, unknown> = {}) {
  const id = (extra.id as string) ?? randomUUID();
  return { type, id, data: { id, ...data }, updatedAt, deleted: false, ...extra };
}
