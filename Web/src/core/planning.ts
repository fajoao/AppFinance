import { Dec, ZERO, dec, dmax, dmin, rounded, sum } from './decimal'
import {
  YearMonth, addDays, addMonths, isBeforeDay, isSameDay, startOfDay, ymContains, ymLabel, ymMonthsTo, ymOf, ymEq, ymCmp, ymPrev, ymAdd,
} from './calendar'
import { FinanceError, invalidState } from './errors'
import { generateRecurrences } from './ledger'
import { InvoiceSummary } from './creditCard'
import {
  Budget, Category, Debt, Goal, GoalContribution, Transaction, TransactionType, UUID, isCardPurchase, isInvoicePayment, newId,
} from './models'

// MARK: Orçamento

export type BudgetAlert = 'none' | 'warning' | 'exceeded'
export interface BudgetStatus {
  budget: Budget
  spent: Dec
  limit: Dec
  remaining: Dec
  percentUsed: Dec
  alert: BudgetAlert
}
export const WARNING_THRESHOLD = 80
export const EXCEEDED_THRESHOLD = 100

export function categoryFamily(categoryId: UUID, categories: Category[]): Set<UUID> {
  const ids = new Set<UUID>([categoryId])
  let changed = true
  while (changed) {
    changed = false
    for (const c of categories) {
      if (c.parentId !== undefined && ids.has(c.parentId) && !ids.has(c.id)) {
        ids.add(c.id)
        changed = true
      }
    }
  }
  return ids
}

export function spentInCategory(categoryId: UUID, month: YearMonth, txs: Transaction[], categories: Category[] = [], onlyPaid = false): Dec {
  const family = categoryFamily(categoryId, categories)
  let acc = ZERO
  for (const t of txs) {
    if (t.type !== 'expense' || isInvoicePayment(t) || t.categoryId === undefined || !family.has(t.categoryId)) continue
    if (!ymContains(month, t.date) || (onlyPaid && t.status !== 'paid')) continue
    acc = acc.plus(t.amount)
  }
  return acc
}

export function budgetAlert(spent: Dec, limit: Dec): BudgetAlert {
  if (limit.lte(0)) return spent.gt(0) ? 'exceeded' : 'none'
  if (spent.times(100).gte(limit.times(EXCEEDED_THRESHOLD))) return 'exceeded'
  if (spent.times(100).gte(limit.times(WARNING_THRESHOLD))) return 'warning'
  return 'none'
}

export function budgetStatus(budget: Budget, txs: Transaction[], categories: Category[] = [], onlyPaid = false): BudgetStatus {
  const s = spentInCategory(budget.categoryId, budget.month, txs, categories, onlyPaid)
  const pct = budget.limit.gt(0) ? rounded(s.times(100).div(budget.limit)) : s.gt(0) ? dec(100) : ZERO
  return { budget, spent: s, limit: budget.limit, remaining: budget.limit.minus(s), percentUsed: pct, alert: budgetAlert(s, budget.limit) }
}

export const budgetStatuses = (month: YearMonth, budgets: Budget[], txs: Transaction[], categories: Category[] = []): BudgetStatus[] =>
  budgets.filter((b) => ymEq(b.month, month)).map((b) => budgetStatus(b, txs, categories))

export const budgetAlerts = (month: YearMonth, budgets: Budget[], txs: Transaction[], categories: Category[] = []): BudgetStatus[] =>
  budgetStatuses(month, budgets, txs, categories)
    .filter((s) => s.alert !== 'none')
    .sort((a, b) => b.percentUsed.comparedTo(a.percentUsed))

export function copyBudgets(budgets: Budget[], from: YearMonth, to: YearMonth): Budget[] {
  const now = new Date()
  return budgets.filter((b) => ymEq(b.month, from)).map((b) => ({
    id: newId(), categoryId: b.categoryId, month: to, limit: b.limit, ownerId: b.ownerId, createdAt: now, updatedAt: now,
  }))
}

// MARK: Resumo mensal

export interface CategoryTotal { categoryId: UUID | null; amount: Dec; percentOfTotal: Dec }
export interface MonthComparison {
  previousIncome: Dec; previousExpense: Dec; incomeDelta: Dec; expenseDelta: Dec
  incomeChangePercent: Dec | null; expenseChangePercent: Dec | null
}
export interface MonthlySummary {
  month: YearMonth; income: Dec; expense: Dec; balance: Dec
  expensesByCategory: CategoryTotal[]; incomeByCategory: CategoryTotal[]; comparison: MonthComparison
}

const counts = (t: Transaction, onlyPaid: boolean): boolean => t.type !== 'transfer' && !isInvoicePayment(t) && (!onlyPaid || t.status === 'paid')

