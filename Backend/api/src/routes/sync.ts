import type { FastifyInstance } from 'fastify';
import type pg from 'pg';
import { audit } from '../audit.js';
import { Tokens, auth, requireAuth, type Role } from '../auth.js';
import { decide } from '../conflict.js';
import type { Config } from '../config.js';
import { HttpError } from '../errors.js';
import { MAX_RECORD_BYTES, syncBody, syncQuery, type RecordType } from '../schemas.js';

interface Row {
  type: string;
  id: string;
  data: Record<string, unknown>;
  updated_at: Date;
  deleted: boolean;
  server_seq: string;
}

const toWire = (r: Row) => ({ type: r.type, id: r.id, data: r.data, updatedAt: r.updated_at.toISOString(), deleted: r.deleted });

/** Tipos que um dependente não pode gravar (estrutura da família e mesada). */
const DEPENDENT_FORBIDDEN: ReadonlySet<RecordType> = new Set(['Household', 'FamilyMember', 'Allowance']);

export function syncRoutes(app: FastifyInstance, cfg: Config, pool: pg.Pool, tokens: Tokens): void {
  const pre = requireAuth(tokens, pool);
  const rateLimit = { max: cfg.rateLimits.sync, timeWindow: cfg.rateLimits.windowMs };

  // GET /api/sync?since=<seq>&limit=<n>
  app.get('/api/sync', { preHandler: pre, config: { rateLimit } }, async (req) => {
    const a = auth(req);
    const q = syncQuery.parse(req.query);
    const { rows } = await pool.query<Row>(
      `SELECT type, id, data, updated_at, deleted, server_seq
       FROM records WHERE household_id = $1 AND server_seq > $2
       ORDER BY server_seq LIMIT $3`,
      [a.householdId, q.since, q.limit + 1],
    );
    const hasMore = rows.length > q.limit;
    const page = hasMore ? rows.slice(0, q.limit) : rows;
    // O token é o maior server_seq entregue (ou o próprio `since` se nada mudou): nunca pula registros.
    const token = page.length ? Number(page[page.length - 1]!.server_seq) : Number(q.since);
    return { records: page.map(toWire), token, hasMore };
  });

  // POST /api/sync { records: [...] }
  app.post('/api/sync', { preHandler: pre, config: { rateLimit } }, async (req) => {
    const a = auth(req);
    const body = syncBody.parse(req.body);
    for (const r of body.records) {
      if (Buffer.byteLength(JSON.stringify(r.data)) > MAX_RECORD_BYTES) {
        throw new HttpError(413, 'record_too_large', `Registro ${r.id} excede ${MAX_RECORD_BYTES} bytes.`);
      }
    }

    const client = await pool.connect();
    try {
      await client.query('BEGIN');
      // Serializa gravações por household: server_seq passa a ser confirmado em ordem, então o token do pull nunca pula registros.
      await client.query('SELECT pg_advisory_xact_lock(hashtextextended($1, 0))', [a.householdId]);

      const accepted: string[] = [];
      const rejected: { id: string; reason: string; serverRecord: ReturnType<typeof toWire> | null }[] = [];
      const writes: { type: string; id: string; deleted: boolean }[] = [];

      const keys = body.records.map((r) => ({ t: r.type, i: r.id }));
      const existingRows = keys.length
        ? (
            await client.query<Row>(
              `SELECT r.type, r.id, r.data, r.updated_at, r.deleted, r.server_seq
               FROM records r JOIN unnest($2::text[], $3::uuid[]) AS k(t, i) ON r.type = k.t AND r.id = k.i
               WHERE r.household_id = $1`,
              [a.householdId, keys.map((k) => k.t), keys.map((k) => k.i)],
            )
          ).rows
        : [];
      const existing = new Map<string, Row>(existingRows.map((r) => [`${r.type}|${r.id}`, r]));

      for (const rec of body.records) {
        const k = `${rec.type}|${rec.id.toLowerCase()}`;
        const cur = existing.get(k);
        if (a.role === 'dependent' && DEPENDENT_FORBIDDEN.has(rec.type)) {
          rejected.push({ id: rec.id, reason: 'forbidden_role', serverRecord: cur ? toWire(cur) : null });
          continue;
        }
        const incoming = { updatedAtMs: Date.parse(rec.updatedAt), deleted: rec.deleted, data: rec.data };
        const decision = decide(
          incoming,
          cur && { updatedAtMs: cur.updated_at.getTime(), deleted: cur.deleted, data: cur.data },
        );
        if (decision === 'same') {
          accepted.push(rec.id);
          continue;
        }
        if (decision !== 'apply') {
          rejected.push({ id: rec.id, reason: decision, serverRecord: cur ? toWire(cur) : null });
          continue;
        }
        const res = await client.query<Row>(
          `INSERT INTO records (household_id, type, id, data, updated_at, deleted, owner_id)
           VALUES ($1,$2,$3,$4,$5,$6,$7)
           ON CONFLICT (household_id, type, id) DO UPDATE
             SET data = EXCLUDED.data, updated_at = EXCLUDED.updated_at, deleted = EXCLUDED.deleted,
                 owner_id = EXCLUDED.owner_id, server_seq = nextval('records_server_seq_seq')
           RETURNING type, id, data, updated_at, deleted, server_seq`,
          [a.householdId, rec.type, rec.id, JSON.stringify(rec.data), rec.updatedAt, rec.deleted, a.userId],
        );
        existing.set(k, res.rows[0]!); // duplicatas no mesmo lote são avaliadas contra o estado já gravado
        accepted.push(rec.id);
        writes.push({ type: rec.type, id: rec.id, deleted: rec.deleted });
      }

      if (writes.length) {
        await client.query(
          `INSERT INTO audit_log (household_id, user_id, action, entity_type, entity_id, ip)
           SELECT $1, $2, CASE WHEN w.d THEN 'record.delete' ELSE 'record.upsert' END, w.t, w.i, $3
           FROM unnest($4::text[], $5::uuid[], $6::boolean[]) AS w(t, i, d)`,
          [a.householdId, a.userId, req.ip, writes.map((w) => w.type), writes.map((w) => w.id), writes.map((w) => w.deleted)],
        );
      }
      const head = await client.query<{ head: string | null }>('SELECT max(server_seq) AS head FROM records WHERE household_id = $1', [a.householdId]);
      await client.query('COMMIT');
      // `token` aqui é só o "head" atual do household. O cliente NÃO deve usá-lo como `since` (poderia pular
      // mudanças de outros dispositivos); continue usando o token devolvido por GET /api/sync.
      return { accepted, rejected, token: Number(head.rows[0]?.head ?? 0) };
    } catch (e) {
      await client.query('ROLLBACK').catch(() => {});
      throw e;
    } finally {
      client.release();
    }
  });
}
