import type { FastifyInstance } from 'fastify';
import type pg from 'pg';
import { audit } from '../audit.js';
import { Tokens, auth, requireAuth } from '../auth.js';
import type { Config } from '../config.js';
import { HttpError } from '../errors.js';
import { inviteBody, joinBody } from '../schemas.js';
import { formatInviteCode, newInviteCode, normalizeInviteCode, sha256 } from '../security.js';

const INVITE_TTL_HOURS = 48;
const MAX_OPEN_INVITES = 20;

export function householdRoutes(app: FastifyInstance, cfg: Config, pool: pg.Pool, tokens: Tokens): void {
  const pre = requireAuth(tokens, pool);

  // Só admin cria convite.
  app.post('/api/households/invite', { preHandler: pre, config: { rateLimit: { max: cfg.rateLimits.join, timeWindow: cfg.rateLimits.windowMs } } }, async (req, reply) => {
    const a = auth(req);
    if (a.role !== 'admin') throw new HttpError(403, 'forbidden', 'Apenas administradores podem convidar.');
    const body = inviteBody.parse(req.body ?? {});
    const open = await pool.query<{ n: string }>(
      'SELECT count(*) AS n FROM invites WHERE household_id = $1 AND used_at IS NULL AND expires_at > now()',
      [a.householdId],
    );
    if (Number(open.rows[0]!.n) >= MAX_OPEN_INVITES) throw new HttpError(429, 'too_many_invites', 'Há convites demais em aberto.');

    const code = newInviteCode();
    const r = await pool.query<{ expires_at: Date }>(
      `INSERT INTO invites (household_id, code_hash, role, created_by, expires_at)
       VALUES ($1,$2,$3,$4, now() + make_interval(hours => $5)) RETURNING expires_at`,
      [a.householdId, sha256(code), body.role, a.userId, INVITE_TTL_HOURS],
    );
    await audit(pool, { householdId: a.householdId, userId: a.userId, action: 'invite.create', detail: { role: body.role }, ip: req.ip });
    return reply.code(201).send({ code: formatInviteCode(code), role: body.role, expiresAt: r.rows[0]!.expires_at.toISOString() });
  });

  app.post('/api/households/join', { preHandler: pre, config: { rateLimit: { max: cfg.rateLimits.join, timeWindow: cfg.rateLimits.windowMs } } }, async (req) => {
    const a = auth(req);
    const { code } = joinBody.parse(req.body);
    const hash = sha256(normalizeInviteCode(code));

    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      // Consumo atômico: dois joins simultâneos com o mesmo código não passam os dois.
      const inv = await client.query<{ household_id: string; role: string }>(
        `UPDATE invites SET used_at = now(), used_by = $2
         WHERE code_hash = $1 AND used_at IS NULL AND expires_at > now()
         RETURNING household_id, role`,
        [hash, a.userId],
      );
      const invite = inv.rows[0];
      if (!invite) throw new HttpError(404, 'invalid_code', 'Código inválido, já usado ou expirado.');
      if (invite.household_id === a.householdId) throw new HttpError(409, 'already_member', 'Você já faz parte desta casa.');

      // Um usuário tem um household. Só trocamos se o atual não tiver dados (evita perder dados sem querer).
      const live = await client.query('SELECT 1 FROM records WHERE household_id = $1 AND NOT deleted LIMIT 1', [a.householdId]);
      if (live.rowCount) throw new HttpError(409, 'household_not_empty', 'Sua casa atual tem dados. Exporte ou apague antes de entrar em outra.');
      if (a.role === 'admin') {
        const others = await client.query('SELECT 1 FROM memberships WHERE household_id = $1 AND user_id <> $2 LIMIT 1', [a.householdId, a.userId]);
        if (others.rowCount) throw new HttpError(409, 'last_admin', 'Sua casa atual tem outros membros. Transfira ou remova-os antes.');
      }

      await client.query('DELETE FROM memberships WHERE user_id = $1', [a.userId]);
      await client.query(
        `DELETE FROM households h WHERE h.id = $1 AND NOT EXISTS (SELECT 1 FROM memberships m WHERE m.household_id = h.id)`,
        [a.householdId],
      );
      await client.query('INSERT INTO memberships (user_id, household_id, role) VALUES ($1,$2,$3)', [a.userId, invite.household_id, invite.role]);
      const h = await client.query<{ name: string }>('SELECT name FROM households WHERE id = $1', [invite.household_id]);
      await audit(client, { householdId: invite.household_id, userId: a.userId, action: 'household.join', detail: { role: invite.role }, ip: req.ip });
      await client.query('COMMIT');
      return { household: { id: invite.household_id, name: h.rows[0]!.name, role: invite.role } };
    } catch (e) {
      await client.query('ROLLBACK').catch(() => {});
      throw e;
    } finally {
      client.release();
    }
  });
}