export function monthTotals(month: YearMonth, txs: Transaction[], onlyPaid = false): { income: Dec; expense: Dec } {
  let income = ZERO, expense = ZERO
  for (const t of txs) {
    if (!ymContains(month, t.date) || !counts(t, onlyPaid)) continue
    if (t.type === 'income') income = income.plus(t.amount)
    else expense = expense.plus(t.amount)
  }
  return { income, expense }
}

function grouped(type: TransactionType, month: YearMonth, txs: Transaction[], total: Dec, onlyPaid: boolean): CategoryTotal[] {
  const map = new Map<UUID | null, Dec>()
  for (const t of txs) {
    if (t.type !== type || !ymContains(month, t.date) || !counts(t, onlyPaid)) continue
    const k = t.categoryId ?? null
    map.set(k, (map.get(k) ?? ZERO).plus(t.amount))
  }
  return [...map.entries()]
    .map(([categoryId, amount]) => ({ categoryId, amount, percentOfTotal: total.isZero() ? ZERO : rounded(amount.times(100).div(total)) }))
    .sort((a, b) => (!a.amount.eq(b.amount) ? b.amount.comparedTo(a.amount) : (a.categoryId ?? '') < (b.categoryId ?? '') ? -1 : (a.categoryId ?? '') > (b.categoryId ?? '') ? 1 : 0))
}

const change = (now: Dec, before: Dec): Dec | null => (before.isZero() ? null : rounded(now.minus(before).times(100).div(before.abs())))

export function monthlySummary(month: YearMonth, txs: Transaction[], onlyPaid = false): MonthlySummary {
  const cur = monthTotals(month, txs, onlyPaid)
  const prev = monthTotals(ymPrev(month), txs, onlyPaid)
  return {
    month, income: cur.income, expense: cur.expense, balance: cur.income.minus(cur.expense),
    expensesByCategory: grouped('expense', month, txs, cur.expense, onlyPaid),
    incomeByCategory: grouped('income', month, txs, cur.income, onlyPaid),
    comparison: {
      previousIncome: prev.income, previousExpense: prev.expense,
      incomeDelta: cur.income.minus(prev.income), expenseDelta: cur.expense.minus(prev.expense),
      incomeChangePercent: change(cur.income, prev.income), expenseChangePercent: change(cur.expense, prev.expense),
    },
  }
}

// MARK: Fluxo de caixa projetado

export interface CashFlowItem { date: Date; amount: Dec; label: string }
export interface CashFlowPoint { date: Date; change: Dec; balance: Dec }
export interface CashFlowProjection {
  days: number; startingBalance: Dec; points: CashFlowPoint[]; items: CashFlowItem[]
  endingBalance: Dec; lowestBalance: Dec; lowestBalanceDate: Date | null; totalIn: Dec; totalOut: Dec; goesNegative: boolean
}

export function cashEffect(t: Transaction): Dec {
  switch (t.type) {
    case 'income': return t.amount
    case 'expense': return isCardPurchase(t) ? ZERO : t.amount.neg()
    case 'transfer': return t.destinationAccountId === undefined ? t.amount.neg() : ZERO
  }
}

export function cashFlowItems(from: Date, days: number, txs: Transaction[], invoiceDues: CashFlowItem[] = []): CashFlowItem[] {
  const end = addDays(from, days), start = addDays(from, 1)
  const sd = startOfDay(start).getTime(), ed = startOfDay(end).getTime()
  const result: CashFlowItem[] = []
  for (const t of txs) {
    if (t.status !== 'pending') continue
    const d = startOfDay(t.date).getTime()
    if (d >= sd && d <= ed && !cashEffect(t).isZero()) result.push({ date: t.date, amount: cashEffect(t), label: t.title })
  }
  for (const tpl of txs) {
    if (!tpl.recurrence) continue
    for (const occ of generateRecurrences(tpl, start, end, txs)) {
      const eff = cashEffect(occ)
      if (!eff.isZero()) result.push({ date: occ.date, amount: eff, label: occ.title })
    }
  }
  for (const due of invoiceDues) {
    const d = startOfDay(due.date).getTime()
    if (d >= sd && d <= ed) result.push(due)
  }
  return result.sort((a, b) => a.date.getTime() - b.date.getTime())
}

