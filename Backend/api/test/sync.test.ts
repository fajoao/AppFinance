import { randomUUID } from 'node:crypto';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { decide, stableStringify } from '../src/conflict.js';
import { bearer, rec, register, setup, type Ctx, type Session } from './helpers.js';

let ctx: Ctx;
beforeAll(async () => { ctx = await setup(); });
afterAll(async () => { await ctx.close(); });

const push = (s: Session, records: unknown[]) =>
  ctx.app.inject({ method: 'POST', url: '/api/sync', headers: bearer(s), payload: { records } });
const pull = (s: Session, since: number | string = 0) =>
  ctx.app.inject({ method: 'GET', url: `/api/sync?since=${since}`, headers: bearer(s) });

describe('isolamento por household', () => {
  it('um usuário nunca vê (nem sobrescreve) dados de outro household', async () => {
    const a = await register(ctx.app, 'Alice');
    const b = await register(ctx.app, 'Bruno');
    const secret = rec('Transaction', '2026-01-01T10:00:00.000Z', { title: 'segredo da Alice', amount: 123.45 });
    expect((await push(a, [secret])).json().accepted).toEqual([secret.id]);

    const seenByB = (await pull(b)).json();
    expect(seenByB.records).toEqual([]);
    expect(JSON.stringify(seenByB)).not.toContain('segredo');

    // B grava o MESMO (type,id) com updatedAt mais novo: cria registro próprio, sem tocar o da Alice
    const forged = { ...secret, data: { ...secret.data, title: 'do Bruno' }, updatedAt: '2027-01-01T00:00:00.000Z' };
    expect((await push(b, [forged])).json().accepted).toEqual([secret.id]);
    const aAfter = (await pull(a)).json();
    expect(aAfter.records).toHaveLength(1);
    expect(aAfter.records[0].data.title).toBe('segredo da Alice');
    const bAfter = (await pull(b)).json();
    expect(bAfter.records[0].data.title).toBe('do Bruno');
  });

  it('exige autenticação', async () => {
    expect((await ctx.app.inject({ method: 'GET', url: '/api/sync' })).statusCode).toBe(401);
    expect((await ctx.app.inject({ method: 'POST', url: '/api/sync', payload: { records: [] } })).statusCode).toBe(401);
  });
});

describe('sincronização incremental', () => {
  it('pull com since devolve só o que mudou e o token avança', async () => {
    const s = await register(ctx.app, 'Inc');
    const r1 = rec('Account', '2026-02-01T00:00:00.000Z', { name: 'Conta' });
    await push(s, [r1]);
    const p1 = (await pull(s, 0)).json();
    expect(p1.records).toHaveLength(1);
    expect(p1.token).toBeGreaterThan(0);

    const p2 = (await pull(s, p1.token)).json();
    expect(p2.records).toEqual([]);
    expect(p2.token).toBe(p1.token);

    const r2 = rec('Category', '2026-02-02T00:00:00.000Z', { name: 'Mercado' });
    await push(s, [r2]);
    const p3 = (await pull(s, p1.token)).json();
    expect(p3.records.map((r: { id: string }) => r.id)).toEqual([r2.id]);
    expect(p3.token).toBeGreaterThan(p1.token);
  });

  it('paginação com limit/hasMore não pula registros', async () => {
    const s = await register(ctx.app, 'Pag');
    const recs = Array.from({ length: 5 }, (_, i) => rec('Tag', `2026-03-0${i + 1}T00:00:00.000Z`, { name: `t${i}` }));
    await push(s, recs);
    const seen: string[] = [];
    let token = 0;
    for (let guard = 0; guard < 10; guard++) {
      const r = (await ctx.app.inject({ method: 'GET', url: `/api/sync?since=${token}&limit=2`, headers: bearer(s) })).json();
      seen.push(...r.records.map((x: { id: string }) => x.id));
      token = r.token;
      if (!r.hasMore) break;
    }
    expect(new Set(seen)).toEqual(new Set(recs.map((r) => r.id)));
    expect(seen).toHaveLength(5);
  });
});

