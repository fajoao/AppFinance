import type pg from 'pg';

export interface AuditEntry {
  householdId?: string | null;
  userId?: string | null;
  action: string;
  entityType?: string | null;
  entityId?: string | null;
  detail?: Record<string, unknown>;
  ip?: string | null;
}

type Queryable = Pick<pg.Pool | pg.PoolClient, 'query'>;

/** Auditoria só guarda metadados (quem, o quê, quando). Nunca valores financeiros nem tokens. */
export async function audit(db: Queryable, e: AuditEntry): Promise<void> {
  await db.query(
    `INSERT INTO audit_log (household_id, user_id, action, entity_type, entity_id, detail, ip)
     VALUES ($1,$2,$3,$4,$5,$6,$7)`,
    [e.householdId ?? null, e.userId ?? null, e.action, e.entityType ?? null, e.entityId ?? null, JSON.stringify(e.detail ?? {}), e.ip ?? null],
  );
}
