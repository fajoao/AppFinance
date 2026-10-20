import { dateToWire } from './codec'
import {
  COLLECTION, ENTITY_TYPES, EntityMap, EntityType, Snapshot, Tombstone, UUID, emptySnapshot, newId,
} from './models'

// Regra de conflito do Core (SyncEngine.merge): vence o maior updatedAt; exclusões (tombstones) vencem
// edições anteriores à exclusão (deletedAt >= updatedAt).

export interface MergeReport { applied: number; keptLocal: number; deleted: number }

function canonical(v: unknown): string {
  return JSON.stringify(v, (_k, x) => {
    if (x instanceof Date) return dateToWire(x)
    if (x && typeof x === 'object' && !Array.isArray(x) && typeof (x as { toFixed?: unknown }).toFixed === 'function') return String(x)
    if (x && typeof x === 'object' && !Array.isArray(x)) return Object.fromEntries(Object.entries(x).sort(([a], [b]) => (a < b ? -1 : 1)))
    return x
  })
}

/** Vence o remoto? Retorna 'remote' | 'local'. Empate com conteúdo diferente: desempate determinístico. */
export function resolveConflict<T extends { updatedAt: Date }>(local: T, remote: T): 'remote' | 'local' {
  const l = local.updatedAt.getTime(), r = remote.updatedAt.getTime()
  if (r > l) return 'remote'
  if (r < l) return 'local'
  const cr = canonical(remote), cl = canonical(local)
  return cr !== cl && cr > cl ? 'remote' : 'local'
}

function mergeCollection<T extends { id: UUID; updatedAt: Date }>(local: T[], remote: T[], report: MergeReport): T[] {
  const result = [...local]
  const index = new Map<UUID, number>(result.map((e, i) => [e.id, i]))
  for (const r of remote) {
    const i = index.get(r.id)
    if (i === undefined) { index.set(r.id, result.length); result.push(r); report.applied++; continue }
    const l = result[i]!
    const same = canonical(l) === canonical(r)
    if (r.updatedAt.getTime() > l.updatedAt.getTime()) { result[i] = r; report.applied++ }
    else if (r.updatedAt.getTime() < l.updatedAt.getTime()) report.keptLocal++
    else if (!same) {
      if (resolveConflict(l, r) === 'remote') { result[i] = r; report.applied++ } else report.keptLocal++
    }
  }
  return result
}

function applyTombstones<T extends { id: UUID; updatedAt: Date }>(type: EntityType, list: T[], tombstones: Tombstone[], report: MergeReport): T[] {
  const deletedAt = new Map<UUID, number>()
  for (const t of tombstones) if (t.entityType === type) deletedAt.set(t.entityId, Math.max(deletedAt.get(t.entityId) ?? -Infinity, t.deletedAt.getTime()))
  if (deletedAt.size === 0) return list
  return list.filter((e) => {
    const when = deletedAt.get(e.id)
    if (when === undefined || when < e.updatedAt.getTime()) return true
    report.deleted++
    return false
  })
}

export function mergeSnapshots(local: Snapshot, remote: Snapshot): { snapshot: Snapshot; report: MergeReport } {
  const report: MergeReport = { applied: 0, keptLocal: 0, deleted: 0 }
  const out = emptySnapshot()
  out.version = Math.max(local.version, remote.version)
  const ignored: MergeReport = { applied: 0, keptLocal: 0, deleted: 0 }
  const tombstones = mergeCollection(local.tombstones, remote.tombstones, ignored).sort((a, b) => a.deletedAt.getTime() - b.deletedAt.getTime())
  out.tombstones = tombstones
  for (const t of ENTITY_TYPES) {
    if (t === 'Tombstone') continue
    const key = COLLECTION[t]
    const merged = mergeCollection(local[key] as { id: UUID; updatedAt: Date }[], remote[key] as { id: UUID; updatedAt: Date }[], report)
    ;(out[key] as unknown[]) = applyTombstones(t, merged, tombstones, report)
  }
  return { snapshot: out, report }
}

export function snapshotCount(s: Snapshot): number {
  return ENTITY_TYPES.reduce((n, t) => n + (s[COLLECTION[t]] as unknown[]).length, 0)
}

export function makeTombstone(type: EntityType, entityId: UUID, now = new Date()): Tombstone {
  return { id: newId(), entityType: type, entityId, deletedAt: now, createdAt: now, updatedAt: now }
}

export type { EntityMap }
