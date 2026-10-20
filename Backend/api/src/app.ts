import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import Fastify, { type FastifyInstance } from 'fastify';
import type pg from 'pg';
import { ZodError } from 'zod';
import { Tokens } from './auth.js';
import type { Config } from './config.js';
import { HttpError } from './errors.js';
import { authRoutes } from './routes/auth.js';
import { householdRoutes } from './routes/households.js';
import { syncRoutes } from './routes/sync.js';

export async function buildApp(cfg: Config, pool: pg.Pool): Promise<FastifyInstance> {
  const app = Fastify({
    trustProxy: cfg.trustProxy,
    bodyLimit: cfg.bodyLimitBytes,
    logger: {
      level: cfg.logLevel,
      // Nunca logar corpo, cabeçalhos (Authorization), query string nem tokens: só método, rota sem query e IP.
      serializers: {
        req: (req) => ({ method: req.method, url: String(req.url).split('?')[0], ip: req.ip }),
        res: (res) => ({ statusCode: res.statusCode }),
      },
      redact: { paths: ['req.headers', 'res.headers'], remove: true },
    },
  });

  await app.register(helmet, { contentSecurityPolicy: { directives: { defaultSrc: ["'none'"], frameAncestors: ["'none'"] } } });
  await app.register(cors, {
    origin: cfg.corsOrigins.length ? cfg.corsOrigins : false,
    methods: ['GET', 'POST', 'OPTIONS'],
    allowedHeaders: ['Authorization', 'Content-Type'],
    maxAge: 600,
  });
  await app.register(rateLimit, {
    global: true,
    max: cfg.rateLimits.global,
    timeWindow: cfg.rateLimits.windowMs,
    errorResponseBuilder: (_req, ctx) => ({
      statusCode: 429,
      error: 'rate_limited',
      message: 'Muitas requisições. Tente novamente em instantes.',
      retryAfter: Math.ceil(ctx.ttl / 1000),
    }),
  });

  app.setErrorHandler((err: unknown, req, reply) => {
    if (err instanceof HttpError) {
      return reply.code(err.status).send({ error: err.code, message: err.message, ...err.extra });
    }
    if (err instanceof ZodError) {
      return reply.code(400).send({
        error: 'validation_error',
        message: 'Requisição inválida.',
        issues: err.issues.map((i) => ({ path: i.path.join('.'), message: i.message })),
      });
    }
    const e = err as { statusCode?: number; code?: string; message?: string };
    if (typeof e.statusCode === 'number' && e.statusCode < 500) {
      if (e.statusCode === 429) return reply.code(429).send(err as object);
      const code = e.statusCode === 413 ? 'payload_too_large' : 'bad_request';
      return reply.code(e.statusCode).send({ error: code, message: e.statusCode === 413 ? 'Corpo grande demais.' : 'Requisição inválida.' });
    }
    // Só o código do erro é logado (a mensagem de driver/SQL pode conter valores).
    req.log.error({ code: e.code, name: (err as Error)?.name }, 'erro interno');
    return reply.code(500).send({ error: 'internal_error', message: 'Erro interno.' });
  });
  app.setNotFoundHandler((_req, reply) => reply.code(404).send({ error: 'not_found', message: 'Rota não encontrada.' }));

  app.get('/api/health', async (_req, reply) => {
    try {
      await pool.query('SELECT 1');
      return { status: 'ok', db: 'up' };
    } catch {
      return reply.code(503).send({ status: 'degraded', db: 'down' });
    }
  });

  const tokens = new Tokens(cfg, pool);
  authRoutes(app, cfg, pool, tokens);
  householdRoutes(app, cfg, pool, tokens);
  syncRoutes(app, cfg, pool, tokens);
  return app;
}
