import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { bearer, rec, register, setup, type Ctx } from './helpers.js';

let ctx: Ctx;
beforeAll(async () => { ctx = await setup(); });
afterAll(async () => { await ctx.close(); });

const invite = (s: Parameters<typeof bearer>[0], payload: object = {}) =>
  ctx.app.inject({ method: 'POST', url: '/api/households/invite', headers: bearer(s), payload });
const join = (s: Parameters<typeof bearer>[0], code: string) =>
  ctx.app.inject({ method: 'POST', url: '/api/households/join', headers: bearer(s), payload: { code } });

describe('convites', () => {
  it('admin convida; o convidado entra e passa a ver os dados da casa', async () => {
    const admin = await register(ctx.app, 'Admin');
    const guest = await register(ctx.app, 'Guest');
    const r = rec('Account', '2026-09-01T00:00:00.000Z', { name: 'Conta da casa' });
    await ctx.app.inject({ method: 'POST', url: '/api/sync', headers: bearer(admin), payload: { records: [r] } });

    const inv = await invite(admin);
    expect(inv.statusCode).toBe(201);
    const { code, expiresAt } = inv.json();
    expect(code).toMatch(/^[A-Z2-9]{4}-[A-Z2-9]{4}$/);
    const ttl = new Date(expiresAt).getTime() - Date.now();
    expect(ttl).toBeGreaterThan(47.9 * 3600e3);
    expect(ttl).toBeLessThanOrEqual(48 * 3600e3);

    const j = await join(guest, code.toLowerCase().replace('-', ' '));
    expect(j.statusCode).toBe(200);
    expect(j.json().household).toMatchObject({ id: admin.householdId, role: 'member' });

    const seen = await ctx.app.inject({ method: 'GET', url: '/api/sync', headers: bearer(guest) });
    expect(seen.json().records.map((x: { id: string }) => x.id)).toEqual([r.id]);
    const me = await ctx.app.inject({ method: 'GET', url: '/api/me', headers: bearer(guest) });
    expect(me.json().members).toHaveLength(2);
    // a casa antiga (vazia) do convidado foi removida
    const old = await ctx.pool.query('SELECT 1 FROM households WHERE id = $1', [guest.householdId]);
    expect(old.rowCount).toBe(0);
  });

  it('código é de uso único', async () => {
    const admin = await register(ctx.app, 'Admin1');
    const g1 = await register(ctx.app, 'G1');
    const g2 = await register(ctx.app, 'G2');
    const { code } = (await invite(admin)).json();
    expect((await join(g1, code)).statusCode).toBe(200);
    const again = await join(g2, code);
    expect(again.statusCode).toBe(404);
    expect(again.json().error).toBe('invalid_code');
  });

  it('código expirado ou inexistente falha', async () => {
    const admin = await register(ctx.app, 'Admin2');
    const g = await register(ctx.app, 'G3');
    const { code } = (await invite(admin)).json();
    await ctx.pool.query(`UPDATE invites SET expires_at = now() - interval '1 minute' WHERE household_id = $1`, [admin.householdId]);
    expect((await join(g, code)).statusCode).toBe(404);
    expect((await join(g, 'ZZZZ-ZZZZ')).statusCode).toBe(404);
  });

  it('só admin convida; dependente entra com papel dependent e não grava Household/FamilyMember', async () => {
    const admin = await register(ctx.app, 'Admin3');
    const kid = await register(ctx.app, 'Kid');
    const { code } = (await invite(admin, { role: 'dependent' })).json();
    expect((await join(kid, code)).json().household.role).toBe('dependent');
    expect((await invite(kid)).statusCode).toBe(403);
    const forbidden = rec('FamilyMember', '2026-09-02T00:00:00.000Z', { name: 'x' });
    const ok = rec('Transaction', '2026-09-02T00:00:00.000Z', { title: 'lanche' });
    const res = await ctx.app.inject({ method: 'POST', url: '/api/sync', headers: bearer(kid), payload: { records: [forbidden, ok] } });
    expect(res.json().accepted).toEqual([ok.id]);
    expect(res.json().rejected[0]).toMatchObject({ id: forbidden.id, reason: 'forbidden_role' });
  });

  it('quem já tem dados não troca de casa e o convite não é consumido', async () => {
    const admin = await register(ctx.app, 'Admin4');
    const owner = await register(ctx.app, 'Owner');
    await ctx.app.inject({ method: 'POST', url: '/api/sync', headers: bearer(owner), payload: { records: [rec('Tag', '2026-09-03T00:00:00.000Z')] } });
    const { code } = (await invite(admin)).json();
    const r = await join(owner, code);
    expect(r.statusCode).toBe(409);
    expect(r.json().error).toBe('household_not_empty');
    const g = await register(ctx.app, 'Late');
    expect((await join(g, code)).statusCode).toBe(200); // convite continuou válido
  });
});
