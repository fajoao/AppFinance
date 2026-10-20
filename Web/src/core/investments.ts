import { Dec, ZERO, dec, rounded, sum } from './decimal'
import { YearMonth, ymAdd, ymCmp, ymEq } from './calendar'
import { FinanceError } from './errors'
import { usedLimit as creditCardUsed } from './creditCard'
import { balanceOf } from './ledger'
import * as Money from './money'
import { Account, ASSET_CLASSES, AssetClass, CreditCard, Debt, Investment, NetWorthSnapshot, Transaction, newId } from './models'

export const investmentCost = (i: Investment): Dec => i.quantity.times(i.averagePrice)
export const marketValue = (i: Investment): Dec => i.quantity.times(i.quote ?? i.averagePrice)
export const investmentGain = (i: Investment): Dec => marketValue(i).minus(investmentCost(i))
const pct = (part: Dec, base: Dec): Dec | null => (base.isZero() ? null : rounded(part.times(100).div(base)))
export const investmentReturn = (i: Investment): Dec | null => pct(investmentGain(i), investmentCost(i))

export function buy(i: Investment, quantity: Dec, price: Dec): Investment {
  if (!quantity.gt(0)) throw new FinanceError('invalidQuantity')
  if (price.lt(0)) throw new FinanceError('invalidAmount')
  const total = i.quantity.plus(quantity)
  return { ...i, averagePrice: rounded(investmentCost(i).plus(quantity.times(price)).div(total), 4), quantity: total, updatedAt: new Date() }
}

export function sell(i: Investment, quantity: Dec, price: Dec): Investment {
  if (!quantity.gt(0)) throw new FinanceError('invalidQuantity')
  if (quantity.gt(i.quantity)) throw new FinanceError('insufficientQuantity')
  if (price.lt(0)) throw new FinanceError('invalidAmount')
  return {
    ...i, quantity: i.quantity.minus(quantity),
    realizedProfit: i.realizedProfit.plus(quantity.times(price.minus(i.averagePrice))), updatedAt: new Date(),
  }
}

export function updateQuote(i: Investment, quote: Dec, date: Date): Investment {
  if (quote.lt(0)) throw new FinanceError('invalidAmount')
  return { ...i, quote, quoteDate: date, updatedAt: new Date() }
}

export interface PortfolioTotals { cost: Dec; value: Dec; gain: Dec; returnPercent: Dec | null }
export function portfolioTotals(list: Investment[]): PortfolioTotals {
  const cost = sum(list.map(investmentCost)), value = sum(list.map(marketValue))
  return { cost, value, gain: value.minus(cost), returnPercent: pct(value.minus(cost), cost) }
}

export interface AllocationSlice { assetClass: AssetClass; value: Dec; percent: Dec }
export function allocation(list: Investment[]): AllocationSlice[] {
  const by = new Map<AssetClass, Dec>()
  for (const i of list) by.set(i.assetClass, (by.get(i.assetClass) ?? ZERO).plus(marketValue(i)))
  const sorted = [...by.entries()].filter(([, v]) => v.gt(0)).sort(([ka, va], [kb, vb]) =>
    !va.eq(vb) ? vb.comparedTo(va) : ASSET_CLASSES.indexOf(ka) - ASSET_CLASSES.indexOf(kb))
  const total = sum(sorted.map(([, v]) => v))
  if (!total.gt(0)) return []
  const percents = Money.allocate(dec(100), sorted.map(([, v]) => v))
  return sorted.map(([assetClass, value], i) => ({ assetClass, value, percent: percents[i]! }))
}

// MARK: Patrimônio líquido

export interface NetWorth {
  accountsAssets: Dec; investmentsValue: Dec; overdraft: Dec; debts: Dec; cardBalances: Dec
  assets: Dec; liabilities: Dec; netWorth: Dec
}

export function computeNetWorth(
  accounts: Account[], txs: Transaction[], investments: Investment[], debts: Debt[], cards: CreditCard[], asOf?: Date,
): NetWorth {
  let positive = ZERO, overdraft = ZERO
  for (const a of accounts) {
    if (a.isArchived) continue
    const b = balanceOf(a, txs, asOf)
    if (b.gte(0)) positive = positive.plus(b)
    else overdraft = overdraft.plus(b.neg())
  }
  const cardBalances = sum(cards.filter((c) => !c.isArchived).map((c) => {
    const u = creditCardUsed(c, txs)
    return u.gt(0) ? u : ZERO
  }))
  const investmentsValue = portfolioTotals(investments).value
  const debtTotal = sum(debts.map((d) => (d.balance.gt(0) ? d.balance : ZERO)))
  const assets = positive.plus(investmentsValue)
  const liabilities = overdraft.plus(debtTotal).plus(cardBalances)
  return { accountsAssets: positive, investmentsValue, overdraft, debts: debtTotal, cardBalances, assets, liabilities, netWorth: assets.minus(liabilities) }
}

export function netWorthSnapshot(nw: NetWorth, month: YearMonth): NetWorthSnapshot {
  const now = new Date()
  return { id: newId(), month, assets: nw.assets, liabilities: nw.liabilities, createdAt: now, updatedAt: now }
}

export function upsertSnapshot(snap: NetWorthSnapshot, list: NetWorthSnapshot[]): { list: NetWorthSnapshot[]; saved: NetWorthSnapshot } {
  const result = list.map((s) => ({ ...s }))
  const i = result.findIndex((s) => ymEq(s.month, snap.month))
  let saved: NetWorthSnapshot
  if (i >= 0) {
    result[i]!.assets = snap.assets; result[i]!.liabilities = snap.liabilities; result[i]!.updatedAt = snap.updatedAt
    saved = result[i]!
  } else { result.push(snap); saved = snap }
  return { list: result.sort((a, b) => ymCmp(a.month, b.month)), saved }
}

export interface NetWorthPoint { month: YearMonth; netWorth: Dec | null }
export function netWorthEvolution(list: NetWorthSnapshot[], months: number, endingAt: YearMonth): NetWorthPoint[] {
  const out: NetWorthPoint[] = []
  for (let back = Math.max(months, 1) - 1; back >= 0; back--) {
    const m = ymAdd(endingAt, -back)
    const s = list.find((x) => ymEq(x.month, m))
    out.push({ month: m, netWorth: s ? s.assets.minus(s.liabilities) : null })
  }
  return out
}
export function netWorthChange(points: NetWorthPoint[]): Dec | null {
  const known = points.map((p) => p.netWorth).filter((x): x is Dec => x !== null)
  return known.length >= 2 ? known[known.length - 1]!.minus(known[0]!) : null
}