export function projectCashFlow(startingBalance: Dec, from: Date, days: number, txs: Transaction[], invoiceDues: CashFlowItem[] = []): CashFlowProjection {
  const list = cashFlowItems(from, days, txs, invoiceDues)
  const points: CashFlowPoint[] = []
  let balance = startingBalance, lowest = startingBalance
  let lowestDate: Date | null = null
  for (let offset = 1; offset <= days; offset++) {
    const day = addDays(from, offset)
    const delta = sum(list.filter((i) => isSameDay(i.date, day)).map((i) => i.amount))
    balance = balance.plus(delta)
    points.push({ date: day, change: delta, balance })
    if (balance.lt(lowest)) { lowest = balance; lowestDate = day }
  }
  let totalIn = ZERO, totalOut = ZERO
  for (const i of list) { if (i.amount.gt(0)) totalIn = totalIn.plus(i.amount); else totalOut = totalOut.plus(i.amount.neg()) }
  return {
    days, startingBalance, points, items: list, endingBalance: balance, lowestBalance: lowest, lowestBalanceDate: lowestDate,
    totalIn, totalOut, goesNegative: lowest.lt(0),
  }
}

export function invoiceDueItems(summaries: InvoiceSummary[], cardNames: Record<UUID, string> = {}): CashFlowItem[] {
  return summaries.filter((s) => s.remaining.gt(0)).map((s) => ({
    date: s.invoice.dueDate, amount: s.remaining.neg(), label: `Fatura ${cardNames[s.invoice.cardId] ?? 'cartão'} ${ymLabel(s.invoice.month)}`,
  }))
}

// MARK: Dívidas

export type PayoffStrategy = 'avalanche' | 'snowball'
export interface PayoffResult {
  strategy: PayoffStrategy; months: number; totalInterest: Dec; totalPaid: Dec
  payoffOrder: UUID[]; payoffMonth: Record<UUID, number>; feasible: boolean; monthlyBalances: Dec[]
}
export const MAX_PAYOFF_MONTHS = 1200

export function simulatePayoff(debts: Debt[], monthlyBudget: Dec, strategy: PayoffStrategy): PayoffResult {
  const active = debts.filter((d) => d.balance.gt(0)).map((d) => ({ id: d.id, rate: d.monthlyInterestRate, min: d.minimumPayment, bal: rounded(d.balance) }))
  const required = sum(active.map((a) => a.min))
  if (monthlyBudget.lt(required) && active.length > 0) throw new FinanceError('budgetBelowMinimums', undefined, required)
  let month = 0
  let interestTotal = ZERO, paidTotal = ZERO
  const order: UUID[] = [], payoff: Record<UUID, number> = {}, series: Dec[] = []
  let list = active
  while (list.length > 0 && month < MAX_PAYOFF_MONTHS) {
    month += 1
    const totalBefore = sum(list.map((a) => a.bal))
    for (const a of list) {
      const interest = rounded(a.bal.times(a.rate))
      a.bal = a.bal.plus(interest)
      interestTotal = interestTotal.plus(interest)
    }
    let pool = monthlyBudget
    for (const a of list) {
      const pay = dmin(dmin(a.min, a.bal), pool)
      a.bal = a.bal.minus(pay); pool = pool.minus(pay); paidTotal = paidTotal.plus(pay)
    }
    const priority = list.filter((a) => a.bal.gt(0)).sort((x, y) =>
      strategy === 'avalanche'
        ? (!x.rate.eq(y.rate) ? y.rate.comparedTo(x.rate) : x.bal.comparedTo(y.bal))
        : (!x.bal.eq(y.bal) ? x.bal.comparedTo(y.bal) : y.rate.comparedTo(x.rate)),
    )
    for (const a of priority) {
      if (!pool.gt(0)) break
      const pay = dmin(a.bal, pool)
      a.bal = a.bal.minus(pay); pool = pool.minus(pay); paidTotal = paidTotal.plus(pay)
    }
    for (const a of list) if (a.bal.lte(0)) { order.push(a.id); payoff[a.id] = month }
    list = list.filter((a) => a.bal.gt(0))
    const remaining = sum(list.map((a) => a.bal))
    series.push(remaining)
    if (list.length > 0 && remaining.gte(totalBefore)) break
  }
  return { strategy, months: month, totalInterest: interestTotal, totalPaid: paidTotal, payoffOrder: order, payoffMonth: payoff, feasible: list.length === 0, monthlyBalances: series }
}

export function comparePayoff(debts: Debt[], monthlyBudget: Dec) {
  const avalanche = simulatePayoff(debts, monthlyBudget, 'avalanche')
  const snowball = simulatePayoff(debts, monthlyBudget, 'snowball')
  return { avalanche, snowball, interestSavedByAvalanche: snowball.totalInterest.minus(avalanche.totalInterest) }
}

// MARK: Metas

export interface GoalProgress {
  fraction: Dec; percent: Dec; remaining: Dec; isComplete: boolean
  monthsRemaining: number | null; monthlyContributionNeeded: Dec | null
}

