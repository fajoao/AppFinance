import { randomUUID } from 'node:crypto';
import type { FastifyReply, FastifyRequest } from 'fastify';
import { SignJWT, jwtVerify } from 'jose';
import type pg from 'pg';
import type { Config } from './config.js';
import { HttpError } from './errors.js';
import { newRefreshToken, sha256 } from './security.js';

export type Role = 'admin' | 'member' | 'dependent';

export interface AuthContext {
  userId: string;
  email: string;
  name: string;
  householdId: string;
  householdName: string;
  role: Role;
}

declare module 'fastify' {
  interface FastifyRequest {
    auth?: AuthContext;
  }
}

const ISSUER = 'finance-api';
const AUDIENCE = 'finance-app';

export class Tokens {
  private readonly key: Uint8Array;
  constructor(private readonly cfg: Config, private readonly pool: pg.Pool) {
    this.key = new TextEncoder().encode(cfg.jwtSecret);
  }

  signAccess(userId: string): Promise<string> {
    return new SignJWT({})
      .setProtectedHeader({ alg: 'HS256' })
      .setSubject(userId)
      .setIssuer(ISSUER)
      .setAudience(AUDIENCE)
      .setIssuedAt()
      .setExpirationTime(`${this.cfg.accessTtlSec}s`)
      .setJti(randomUUID())
      .sign(this.key);
  }

  async verifyAccess(token: string): Promise<string> {
    const { payload } = await jwtVerify(token, this.key, { issuer: ISSUER, audience: AUDIENCE, algorithms: ['HS256'] });
    if (!payload.sub) throw new Error('sem sub');
    return payload.sub;
  }

  /** Cria um refresh token (nova família se `familyId` não for informado). */
  async issueRefresh(client: Pick<pg.PoolClient, 'query'>, userId: string, familyId: string = randomUUID()): Promise<string> {
    const token = newRefreshToken();
    await client.query(
      `INSERT INTO refresh_tokens (user_id, family_id, token_hash, expires_at)
       VALUES ($1,$2,$3, now() + make_interval(days => $4))`,
      [userId, familyId, sha256(token), this.cfg.refreshTtlDays],
    );
    return token;
  }

  async pair(client: Pick<pg.PoolClient, 'query'>, userId: string, familyId?: string) {
    return {
      accessToken: await this.signAccess(userId),
      refreshToken: await this.issueRefresh(client, userId, familyId),
      expiresIn: this.cfg.accessTtlSec,
      tokenType: 'Bearer' as const,
    };
  }
}

/** preHandler: valida o JWT e carrega usuário/household/papel do banco (revogações valem na hora). */
export function requireAuth(tokens: Tokens, pool: pg.Pool) {
  return async (req: FastifyRequest, _reply: FastifyReply): Promise<void> => {
    const header = req.headers.authorization;
    if (!header?.startsWith('Bearer ')) throw new HttpError(401, 'unauthorized', 'Token ausente.');
    let userId: string;
    try {
      userId = await tokens.verifyAccess(header.slice(7));
    } catch {
      throw new HttpError(401, 'unauthorized', 'Token inválido ou expirado.');
    }
    const { rows } = await pool.query(
      `SELECT u.id, u.email, u.name, m.household_id, m.role, h.name AS household_name
       FROM users u JOIN memberships m ON m.user_id = u.id JOIN households h ON h.id = m.household_id
       WHERE u.id = $1 AND NOT u.disabled`,
      [userId],
    );
    const r = rows[0];
    if (!r) throw new HttpError(401, 'unauthorized', 'Usuário inválido.');
    req.auth = {
      userId: r.id, email: r.email, name: r.name, householdId: r.household_id, householdName: r.household_name, role: r.role,
    };
  };
}

export function auth(req: FastifyRequest): AuthContext {
  if (!req.auth) throw new HttpError(401, 'unauthorized', 'Não autenticado.');
  return req.auth;
}
