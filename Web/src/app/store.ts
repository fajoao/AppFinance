import { create } from 'zustand'
import {
  COLLECTION, ENTITY_TYPES, EntityMap, EntityType, Snapshot, Tombstone, UUID, YearMonth, decodeEntity, emptySnapshot, encodeEntity, newId, todayCivil, ymOf,
} from '../core'
import { QueueItem, StoredEntity, db, entityKey } from './db'
import { Session } from './api'

export type Theme = 'system' | 'light' | 'dark'
export interface Settings {
  theme: Theme
  hideValues: boolean
  onboarded: boolean
  /** Usa o app sem conta (dados só neste aparelho). */
  localMode: boolean
  /** Perfil ativo (FamilyMember.id), quando há grupo familiar. */
  activeMemberId?: UUID
  scope: 'family' | 'individual'
  budgetAlertsSeen: Record<string, number>
  /** Dias de antecedência do aviso de vencimento. */
  reminderDays: number
}
const DEFAULT_SETTINGS: Settings = { theme: 'system', hideValues: false, onboarded: false, localMode: false, scope: 'family', budgetAlertsSeen: {}, reminderDays: 3 }

export interface SyncInfo {
  status: 'off' | 'idle' | 'syncing' | 'error' | 'offline'
  lastSyncAt?: number
  error?: string
  pending: number
}
export interface Toast { id: number; text: string; tone: 'info' | 'warn' | 'danger' }

export type Change = { put: { [T in EntityType]: [T, EntityMap[T]] }[EntityType][]; del: [EntityType, UUID][] }

export interface AppState {
  ready: boolean
  data: Snapshot
  settings: Settings
  session: Session | null
  syncInfo: SyncInfo
  month: YearMonth
  toasts: Toast[]
  init(): Promise<void>
  /** Relê as entidades gravadas no IndexedDB para o estado. */
  reload(): Promise<void>
  /** Aplica criações/edições/exclusões: atualiza o estado, grava no IndexedDB e enfileira para sincronizar. */
  commit(change: Partial<Change>, opts?: { fromRemote?: boolean }): void
  put<T extends EntityType>(type: T, e: EntityMap[T]): void
  putMany<T extends EntityType>(type: T, list: EntityMap[T][]): void
  del(type: EntityType, ...ids: UUID[]): void
  setSettings(p: Partial<Settings>): void
  setMonth(m: YearMonth): void
  setSession(s: Session | null): Promise<void>
  setSyncInfo(p: Partial<SyncInfo>): void
  toast(text: string, tone?: Toast['tone']): void
  dismissToast(id: number): void
  /** Apaga todos os dados locais (conta e preferências ficam). */
  wipeData(): Promise<void>
}

let toastSeq = 1
let syncHook: (() => void) | null = null
export const onChangeNeedsSync = (fn: () => void): void => { syncHook = fn }

function applyTheme(t: Theme): void {
  const dark = t === 'dark' || (t === 'system' && typeof matchMedia !== 'undefined' && matchMedia('(prefers-color-scheme: dark)').matches)
  document.documentElement.dataset.theme = dark ? 'dark' : 'light'
  document.querySelector('meta[name="theme-color"]')?.setAttribute('content', dark ? '#0E1513' : '#EEF2EF')
}