export function goalProgress(goal: Goal, asOf: Date): GoalProgress {
  const target = goal.targetAmount
  const remaining = dmax(target.minus(goal.currentAmount), ZERO)
  const fraction = target.gt(0) ? dmin(dmax(goal.currentAmount.div(target), ZERO), dec(1)) : goal.currentAmount.gt(0) ? dec(1) : ZERO
  const complete = target.gt(0) ? goal.currentAmount.gte(target) : true
  let months: number | null = null
  let needed: Dec | null = null
  if (goal.deadline) {
    const m = ymMonthsTo(ymOf(asOf), ymOf(goal.deadline))
    const n = startOfDay(goal.deadline).getTime() <= startOfDay(asOf).getTime() ? 0 : Math.max(m, 1)
    months = n
    needed = complete ? ZERO : n <= 1 ? remaining : rounded(remaining.div(n), 2, 'up')
  }
  return { fraction, percent: rounded(fraction.times(100)), remaining, isComplete: complete, monthsRemaining: months, monthlyContributionNeeded: needed }
}

export function contributeToGoal(goal: Goal, amount: Dec): Goal {
  if (amount.isZero()) throw new FinanceError('invalidAmount')
  return { ...goal, currentAmount: dmax(goal.currentAmount.plus(amount), ZERO), updatedAt: new Date() }
}

export interface GoalProjection {
  averageMonthlyContribution: Dec; monthsToComplete: number | null; projectedCompletion: Date | null
  onTrack: boolean | null; extraPerMonthNeeded: Dec | null
}

export function editGoal(goal: Goal, name: string, target: Dec, deadline?: Date): Goal {
  const n = name.trim()
  if (!n) throw invalidState('Informe um nome.')
  if (!target.gt(0)) throw new FinanceError('invalidAmount')
  return { ...goal, name: n, targetAmount: target, deadline, updatedAt: new Date() }
}

export function recordContribution(goal: Goal, amount: Dec, date: Date, accountId?: UUID, note?: string): { goal: Goal; entry: GoalContribution } {
  const updated = contributeToGoal(goal, amount)
  const applied = updated.currentAmount.minus(goal.currentAmount)
  const now = new Date()
  return {
    goal: updated,
    entry: { id: newId(), goalId: goal.id, amount: applied, date, accountId, note, ownerId: goal.ownerId, createdAt: now, updatedAt: now },
  }
}

export function revertContribution(goal: Goal, entry: GoalContribution): Goal {
  return { ...goal, currentAmount: dmax(goal.currentAmount.minus(entry.amount), ZERO), updatedAt: new Date() }
}

export function contributionHistory(goalId: UUID, entries: GoalContribution[]): GoalContribution[] {
  return entries.filter((e) => e.goalId === goalId).sort((a, b) =>
    a.date.getTime() !== b.date.getTime() ? b.date.getTime() - a.date.getTime() : b.createdAt.getTime() - a.createdAt.getTime())
}

export function goalProjection(goal: Goal, contributions: GoalContribution[], asOf: Date, lookbackMonths = 3): GoalProjection {
  const mine = contributions.filter((c) => c.goalId === goal.id && !isBeforeDay(asOf, c.date))
  const window = Math.max(lookbackMonths, 1)
  const current = ymOf(asOf)
  const firstMonth = ymAdd(current, -(window - 1))
  const inWindow = mine.filter((c) => ymCmp(ymOf(c.date), firstMonth) >= 0)
  const net = sum(inWindow.map((c) => c.amount))
  let divisor = window
  if (mine.length > 0) {
    const earliest = mine.map((c) => ymOf(c.date)).reduce((a, b) => (ymCmp(a, b) <= 0 ? a : b))
    divisor = Math.min(window, Math.max(ymMonthsTo(earliest, current) + 1, 1))
  }
  const average = rounded(net.div(divisor))
  const remaining = dmax(goal.targetAmount.minus(goal.currentAmount), ZERO)
  let months: number | null = null
  let completion: Date | null = null
  if (remaining.isZero()) { months = 0; completion = asOf }
  else if (average.gt(0)) {
    months = Math.max(rounded(remaining.div(average), 0, 'up').toNumber(), 1)
    completion = addMonths(asOf, months)
  }
  let onTrack: boolean | null = null
  let extra: Dec | null = null
  if (goal.deadline) {
    if (remaining.isZero()) { onTrack = true; extra = ZERO }
    else {
      onTrack = completion ? !isBeforeDay(goal.deadline, completion) : false
      const needed = goalProgress(goal, asOf).monthlyContributionNeeded ?? remaining
      extra = onTrack ? ZERO : dmax(needed.minus(dmax(average, ZERO)), ZERO)
    }
  }
  return { averageMonthlyContribution: average, monthsToComplete: months, projectedCompletion: completion, onTrack, extraPerMonthNeeded: extra }
}
