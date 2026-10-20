import {
  COLLECTION, EntityType, ENTITY_TYPES, Tombstone, decodeEntity, encodeEntity, resolveConflict,
} from '../core'
import { ApiError, SyncRecordWire, authApi, syncApi } from './api'
import { QueueItem, db, entityKey } from './db'
import { Change, onChangeNeedsSync, useApp } from './store'

// Sincronização offline-first. Fila local (IndexedDB) -> POST /api/sync; depois GET /api/sync?since=token.
// Conflito: vence o maior updatedAt (o servidor aplica a mesma regra e devolve `rejected` com o registro vencedor).

const BATCH = 200
let running: Promise<void> | null = null
let again = false
let timer: ReturnType<typeof setTimeout> | null = null

async function accessToken(): Promise<string> {
  const { session, setSession } = useApp.getState()
  if (!session) throw new ApiError(401, 'no_session', 'Entre na sua conta para sincronizar.')
  if (session.expiresAt - 30_000 > Date.now()) return session.accessToken
  try {
    const t = await authApi.refresh(session.refreshToken)
    const next = { ...session, accessToken: t.accessToken, refreshToken: t.refreshToken, expiresAt: Date.now() + (t.expiresIn ?? 900) * 1000 }
    await setSession(next)
    return next.accessToken
  } catch (e) {
    if (e instanceof ApiError && (e.status === 401 || e.code === 'invalid_refresh')) await setSession(null)
    throw e
  }
}

function toWire(item: QueueItem): SyncRecordWire | null {
  if (item.deleted) return { type: item.type, id: item.id, updatedAt: item.updatedAt, deleted: true }
  const t = item.type as EntityType
  const e = (useApp.getState().data[COLLECTION[t]] as { id: string; updatedAt: Date }[]).find((x) => x.id === item.id)
  if (!e) return null
  return { type: t, id: e.id, data: encodeEntity(t, e as never), updatedAt: e.updatedAt.toISOString(), deleted: false }
}

/** Aplica um registro vindo do servidor sem reenfileirar. */
export function applyRemote(rec: SyncRecordWire): void {
  const t = rec.type as EntityType
  if (!ENTITY_TYPES.includes(t)) return
  const st = useApp.getState()
  const list = st.data[COLLECTION[t]] as { id: string; updatedAt: Date }[]
  const local = list.find((x) => x.id.toLowerCase() === rec.id.toLowerCase())
  const when = new Date(rec.updatedAt)
  if (rec.deleted) {
    if (local && local.updatedAt.getTime() <= when.getTime()) st.commit({ del: [[t, local.id]] }, { fromRemote: true })
    return
  }
  if (!rec.data) return
  const remote = decodeEntity(t, rec.data) as { id: string; updatedAt: Date }
  if (local && resolveConflict(local, remote) === 'local') return
  const change: Partial<Change> = { put: [[t, remote]] as Change['put'] }
  if (t === 'Tombstone') {
    const tomb = remote as unknown as Tombstone
    const target = (st.data[COLLECTION[tomb.entityType as EntityType]] as { id: string; updatedAt: Date }[] | undefined)?.find((x) => x.id.toLowerCase() === tomb.entityId.toLowerCase())
    if (target && tomb.deletedAt.getTime() >= target.updatedAt.getTime()) change.del = [[tomb.entityType as EntityType, target.id]]
  }
  st.commit(change, { fromRemote: true })
}

async function runOnce(): Promise<void> {
  const st = useApp.getState()
  if (!st.session) return
  st.setSyncInfo({ status: 'syncing', error: undefined })
  // 1) push
  for (;;) {
    const queue = (await db.allQueue()).slice(0, BATCH)
    if (queue.length === 0) break
    const records: SyncRecordWire[] = []
    const dropped: string[] = []
    for (const q of queue) {
      const w = toWire(q)
      if (w) records.push(w)
      else dropped.push(q.key)
    }
    if (dropped.length) await db.deleteQueue(dropped)
    if (records.length === 0) continue
    const res = await syncApi.push(await accessToken(), records)
    const done = new Set<string>(res.accepted.map((i) => i.toLowerCase()))
    const keys: string[] = []
    for (const r of records) if (done.has(r.id.toLowerCase())) keys.push(entityKey(r.type, r.id))
    for (const rej of res.rejected) {
      const rec = records.find((r) => r.id.toLowerCase() === rej.id.toLowerCase())
      if (!rec) continue
      keys.push(entityKey(rec.type, rec.id))
      if (rej.reason === 'forbidden_role') {
        useApp.getState().toast('Seu papel na família não permite alterar um dos registros; ele foi restaurado.', 'warn')
      }
      if (rej.serverRecord) applyRemote(rej.serverRecord)
    }
    // só remove da fila o que não foi editado durante o envio (updatedAt igual ao enviado)
    const sent = new Map(records.map((r) => [entityKey(r.type, r.id), r.updatedAt]))
    const current = new Map((await db.allQueue()).map((q) => [q.key, q.updatedAt]))
    await db.deleteQueue(keys.filter((k) => current.get(k) === undefined || current.get(k) === sent.get(k)))
    if (keys.length === 0) break
  }
  // 2) pull
  let since = (await db.getMeta<number>('syncToken')) ?? 0
  for (let guard = 0; guard < 1000; guard++) {
    const page = await syncApi.pull(await accessToken(), since)
    for (const rec of page.records) applyRemote(rec)
    since = page.token
    await db.setMeta('syncToken', since)
    if (!page.hasMore) break
  }
  const now = Date.now()
  await db.setMeta('lastSyncAt', now)
  useApp.getState().setSyncInfo({ status: 'idle', lastSyncAt: now, pending: (await db.allQueue()).length, error: undefined })
}

/** Sincroniza agora. Chamadas concorrentes se juntam; mudanças durante o envio disparam nova rodada. */
export function syncNow(): Promise<void> {
  if (running) { again = true; return running }
  running = (async () => {
    try {
      do {
        again = false
        await runOnce()
      } while (again)
    } catch (e) {
      const offline = e instanceof ApiError && e.status === 0
      useApp.getState().setSyncInfo({ status: offline ? 'offline' : 'error', error: e instanceof Error ? e.message : 'Falha ao sincronizar' })
    } finally {
      running = null
    }
  })()
  return running
}

/** Agenda sincronização (debounce) após alterações locais. */
export function scheduleSync(): void {
  if (timer) clearTimeout(timer)
  timer = setTimeout(() => void syncNow(), 800)
}

export function startSyncLoop(): void {
  onChangeNeedsSync(scheduleSync)
  if (typeof window === 'undefined') return
  window.addEventListener('online', () => void syncNow())
  document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible' && useApp.getState().session) void syncNow() })
  setInterval(() => { if (useApp.getState().session && document.visibilityState === 'visible') void syncNow() }, 60_000)
  if (useApp.getState().session) void syncNow()
}
