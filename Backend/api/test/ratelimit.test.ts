import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { PASSWORD, register, setup, type Ctx } from './helpers.js';

let ctx: Ctx;
beforeAll(async () => {
  ctx = await setup({ RATE_LIMIT_LOGIN: '3', RATE_LIMIT_GLOBAL: '20', LOCKOUT_FREE_ATTEMPTS: '100' });
});
afterAll(async () => { await ctx.close(); });

describe('rate limit', () => {
  it('limita o login por IP (429 após o máximo)', async () => {
    const s = await register(ctx.app, 'Rl');
    const codes: number[] = [];
    for (let i = 0; i < 5; i++) {
      const r = await ctx.app.inject({ method: 'POST', url: '/api/auth/login', payload: { email: s.email, password: i === 0 ? PASSWORD : 'errada-errada' } });
      codes.push(r.statusCode);
    }
    expect(codes).toEqual([200, 401, 401, 429, 429]);
  });

  it('limite geral protege as demais rotas', async () => {
    const codes = new Set<number>();
    for (let i = 0; i < 30; i++) codes.add((await ctx.app.inject({ method: 'GET', url: '/api/health' })).statusCode);
    expect(codes.has(200)).toBe(true);
    expect(codes.has(429)).toBe(true);
  });
});