describe('regra de conflito e tombstone', () => {
  it('o maior updatedAt vence; o mais antigo é rejeitado com o serverRecord', async () => {
    const s = await register(ctx.app, 'Conf');
    const base = rec('Transaction', '2026-04-10T12:00:00.000Z', { title: 'v1' });
    await push(s, [base]);

    const newer = { ...base, data: { ...base.data, title: 'v2' }, updatedAt: '2026-04-10T12:00:05.000Z' };
    expect((await push(s, [newer])).json().accepted).toEqual([base.id]);

    const older = { ...base, data: { ...base.data, title: 'velho' }, updatedAt: '2026-04-10T11:00:00.000Z' };
    const res = (await push(s, [older])).json();
    expect(res.accepted).toEqual([]);
    expect(res.rejected).toHaveLength(1);
    expect(res.rejected[0]).toMatchObject({ id: base.id, reason: 'stale' });
    expect(res.rejected[0].serverRecord.data.title).toBe('v2');
    expect((await pull(s)).json().records[0].data.title).toBe('v2');
  });

  it('empate de updatedAt: desempate determinístico, independente da ordem de chegada', async () => {
    const a = await register(ctx.app, 'TieA');
    const b = await register(ctx.app, 'TieB');
    const id = randomUUID();
    const t = '2026-05-01T00:00:00.000Z';
    const x = { type: 'Goal', id, data: { name: 'AAA' }, updatedAt: t, deleted: false };
    const y = { type: 'Goal', id, data: { name: 'ZZZ' }, updatedAt: t, deleted: false };
    await push(a, [x]); await push(a, [y]);
    await push(b, [y]); await push(b, [x]);
    const fa = (await pull(a)).json().records[0].data.name;
    const fb = (await pull(b)).json().records[0].data.name;
    expect(fa).toBe(fb);
    expect(fa).toBe('ZZZ');
    // reenvio idêntico é idempotente (aceito, sem erro)
    expect((await push(a, [y])).json().accepted).toEqual([id]);
  });

  it('delete é tombstone: vira deleted=true, aparece no pull e vence edição anterior', async () => {
    const s = await register(ctx.app, 'Tomb');
    const tx = rec('Transaction', '2026-06-01T00:00:00.000Z', { title: 'apagar' });
    await push(s, [tx]);
    const t1 = (await pull(s)).json().token;

    const del = { ...tx, deleted: true, updatedAt: '2026-06-02T00:00:00.000Z' };
    expect((await push(s, [del])).json().accepted).toEqual([tx.id]);
    const p = (await pull(s, t1)).json();
    expect(p.records).toHaveLength(1);
    expect(p.records[0]).toMatchObject({ id: tx.id, deleted: true });

    // edição ANTERIOR à exclusão não ressuscita
    const lateEdit = { ...tx, data: { ...tx.data, title: 'editado' }, updatedAt: '2026-06-01T12:00:00.000Z' };
    const r = (await push(s, [lateEdit])).json();
    expect(r.rejected[0]).toMatchObject({ reason: 'stale' });
    expect(r.rejected[0].serverRecord.deleted).toBe(true);

    // edição POSTERIOR à exclusão recria (mesma regra do Core)
    const revive = { ...tx, updatedAt: '2026-06-03T00:00:00.000Z' };
    expect((await push(s, [revive])).json().accepted).toEqual([tx.id]);
    expect((await pull(s)).json().records[0].deleted).toBe(false);
  });

  it('em empate de updatedAt a exclusão vence a edição (Core: tombstone vale se deletedAt >= updatedAt)', () => {
    const base = { updatedAtMs: 1000, data: { a: 1 } };
    expect(decide({ ...base, deleted: true }, { ...base, deleted: false })).toBe('apply');
    expect(decide({ ...base, deleted: false }, { ...base, deleted: true })).toBe('tie_lost');
    expect(stableStringify({ b: 1, a: [2, { d: 1, c: 2 }] })).toBe('{"a":[2,{"c":2,"d":1}],"b":1}');
  });

  it('grava owner_id e auditoria sem dados financeiros', async () => {
    const s = await register(ctx.app, 'Audit');
    const tx = rec('Transaction', '2026-07-01T00:00:00.000Z', { title: 'Mercado secreto', amount: 987.65 });
    await push(s, [tx]);
    const row = (await ctx.pool.query('SELECT owner_id FROM records WHERE id = $1', [tx.id])).rows[0];
    expect(row.owner_id).toBe(s.userId);
    const log = (await ctx.pool.query('SELECT * FROM audit_log WHERE entity_id = $1', [tx.id])).rows;
    expect(log).toHaveLength(1);
    expect(log[0]).toMatchObject({ action: 'record.upsert', user_id: s.userId, household_id: s.householdId, entity_type: 'Transaction' });
    expect(JSON.stringify(log)).not.toMatch(/Mercado|987/);
  });
});

describe('validação e limites', () => {
  it('rejeita tipo desconhecido, id inválido, data fora de objeto e campos extras (400)', async () => {
    const s = await register(ctx.app, 'Val');
    const ok = rec('Tag', '2026-08-01T00:00:00.000Z');
    expect((await push(s, [{ ...ok, type: 'Hacker' }])).statusCode).toBe(400);
    expect((await push(s, [{ ...ok, id: 'nao-uuid' }])).statusCode).toBe(400);
    expect((await push(s, [{ ...ok, data: 'x' }])).statusCode).toBe(400);
    expect((await push(s, [{ ...ok, updatedAt: 'ontem' }])).statusCode).toBe(400);
    expect((await push(s, [{ ...ok, householdId: randomUUID() }])).statusCode).toBe(400);
  });

  it('limita registros por lote, tamanho do registro e do corpo', async () => {
    const s = await register(ctx.app, 'Lim');
    const many = Array.from({ length: 501 }, () => rec('Tag', '2026-08-01T00:00:00.000Z'));
    expect((await push(s, many)).statusCode).toBe(400);
    const big = rec('Transaction', '2026-08-01T00:00:00.000Z', { note: 'x'.repeat(70 * 1024) });
    expect((await push(s, [big])).statusCode).toBe(413);
    const huge = await ctx.app.inject({ method: 'POST', url: '/api/sync', headers: bearer(s), payload: { records: [rec('Tag', '2026-08-01T00:00:00.000Z', { n: 'x'.repeat(3 * 1024 * 1024) })] } });
    expect(huge.statusCode).toBe(413);
  });

  it('aceita ids em maiúsculas (Swift UUID.uuidString) e devolve minúsculas no pull', async () => {
    const s = await register(ctx.app, 'Upper');
    const id = randomUUID().toUpperCase();
    const r = rec('Tag', '2026-08-02T00:00:00.000Z', { name: 'x' }, { id });
    expect((await push(s, [r])).json().accepted).toEqual([id]);
    expect((await pull(s)).json().records[0].id).toBe(id.toLowerCase());
    // reenviar com o id em outra caixa não duplica
    await push(s, [{ ...r, id: id.toLowerCase(), updatedAt: '2026-08-03T00:00:00.000Z' }]);
    expect((await pull(s)).json().records).toHaveLength(1);
  });
});
