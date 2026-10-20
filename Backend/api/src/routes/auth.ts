import { createHash } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import type pg from 'pg';
import { audit } from '../audit.js';
import { Tokens, auth, requireAuth } from '../auth.js';
import type { Config } from '../config.js';
import { HttpError } from '../errors.js';
import { loginBody, refreshBody, registerBody } from '../schemas.js';
import { dummyHash, hashPassword, passwordProblem, sha256, verifyPassword } from '../security.js';

const UNIQUE_VIOLATION = '23505';

export function authRoutes(app: FastifyInstance, cfg: Config, pool: pg.Pool, tokens: Tokens): void {
  const rl = cfg.rateLimits;

  app.post('/api/auth/register', { config: { rateLimit: { max: rl.register, timeWindow: rl.windowMs } } }, async (req, reply) => {
    const body = registerBody.parse(req.body);
    const problem = passwordProblem(body.password, body.email);
    if (problem) throw new HttpError(400, 'weak_password', problem);
    const passwordHash = await hashPassword(body.password);

    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      let userId: string;
      try {
        const u = await client.query<{ id: string }>(
          'INSERT INTO users (email, name, password_hash) VALUES ($1,$2,$3) RETURNING id',
          [body.email, body.name, passwordHash],
        );
        userId = u.rows[0]!.id;
      } catch (e) {
        if ((e as { code?: string }).code === UNIQUE_VIOLATION) throw new HttpError(409, 'email_in_use', 'Este e-mail já está cadastrado.');
        throw e;
      }
      const h = await client.query<{ id: string }>('INSERT INTO households (name) VALUES ($1) RETURNING id', [`Casa de ${body.name}`]);
      const householdId = h.rows[0]!.id;
      await client.query(`INSERT INTO memberships (user_id, household_id, role) VALUES ($1,$2,'admin')`, [userId, householdId]);
      const pair = await tokens.pair(client, userId);
      await audit(client, { householdId, userId, action: 'auth.register', ip: req.ip });
      await client.query('COMMIT');
      return reply.code(201).send({
        user: { id: userId, email: body.email, name: body.name },
        household: { id: householdId, name: `Casa de ${body.name}`, role: 'admin' },
        ...pair,
      });
    } catch (e) {
      await client.query('ROLLBACK').catch(() => {});
      throw e;
    } finally {
      client.release();
    }
  });

  app.post('/api/auth/login', { config: { rateLimit: { max: rl.login, timeWindow: rl.windowMs } } }, async (req, reply) => {
    const body = loginBody.parse(req.body);
    const key = sha256(body.email);

    const t = await pool.query<{ failures: number; wait: number | null }>(
      `SELECT failures, CEIL(EXTRACT(EPOCH FROM (locked_until - now())))::int AS wait FROM login_throttle WHERE key_hash = $1`,
      [key],
    );
    const wait = t.rows[0]?.wait ?? 0;
    if (wait > 0) {
      reply.header('Retry-After', String(wait));
      throw new HttpError(429, 'locked', 'Muitas tentativas. Aguarde antes de tentar novamente.', { retryAfter: wait });
    }

    const u = await pool.query<{ id: string; password_hash: string; disabled: boolean }>(
      'SELECT id, password_hash, disabled FROM users WHERE email = $1',
      [body.email],
    );
    const user = u.rows[0];
    const ok = await verifyPassword(user?.password_hash ?? (await dummyHash()), body.password);

    if (!user || !ok || user.disabled) {
      // bloqueio progressivo: após N falhas, espera base * 2^(falhas-N), limitada ao máximo
      const r = await pool.query<{ failures: number; wait: number | null }>(
        `INSERT INTO login_throttle (key_hash, failures, locked_until, updated_at)
         VALUES ($1, 1, NULL, now())
         ON CONFLICT (key_hash) DO UPDATE SET failures = login_throttle.failures + 1, updated_at = now()
         RETURNING failures, 0 AS wait`,
        [key],
      );
      const failures = r.rows[0]!.failures;
      if (failures >= cfg.lockoutFreeAttempts) {
        const sec = Math.min(cfg.lockoutMaxSec, cfg.lockoutBaseSec * 2 ** Math.min(failures - cfg.lockoutFreeAttempts, 20));
        await pool.query(`UPDATE login_throttle SET locked_until = now() + make_interval(secs => $2) WHERE key_hash = $1`, [key, sec]);
      }
      await audit(pool, { userId: user?.id ?? null, action: 'auth.login_failed', detail: { emailHash: createHash('sha256').update(body.email).digest('hex').slice(0, 12) }, ip: req.ip });
      throw new HttpError(401, 'invalid_credentials', 'E-mail ou senha incorretos.');
    }

    await pool.query('DELETE FROM login_throttle WHERE key_hash = $1', [key]);
    const m = await pool.query<{ household_id: string }>('SELECT household_id FROM memberships WHERE user_id = $1', [user.id]);
    const pair = await tokens.pair(pool, user.id);
    await audit(pool, { householdId: m.rows[0]?.household_id, userId: user.id, action: 'auth.login', ip: req.ip });
    return reply.send(pair);
  });

  app.post('/api/auth/refresh', { config: { rateLimit: { max: rl.login, timeWindow: rl.windowMs } } }, async (req, reply) => {
    const { refreshToken } = refreshBody.parse(req.body);
    const hash = sha256(refreshToken);
    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      const found = await client.query<{ id: string; user_id: string; family_id: string; revoked: boolean; expired: boolean }>(
        `SELECT id, user_id, family_id, revoked_at IS NOT NULL AS revoked, expires_at <= now() AS expired
         FROM refresh_tokens WHERE token_hash = $1 FOR UPDATE`,
        [hash],
      );
      const row = found.rows[0];
      if (!row) throw new HttpError(401, 'invalid_refresh', 'Sessão inválida.');
      if (row.revoked) {
        // reuso de token já rotacionado: possível roubo; derruba a família inteira
        await client.query('UPDATE refresh_tokens SET revoked_at = now() WHERE family_id = $1 AND revoked_at IS NULL', [row.family_id]);
        await audit(client, { userId: row.user_id, action: 'auth.refresh_reuse', ip: req.ip });
        await client.query('COMMIT');
        throw new HttpError(401, 'invalid_refresh', 'Sessão inválida.');
      }
      if (row.expired) throw new HttpError(401, 'invalid_refresh', 'Sessão expirada.');
      const alive = await client.query('SELECT 1 FROM users WHERE id = $1 AND NOT disabled', [row.user_id]);
      if (alive.rowCount === 0) throw new HttpError(401, 'invalid_refresh', 'Sessão inválida.');
      await client.query('UPDATE refresh_tokens SET revoked_at = now() WHERE id = $1', [row.id]);
      const pair = await tokens.pair(client, row.user_id, row.family_id);
      await client.query('COMMIT');
      return reply.send(pair);
    } catch (e) {
      await client.query('ROLLBACK').catch(() => {});
      throw e;
    } finally {
      client.release();
    }
  });

  app.post('/api/auth/logout', async (req, reply) => {
    const { refreshToken } = refreshBody.parse(req.body);
    await pool.query(
      `UPDATE refresh_tokens SET revoked_at = now()
       WHERE revoked_at IS NULL AND family_id = (SELECT family_id FROM refresh_tokens WHERE token_hash = $1)`,
      [sha256(refreshToken)],
    );
    return reply.code(204).send();
  });

  app.get('/api/me', { preHandler: requireAuth(tokens, pool) }, async (req) => {
    const a = auth(req);
    const members = await pool.query(
      `SELECT u.id AS "userId", u.name, u.email, m.role FROM memberships m JOIN users u ON u.id = m.user_id
       WHERE m.household_id = $1 ORDER BY m.created_at`,
      [a.householdId],
    );
    return {
      user: { id: a.userId, email: a.email, name: a.name },
      household: { id: a.householdId, name: a.householdName, role: a.role },
      members: members.rows,
    };
  });
}
