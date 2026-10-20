import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { PASSWORD, bearer, register, setup, type Ctx } from './helpers.js';

let ctx: Ctx;
beforeAll(async () => { ctx = await setup(); });
afterAll(async () => { await ctx.close(); });

describe('registro e login', () => {
  it('registra, cria household admin e permite GET /api/me', async () => {
    const s = await register(ctx.app, 'Maria');
    const me = await ctx.app.inject({ method: 'GET', url: '/api/me', headers: bearer(s) });
    expect(me.statusCode).toBe(200);
    expect(me.json().user.email).toBe(s.email);
    expect(me.json().household.role).toBe('admin');
    expect(me.json().household.id).toBe(s.householdId);
  });

  it('guarda a senha como argon2id (nunca em texto)', async () => {
    const s = await register(ctx.app, 'Hash');
    const { rows } = await ctx.pool.query('SELECT password_hash FROM users WHERE email = $1', [s.email]);
    expect(rows[0].password_hash).toMatch(/^\$argon2id\$/);
    expect(rows[0].password_hash).not.toContain(PASSWORD);
  });

  it('rejeita e-mail duplicado (409) e senha fraca (400)', async () => {
    const s = await register(ctx.app, 'Dup');
    const dup = await ctx.app.inject({ method: 'POST', url: '/api/auth/register', payload: { email: s.email.toUpperCase(), password: PASSWORD, name: 'X' } });
    expect(dup.statusCode).toBe(409);
    const weak = await ctx.app.inject({ method: 'POST', url: '/api/auth/register', payload: { email: 'w@example.com', password: 'abc', name: 'W' } });
    expect(weak.statusCode).toBe(400);
  });

  it('login devolve accessToken (JWT) e refreshToken; senha errada = 401 genérico', async () => {
    const s = await register(ctx.app, 'Login');
    const ok = await ctx.app.inject({ method: 'POST', url: '/api/auth/login', payload: { email: s.email, password: PASSWORD } });
    expect(ok.statusCode).toBe(200);
    expect(ok.json().accessToken.split('.')).toHaveLength(3);
    expect(ok.json().refreshToken.length).toBeGreaterThan(20);
    expect(ok.json().expiresIn).toBe(900);
    const bad = await ctx.app.inject({ method: 'POST', url: '/api/auth/login', payload: { email: s.email, password: 'errada-errada' } });
    expect(bad.statusCode).toBe(401);
    const ghost = await ctx.app.inject({ method: 'POST', url: '/api/auth/login', payload: { email: 'naoexiste@example.com', password: 'errada-errada' } });
    expect(ghost.statusCode).toBe(401);
    expect(ghost.json()).toEqual(bad.json());
  });

  it('rotaciona o refresh token, detecta reuso e logout revoga', async () => {
    const s = await register(ctx.app, 'Refresh');
    const r1 = await ctx.app.inject({ method: 'POST', url: '/api/auth/refresh', payload: { refreshToken: s.refreshToken } });
    expect(r1.statusCode).toBe(200);
    const newRefresh = r1.json().refreshToken;
    expect(newRefresh).not.toBe(s.refreshToken);
    // reuso do token antigo derruba a família inteira
    const reuse = await ctx.app.inject({ method: 'POST', url: '/api/auth/refresh', payload: { refreshToken: s.refreshToken } });
    expect(reuse.statusCode).toBe(401);
    const afterReuse = await ctx.app.inject({ method: 'POST', url: '/api/auth/refresh', payload: { refreshToken: newRefresh } });
    expect(afterReuse.statusCode).toBe(401);

    const login = await ctx.app.inject({ method: 'POST', url: '/api/auth/login', payload: { email: s.email, password: PASSWORD } });
    const rt = login.json().refreshToken;
    expect((await ctx.app.inject({ method: 'POST', url: '/api/auth/logout', payload: { refreshToken: rt } })).statusCode).toBe(204);
    expect((await ctx.app.inject({ method: 'POST', url: '/api/auth/refresh', payload: { refreshToken: rt } })).statusCode).toBe(401);
  });

  it('exige token válido e rejeita JWT adulterado', async () => {
    const none = await ctx.app.inject({ method: 'GET', url: '/api/me' });
    expect(none.statusCode).toBe(401);
    const s = await register(ctx.app, 'Jwt');
    const tampered = s.accessToken.slice(0, -3) + (s.accessToken.endsWith('aaa') ? 'bbb' : 'aaa');
    const res = await ctx.app.inject({ method: 'GET', url: '/api/me', headers: { authorization: `Bearer ${tampered}` } });
    expect(res.statusCode).toBe(401);
  });

  it('bloqueio progressivo: após 5 falhas responde 429 com Retry-After, mesmo com a senha certa', async () => {
    const s = await register(ctx.app, 'Lock');
    for (let i = 0; i < 5; i++) {
      const r = await ctx.app.inject({ method: 'POST', url: '/api/auth/login', payload: { email: s.email, password: 'errada-errada' } });
      expect(r.statusCode).toBe(401);
    }
    const locked = await ctx.app.inject({ method: 'POST', url: '/api/auth/login', payload: { email: s.email, password: PASSWORD } });
    expect(locked.statusCode).toBe(429);
    expect(Number(locked.headers['retry-after'])).toBeGreaterThan(0);
  });

  it('health responde ok com o banco', async () => {
    const r = await ctx.app.inject({ method: 'GET', url: '/api/health' });
    expect(r.statusCode).toBe(200);
    expect(r.json()).toEqual({ status: 'ok', db: 'up' });
    expect(r.headers['x-content-type-options']).toBe('nosniff'); // helmet
  });
});