export const useApp = create<AppState>((set, get) => ({
  ready: false,
  data: emptySnapshot(),
  settings: DEFAULT_SETTINGS,
  session: null,
  syncInfo: { status: 'off', pending: 0 },
  month: ymOf(todayCivil()),
  toasts: [],

  async init() {
    const [stored, queue, settings, session, lastSync] = await Promise.all([
      db.allEntities(), db.allQueue(), db.getMeta<Settings>('settings'), db.getMeta<Session>('session'), db.getMeta<number>('lastSyncAt'),
    ])
    const data = emptySnapshot()
    for (const s of stored) {
      const t = s.type as EntityType
      if (!COLLECTION[t]) continue
      ;(data[COLLECTION[t]] as unknown[]).push(decodeEntity(t, s.data))
    }
    const merged = { ...DEFAULT_SETTINGS, ...(settings ?? {}) }
    applyTheme(merged.theme)
    set({
      ready: true, data, settings: merged, session: session ?? null,
      syncInfo: { status: session ? 'idle' : 'off', pending: queue.length, lastSyncAt: lastSync },
    })
  },

  async reload() {
    const stored = await db.allEntities()
    const data = emptySnapshot()
    for (const s of stored) {
      const t = s.type as EntityType
      if (COLLECTION[t]) (data[COLLECTION[t]] as unknown[]).push(decodeEntity(t, s.data))
    }
    set({ data, syncInfo: { ...get().syncInfo, pending: (await db.allQueue()).length } })
  },

  commit(change, opts) {
    const put = change.put ?? [], del = change.del ?? []
    if (put.length === 0 && del.length === 0) return
    const state = get()
    const data: Snapshot = { ...state.data }
    const touched = new Set<EntityType>()
    for (const [t] of put) touched.add(t)
    for (const [t] of del) touched.add(t)
    for (const t of touched) (data[COLLECTION[t]] as unknown[]) = [...(data[COLLECTION[t]] as unknown[])]
    const rows: StoredEntity[] = [], queue: QueueItem[] = [], delKeys: string[] = [], delQueue: string[] = []
    for (const [t, e] of put) {
      const list = data[COLLECTION[t]] as { id: UUID }[]
      const i = list.findIndex((x) => x.id === e.id)
      if (i >= 0) list[i] = e
      else list.push(e)
      rows.push({ key: entityKey(t, e.id), type: t, id: e.id, data: encodeEntity(t, e as never) })
      if (opts?.fromRemote) delQueue.push(entityKey(t, e.id))
      else queue.push({ key: entityKey(t, e.id), type: t, id: e.id, deleted: false, updatedAt: e.updatedAt.toISOString() })
    }
    for (const [t, id] of del) {
      const list = data[COLLECTION[t]] as { id: UUID }[]
      const i = list.findIndex((x) => x.id === id)
      if (i >= 0) list.splice(i, 1)
      delKeys.push(entityKey(t, id))
      if (opts?.fromRemote) delQueue.push(entityKey(t, id))
      else queue.push({ key: entityKey(t, id), type: t, id, deleted: true, updatedAt: new Date().toISOString() })
    }
    set({ data })
    void (async () => {
      try {
        if (rows.length) await db.putEntities(rows)
        if (delKeys.length) await db.deleteEntities(delKeys)
        if (delQueue.length) await db.deleteQueue(delQueue)
        if (queue.length) await db.putQueue(queue)
        const pending = (await db.allQueue()).length
        get().setSyncInfo({ pending })
        if (!opts?.fromRemote && get().session) syncHook?.()
      } catch (e) {
        get().toast('Não foi possível salvar neste aparelho: ' + (e instanceof Error ? e.message : 'erro'), 'danger')
      }
    })()
  },

  put(type, e) { get().commit({ put: [[type, { ...e, updatedAt: new Date() }]] as unknown as Change['put'] }) },
  putMany(type, list) {
    const now = new Date()
    get().commit({ put: list.map((e) => [type, { ...e, updatedAt: now }]) as unknown as Change['put'] })
  },
  del(type, ...ids) {
    const tombs: Tombstone[] = ids.map((id) => {
      const now = new Date()
      return { id: newId(), entityType: type, entityId: id, deletedAt: now, createdAt: now, updatedAt: now }
    })
    get().commit({ del: ids.map((id) => [type, id] as [EntityType, UUID]), put: type === 'Tombstone' ? [] : tombs.map((t) => ['Tombstone', t] as ['Tombstone', Tombstone]) })
  },

  setSettings(p) {
    const settings = { ...get().settings, ...p }
    set({ settings })
    if (p.theme) applyTheme(p.theme)
    void db.setMeta('settings', settings)
  },
  setMonth: (month) => set({ month }),

  async setSession(s) {
    set({ session: s, syncInfo: { ...get().syncInfo, status: s ? 'idle' : 'off', error: undefined } })
    if (s) await db.setMeta('session', s)
    else await db.delMeta('session')
  },
  setSyncInfo: (p) => set({ syncInfo: { ...get().syncInfo, ...p } }),

  toast(text, tone = 'info') {
    const id = toastSeq++
    set({ toasts: [...get().toasts, { id, text, tone }] })
    setTimeout(() => get().dismissToast(id), 4500)
  },
  dismissToast: (id) => set({ toasts: get().toasts.filter((t) => t.id !== id) }),

  async wipeData() {
    await db.clearData()
    await db.delMeta('syncToken')
    set({ data: emptySnapshot(), syncInfo: { ...get().syncInfo, pending: 0 } })
  },
}))

if (typeof matchMedia !== 'undefined') {
  matchMedia('(prefers-color-scheme: dark)').addEventListener?.('change', () => {
    if (useApp.getState().settings.theme === 'system') applyTheme('system')
  })
}

export { ENTITY_TYPES }
