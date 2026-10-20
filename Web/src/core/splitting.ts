import { Dec, ZERO, dec, rounded, sum } from './decimal'
import { FinanceError } from './errors'
import * as Money from './money'
import { ExpenseSplit, SplitMode, SplitSettlement, SplitShare, UUID, newId } from './models'

export function makeSplit(p: {
  title: string; total: Dec; date: Date; paidBy: UUID; participants: UUID[]; mode: SplitMode
  percentages?: Record<UUID, Dec>; transactionId?: UUID
}): ExpenseSplit {
  if (!p.total.gt(0)) throw new FinanceError('invalidAmount')
  const members = [...new Set(p.participants)]
  if (members.length === 0) throw new FinanceError('noParticipants')
  let shares: SplitShare[]
  if (p.mode === 'equal') {
    const parts = Money.split(p.total, members.length)
    shares = members.map((m, i) => ({ memberId: m, amount: parts[i]! }))
  } else {
    const weights = members.map((m) => p.percentages?.[m] ?? dec(-1))
    if (!weights.every((w) => w.gte(0)) || !sum(weights).eq(100)) throw new FinanceError('invalidPercentages')
    const parts = Money.allocate(p.total, weights)
    shares = members.map((m, i) => ({ memberId: m, percent: weights[i]!, amount: parts[i]! }))
  }
  const now = new Date()
  return {
    id: newId(), title: p.title, total: rounded(p.total), date: p.date, paidBy: p.paidBy, mode: p.mode, shares,
    transactionId: p.transactionId, createdAt: now, updatedAt: now,
  }
}

export interface SettlementTransfer { from: UUID; to: UUID; amount: Dec }

/** Saldo líquido por membro: positivo = tem a receber; negativo = deve. */
export function settlementBalances(splits: ExpenseSplit[], settlements: SplitSettlement[]): Map<UUID, Dec> {
  const r = new Map<UUID, Dec>()
  const add = (k: UUID, v: Dec) => r.set(k, (r.get(k) ?? ZERO).plus(v))
  for (const s of splits) {
    add(s.paidBy, s.total)
    for (const sh of s.shares) add(sh.memberId, sh.amount.neg())
  }
  for (const p of settlements) {
    add(p.fromMemberId, p.amount)
    add(p.toMemberId, p.amount.neg())
  }
  for (const [k, v] of [...r]) if (v.isZero()) r.delete(k)
  return r
}

const byAmountThenId = (a: [UUID, Dec], b: [UUID, Dec]): number =>
  !a[1].eq(b[1]) ? b[1].comparedTo(a[1]) : a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0

/** Casa sempre o maior devedor com o maior credor (no máximo pessoas-1 transferências). */
export function settlementTransfers(balances: Map<UUID, Dec>): SettlementTransfer[] {
  const creditors: [UUID, Dec][] = [...balances].filter(([, v]) => v.gt(0)).sort(byAmountThenId)
  const debtors: [UUID, Dec][] = [...balances].filter(([, v]) => v.lt(0)).sort((a, b) => -byAmountThenId(a, b)).map(([k, v]) => [k, v.neg()])
  const result: SettlementTransfer[] = []
  while (creditors.length > 0 && debtors.length > 0) {
    const c = creditors[0]!, d = debtors[0]!
    const amount = c[1].lt(d[1]) ? c[1] : d[1]
    result.push({ from: d[0], to: c[0], amount })
    c[1] = c[1].minus(amount); d[1] = d[1].minus(amount)
    if (c[1].isZero()) creditors.shift()
    if (d[1].isZero()) debtors.shift()
    creditors.sort(byAmountThenId)
    debtors.sort(byAmountThenId)
  }
  return result
}

export const settlementPlan = (splits: ExpenseSplit[], settlements: SplitSettlement[]): SettlementTransfer[] =>
  settlementTransfers(settlementBalances(splits, settlements))

export function settle(t: SettlementTransfer, on: Date): SplitSettlement {
  const now = new Date()
  return { id: newId(), fromMemberId: t.from, toMemberId: t.to, amount: t.amount, date: on, createdAt: now, updatedAt: now }
}
