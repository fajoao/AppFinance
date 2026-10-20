import { Decimal, dec } from './decimal'
import { COLLECTION, ENTITY_TYPES, EntityMap, EntityType, Snapshot, emptySnapshot } from './models'

// Formato de rede/armazenamento = JSON Codable do Core Swift (JSONFileStore.encoder):
//  - Date: segundos desde 2001-01-01 UTC (Double, deferredToDate)
//  - Decimal: número JSON; UUID: string maiúscula; YearMonth: {year, month}; nil: campo ausente.
const REF = 978_307_200 // 1970 -> 2001

export const dateFromWire = (secs: number): Date => new Date(Math.round((secs + REF) * 1000))
export const dateToWire = (d: Date): number => d.getTime() / 1000 - REF
const decFromWire = (v: unknown): Decimal => (typeof v === 'string' ? dec(v) : dec(Number(v)))
const decToWire = (d: Decimal): number => d.toNumber()

interface Schema {
  dec?: string[]
  date?: string[]
  /** campos de objetos aninhados */
  nested?: Record<string, { dec?: string[]; date?: string[]; list?: boolean }>
  defaults?: Record<string, unknown>
}

const BASE_DATES = ['createdAt', 'updatedAt']
const SCHEMA: Record<EntityType, Schema> = {
  Account: { dec: ['initialBalance'], date: BASE_DATES, defaults: { currency: 'BRL', isArchived: false, visibility: 'shared' } },
  Category: { date: BASE_DATES, defaults: { visibility: 'shared' } },
  Tag: { date: BASE_DATES },
  Transaction: {
    dec: ['amount'], date: [...BASE_DATES, 'date'],
    nested: { recurrence: { date: ['endDate'] } }, defaults: { status: 'paid', tagIds: [] },
  },
  CreditCard: { dec: ['limit'], date: BASE_DATES, defaults: { isArchived: false } },
  Invoice: { dec: ['paidAmount'], date: [...BASE_DATES, 'closingDate', 'dueDate', 'paidAt'], defaults: { paidAmount: 0 } },
  Budget: { dec: ['limit'], date: BASE_DATES },
  Goal: { dec: ['targetAmount', 'currentAmount'], date: [...BASE_DATES, 'deadline'], defaults: { currentAmount: 0 } },
  Debt: { dec: ['balance', 'monthlyInterestRate', 'minimumPayment'], date: BASE_DATES },
  Household: { date: BASE_DATES },
  FamilyMember: { dec: ['monthlySpendingLimit'], date: BASE_DATES, defaults: { role: 'member' } },
  GoalContribution: { dec: ['amount'], date: [...BASE_DATES, 'date'] },
  Investment: { dec: ['quantity', 'averagePrice', 'quote', 'realizedProfit'], date: [...BASE_DATES, 'quoteDate'], defaults: { realizedProfit: 0 } },
  NetWorthSnapshot: { dec: ['assets', 'liabilities'], date: BASE_DATES },
  ExpenseSplit: { dec: ['total'], date: [...BASE_DATES, 'date'], nested: { shares: { dec: ['percent', 'amount'], list: true } } },
  SplitSettlement: { dec: ['amount'], date: [...BASE_DATES, 'date'] },
  Allowance: { dec: ['amount'], date: BASE_DATES, defaults: { isActive: true } },
  ApprovalRequest: { dec: ['amount'], date: [...BASE_DATES, 'date', 'decidedAt'], defaults: { status: 'pending' } },
  Tombstone: { date: [...BASE_DATES, 'deletedAt'] },
}

type Obj = Record<string, unknown>

function conv(o: Obj, decs: string[] | undefined, dates: string[] | undefined, toWire: boolean) {
  for (const k of decs ?? []) {
    const v = o[k]
    if (v === undefined || v === null) continue
    o[k] = toWire ? decToWire(v as Decimal) : decFromWire(v)
  }
  for (const k of dates ?? []) {
    const v = o[k]
    if (v === undefined || v === null) continue
    o[k] = toWire ? dateToWire(v as Date) : dateFromWire(Number(v))
  }
}

/** JSON de rede (Codable do Swift) -> entidade de domínio. Tolerante a campos ausentes (dados antigos). */
export function decodeEntity<T extends EntityType>(type: T, wire: unknown): EntityMap[T] {
  const s = SCHEMA[type]
  const o: Obj = { ...(wire as Obj) }
  for (const [k, v] of Object.entries(s.defaults ?? {})) if (o[k] === undefined) o[k] = Array.isArray(v) ? [...v] : v
  conv(o, s.dec, s.date, false)
  for (const [k, n] of Object.entries(s.nested ?? {})) {
    const v = o[k]
    if (v === undefined || v === null) continue
    if (n.list) o[k] = (v as Obj[]).map((x) => { const c = { ...x }; conv(c, n.dec, n.date, false); return c })
    else { const c = { ...(v as Obj) }; conv(c, n.dec, n.date, false); o[k] = c }
  }
  for (const k of Object.keys(o)) if (o[k] === null) delete o[k]
  // Invoice/Goal/Investment/... : defaults numéricos viram Decimal
  for (const k of s.dec ?? []) if (typeof o[k] === 'number') o[k] = dec(o[k] as number)
  return o as unknown as EntityMap[T]
}

/** Entidade de domínio -> JSON de rede (Codable do Swift). */
export function encodeEntity<T extends EntityType>(type: T, e: EntityMap[T]): Record<string, unknown> {
  const s = SCHEMA[type]
  const o: Obj = { ...(e as unknown as Obj) }
  conv(o, s.dec, s.date, true)
  for (const [k, n] of Object.entries(s.nested ?? {})) {
    const v = o[k]
    if (v === undefined || v === null) continue
    if (n.list) o[k] = (v as Obj[]).map((x) => { const c = { ...x }; conv(c, n.dec, n.date, true); return c })
    else { const c = { ...(v as Obj) }; conv(c, n.dec, n.date, true); o[k] = c }
  }
  for (const k of Object.keys(o)) if (o[k] === undefined) delete o[k]
  return o
}

export function decodeSnapshot(wire: Record<string, unknown>): Snapshot {
  const snap = emptySnapshot()
  snap.version = typeof wire.version === 'number' ? wire.version : 1
  for (const t of ENTITY_TYPES) {
    const list = wire[COLLECTION[t]]
    if (Array.isArray(list)) (snap[COLLECTION[t]] as unknown[]) = list.map((x) => decodeEntity(t, x))
  }
  return snap
}

export function encodeSnapshot(s: Snapshot): Record<string, unknown> {
  const out: Record<string, unknown> = { version: s.version }
  for (const t of ENTITY_TYPES) {
    out[COLLECTION[t]] = (s[COLLECTION[t]] as unknown[]).map((x) => encodeEntity(t, x as never))
  }
  return out
}
