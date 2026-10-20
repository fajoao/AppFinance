// Regra de conflito do Core (SyncEngine) aplicada no servidor:
//  1. vence o maior updatedAt;
//  2. empate de updatedAt: exclusão (tombstone) vence edição (Core: tombstone vale se deletedAt >= updatedAt);
//  3. empate e mesmo estado de exclusão: desempate determinístico pelo conteúdo canônico (ordem lexicográfica do
//     JSON com chaves ordenadas), igual ao Core, para todos os dispositivos convergirem ao mesmo documento;
//  4. conteúdo idêntico = nada a fazer (idempotente).

export interface Versioned {
  updatedAtMs: number;
  deleted: boolean;
  data: unknown;
}

export function stableStringify(v: unknown): string {
  if (Array.isArray(v)) return `[${v.map(stableStringify).join(',')}]`;
  if (v !== null && typeof v === 'object') {
    const o = v as Record<string, unknown>;
    return `{${Object.keys(o).sort().map((k) => `${JSON.stringify(k)}:${stableStringify(o[k])}`).join(',')}}`;
  }
  return JSON.stringify(v) ?? 'null';
}

export type Decision = 'apply' | 'same' | 'stale' | 'tie_lost';

export function decide(incoming: Versioned, existing: Versioned | undefined): Decision {
  if (!existing) return 'apply';
  if (incoming.updatedAtMs > existing.updatedAtMs) return 'apply';
  if (incoming.updatedAtMs < existing.updatedAtMs) return 'stale';
  if (incoming.deleted !== existing.deleted) return incoming.deleted ? 'apply' : 'tie_lost';
  const a = stableStringify(incoming.data);
  const b = stableStringify(existing.data);
  if (a === b) return 'same';
  return a > b ? 'apply' : 'tie_lost';
}
