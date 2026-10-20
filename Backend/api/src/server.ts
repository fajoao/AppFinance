import pg from 'pg';
import { buildApp } from './app.js';
import { loadConfig } from './config.js';
import { migrate } from './migrate.js';

const cfg = loadConfig();
const pool = new pg.Pool({ connectionString: cfg.databaseUrl, max: 10 });
pool.on('error', (e) => console.error(JSON.stringify({ level: 'error', msg: 'pool', code: (e as { code?: string }).code })));

async function waitForDb(): Promise<void> {
  for (let i = 0; i < 30; i++) {
    try {
      await pool.query('SELECT 1');
      return;
    } catch {
      await new Promise((r) => setTimeout(r, 1000));
    }
  }
  throw new Error('Banco indisponível');
}

await waitForDb();
const app = await buildApp(cfg, pool);
await migrate(pool, cfg.migrationsDir, (m) => app.log.info(m));
await app.listen({ host: '0.0.0.0', port: cfg.port });

for (const sig of ['SIGINT', 'SIGTERM'] as const) {
  process.on(sig, () => {
    app.close().then(() => pool.end()).finally(() => process.exit(0));
  });
}
