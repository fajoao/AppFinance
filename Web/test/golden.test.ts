import { readFileSync, readdirSync } from 'node:fs'
import { join } from 'node:path'
import { describe, expect, it } from 'vitest'
import * as C from '../src/core'
import { Dec, dec } from '../src/core'

// Vetores dourados gerados pelo Core Swift real (Web/tools/golden-gen). Cada caso compara a saída do porte TS
// com a saída do Swift para a mesma entrada.

type Any = any // eslint-disable-line @typescript-eslint/no-explicit-any
interface Case { name: string; kind: string; input: Any; expected: Any }

const dir = join(__dirname, 'golden')
const suites = readdirSync(dir).filter((f) => f.endsWith('.json')).sort()

const S = (d: Dec | null | undefined): string | null => (d === null || d === undefined ? null : d.toString())
const day = (d: Date | null | undefined): string | null => (d ? C.isoDay(d) : null)
const D = (s: string): Date => {
  const d = C.parseIsoDay(s)
  if (!d) throw new Error('data inválida ' + s)
  return d
}
const DN = (s: string | null | undefined): Date | undefined => (s ? D(s) : undefined)
const ymj = (m: C.YearMonth) => ({ year: m.year, month: m.month })
const tx = (w: Any): C.Transaction => C.decodeEntity('Transaction', w)
const txs = (ws: Any[]): C.Transaction[] => ws.map(tx)
const accs = (ws: Any[]): C.Account[] => ws.map((w) => C.decodeEntity('Account', w))
const cats = (ws: Any[]): C.Category[] => ws.map((w) => C.decodeEntity('Category', w))
const card = (w: Any): C.CreditCard => C.decodeEntity('CreditCard', w)
const invs = (ws: Any[]): C.Invoice[] => ws.map((w) => C.decodeEntity('Invoice', w))
const goal = (w: Any): C.Goal => C.decodeEntity('Goal', w)
const member = (w: Any): C.FamilyMember => C.decodeEntity('FamilyMember', w)
const dmap = (m: Map<string, Dec>): Record<string, string> => Object.fromEntries([...m].map(([k, v]) => [k, v.toString()]))
const obj = <T, R>(o: Record<string, T>, f: (v: T) => R): Record<string, R> => Object.fromEntries(Object.entries(o).map(([k, v]) => [k, f(v)]))
const catTotals = (l: C.CategoryTotal[]) => l.map((c) => ({ categoryId: c.categoryId, amount: S(c.amount), percent: S(c.percentOfTotal) }))
const summaryJ = (s: C.InvoiceSummary) => ({
  month: ymj(s.invoice.month), closing: day(s.invoice.closingDate), due: day(s.invoice.dueDate), total: S(s.total), paid: S(s.paidAmount),
  remaining: S(s.remaining), status: s.status, isStored: s.isStored, txCount: s.transactions.length,
})
const errMsg = (f: () => unknown): { ok: false; error: string; required?: string | null } | { ok: true; value: unknown } => {
  try { return { ok: true, value: f() } } catch (e) {
    if (e instanceof C.FinanceError) return { ok: false, error: e.message, required: e.required ? e.required.toString() : undefined }
    throw e
  }
}

const runners: Record<string, (i: Any) => unknown> = {
  'money.format': (i) => C.Money.format(dec(i.value)),
  'money.plain': (i) => C.Money.plain(dec(i.value)),
  'money.parse': (i) => S(C.Money.parse(i.raw, i.style)),
  'money.split': (i) => C.Money.split(dec(i.total), i.count).map(S),
  'money.allocate': (i) => C.Money.allocate(dec(i.total), i.weights.map((w: string) => dec(w))).map(S),
  'money.round': (i) => S(C.rounded(dec(i.value), i.scale, i.mode)),
  'date.parse': (i) => day(C.parseDate(i.raw)),
  'calendar.addMonths': (i) => day(C.addMonths(D(i.date), i.n)),
  'calendar.addYears': (i) => day(C.addYears(D(i.date), i.n)),
  'calendar.daysBetween': (i) => C.daysBetween(D(i.a), D(i.b)),

  'balance.compute': (i) => {
    const a = accs(i.accounts), t = txs(i.transactions), asOf = DN(i.asOf)
    return {
      balances: a.map((x) => S(C.balanceOf(x, t, asOf, i.includePending))),
      total: S(C.totalBalance(a, t, { asOf, includePending: i.includePending })),
      savingsOnly: S(C.totalBalance(a, t, { asOf, includePending: i.includePending, types: new Set(['savings']) })),
    }
  },
  'balance.reconcile': (i) => {
    const a = C.decodeEntity('Account', i.account), t = txs(i.transactions), date = D(i.date)
    const adj = C.reconciliationAdjustment(a, dec(i.statement), t, date)
    return { diff: S(C.reconciliationDifference(a, dec(i.statement), t, date)), type: adj ? adj.type : 'none', amount: adj ? S(adj.amount) : '0' }
  },
  'installments.make': (i) => C.makeInstallments(tx(i.template), i.count).map((t) => ({
    amount: S(t.amount), date: day(t.date), title: t.title, status: t.status, number: t.installment!.number, total: t.installment!.total,
  })),
  'installments.delete': (i) => {
    const all = txs(i.transactions)
    const target = all[i.targetIndex]!
    return C.idsToDelete(target, i.scope, all).map((id) => all.findIndex((t) => t.id === id))
  },
  'recurrence.occurrences': (i) => {
    return C.occurrences(D(i.start), decodeRule(i.rule), D(i.from), D(i.to)).map((d) => C.isoDay(d))
  },
  'recurrence.generate': (i) => C.generateRecurrences(tx(i.template), D(i.from), D(i.to), txs(i.existing)).map((t) => ({
    date: day(t.date), status: t.status, title: t.title, amount: S(t.amount), parentIsTemplate: t.recurrenceParentId === i.template.id,
  })),

  'card.invoiceMonth': (i) => ymj(C.invoiceMonthFor(D(i.date), card(i.card))),
  'card.dates': (i) => ({ closing: day(C.closingDate(card(i.card), i.month)), due: day(C.dueDate(card(i.card), i.month)) }),
  'card.upcoming': (i) => {
    const c = card(i.card), t = txs(i.transactions)
    return {
      invoices: C.upcomingInvoices(c, t, invs(i.invoices), D(i.asOf), i.futureCount).map(summaryJ),
      used: S(C.usedLimit(c, t)), available: S(C.availableLimit(c, t)),
    }
  },
  'card.pay': (i) => {
    const c = card(i.card), t = txs(i.transactions), on = D(i.on)
    const s = C.summary(c, i.month, t, invs(i.invoices), D(i.asOf))
    const r = errMsg(() => C.payInvoice(s, c, i.amount === null ? undefined : dec(i.amount), i.from, on))
    if (!r.ok) return { ok: false, error: r.error }
    const v = r.value as ReturnType<typeof C.payInvoice>
    return { ok: true, paidAmount: S(v.invoice.paidAmount), paidAt: day(v.invoice.paidAt), paymentAmount: S(v.payment.amount), paymentTitle: v.payment.title, paymentType: v.payment.type }
  },
  'card.makePurchase': (i) => C.makePurchase(card(i.card), i.title, dec(i.total), D(i.date), i.installments).map((t) => ({
    amount: S(t.amount), date: day(t.date), title: t.title, status: t.status,
  })),

  'budget.statuses': (i) => {
    const t = txs(i.transactions), c = cats(i.categories)
    return i.budgets.map((w: Any) => {
      const s = C.budgetStatus(C.decodeEntity('Budget', w), t, c, i.onlyPaid)
      return { id: s.budget.id, spent: S(s.spent), remaining: S(s.remaining), percentUsed: S(s.percentUsed), alert: s.alert }
    })
  },
  'budget.alerts': (i) => C.budgetAlerts(i.month, i.budgets.map((w: Any) => C.decodeEntity('Budget', w)), txs(i.transactions), cats(i.categories)).map((s) => s.budget.id),
  'budget.alert': (i) => C.budgetAlert(dec(i.spent), dec(i.limit)),
  'budget.copy': (i) => C.copyBudgets(i.budgets.map((w: Any) => C.decodeEntity('Budget', w)), i.from, i.to).map((b) => ({ categoryId: b.categoryId, limit: S(b.limit), month: ymj(b.month) })),

  'summary.month': (i) => {
    const s = C.monthlySummary(i.month, txs(i.transactions), i.onlyPaid)
    const c = s.comparison
    return {
      income: S(s.income), expense: S(s.expense), balance: S(s.balance), expensesByCategory: catTotals(s.expensesByCategory), incomeByCategory: catTotals(s.incomeByCategory),
      comparison: {
        previousIncome: S(c.previousIncome), previousExpense: S(c.previousExpense), incomeDelta: S(c.incomeDelta), expenseDelta: S(c.expenseDelta),
        incomeChangePercent: S(c.incomeChangePercent), expenseChangePercent: S(c.expenseChangePercent),
      },
    }
  },
  'cashflow.project': (i) => {
    const dues = i.invoiceDues.map((x: Any) => ({ date: D(x.date), amount: dec(x.amount), label: x.label }))
    const p = C.projectCashFlow(dec(i.startingBalance), D(i.from), i.days, txs(i.transactions), dues)
    return {
      ending: S(p.endingBalance), lowest: S(p.lowestBalance), lowestDate: day(p.lowestBalanceDate), totalIn: S(p.totalIn), totalOut: S(p.totalOut),
      goesNegative: p.goesNegative, pointCount: p.points.length,
      items: p.items.map((x) => ({ date: day(x.date), amount: S(x.amount), label: x.label })),
      points: p.points.map((x) => ({ date: day(x.date), change: S(x.change), balance: S(x.balance) })),
    }
  },
  'debts.compare': (i) => {
    const ds: C.Debt[] = i.debts.map((w: Any) => C.decodeEntity('Debt', w))
    const r = errMsg(() => C.comparePayoff(ds, dec(i.budget)))
    if (!r.ok) return { ok: false, required: r.required, message: r.error }
    const v = r.value as ReturnType<typeof C.comparePayoff>
    const pj = (p: C.PayoffResult) => ({
      months: p.months, totalInterest: S(p.totalInterest), totalPaid: S(p.totalPaid), order: p.payoffOrder, payoffMonth: p.payoffMonth, feasible: p.feasible,
      monthlyBalances: p.monthlyBalances.map(S),
    })
    return { ok: true, avalanche: pj(v.avalanche), snowball: pj(v.snowball), saved: S(v.interestSavedByAvalanche) }
  },
  'goal.progress': (i) => {
    const p = C.goalProgress(goal(i.goal), D(i.asOf))
    return { percent: S(p.percent), remaining: S(p.remaining), complete: p.isComplete, months: p.monthsRemaining, needed: S(p.monthlyContributionNeeded) }
  },
  'goal.projection': (i) => {
    const p = C.goalProjection(goal(i.goal), i.contributions.map((w: Any) => C.decodeEntity('GoalContribution', w)), D(i.asOf), i.lookback)
    return { average: S(p.averageMonthlyContribution), months: p.monthsToComplete, completion: day(p.projectedCompletion), onTrack: p.onTrack, extra: S(p.extraPerMonthNeeded) }
  },
  'goal.history': (i) => C.contributionHistory(i.goalId, i.contributions.map((w: Any) => C.decodeEntity('GoalContribution', w))).map((c) => c.id),

  'invest.totals': (i) => {
    const l: C.Investment[] = i.investments.map((w: Any) => C.decodeEntity('Investment', w))
    const t = C.portfolioTotals(l)
    return {
      cost: S(t.cost), value: S(t.value), gain: S(t.gain), return: S(t.returnPercent),
      positions: l.map((x) => ({ cost: S(C.investmentCost(x)), value: S(C.marketValue(x)), gain: S(C.investmentGain(x)), return: S(C.investmentReturn(x)) })),
      allocation: C.allocation(l).map((a) => ({ class: a.assetClass, value: S(a.value), percent: S(a.percent) })),
    }
  },
  'invest.buy': (i) => { const r = C.buy(C.decodeEntity('Investment', i.investment), dec(i.quantity), dec(i.price)); return { quantity: S(r.quantity), averagePrice: S(r.averagePrice) } },
  'invest.sell': (i) => {
    const r = errMsg(() => C.sell(C.decodeEntity('Investment', i.investment), dec(i.quantity), dec(i.price)))
    if (!r.ok) return { ok: false, error: r.error }
    const v = r.value as C.Investment
    return { ok: true, quantity: S(v.quantity), realized: S(v.realizedProfit), averagePrice: S(v.averagePrice) }
  },
  'networth.compute': (i) => {
    const nw = C.computeNetWorth(accs(i.accounts), txs(i.transactions), i.investments.map((w: Any) => C.decodeEntity('Investment', w)),
      i.debts.map((w: Any) => C.decodeEntity('Debt', w)), i.cards.map(card))
    return { accountsAssets: S(nw.accountsAssets), investmentsValue: S(nw.investmentsValue), overdraft: S(nw.overdraft), debts: S(nw.debts), cardBalances: S(nw.cardBalances), assets: S(nw.assets), liabilities: S(nw.liabilities), netWorth: S(nw.netWorth) }
  },
  'networth.evolution': (i) => {
    const pts = C.netWorthEvolution(i.snapshots.map((w: Any) => C.decodeEntity('NetWorthSnapshot', w)), i.months, i.endingAt)
    return { points: pts.map((p) => ({ month: ymj(p.month), netWorth: S(p.netWorth) })), change: S(C.netWorthChange(pts)) }
  },

  'split.make': (i) => {
    const pcts = obj(i.percentages as Record<string, string>, (v) => dec(v))
    const r = errMsg(() => C.makeSplit({ title: i.title, total: dec(i.total), date: D('2026-10-10'), paidBy: i.paidBy, participants: i.participants, mode: i.mode, percentages: pcts }))
    if (!r.ok) return { ok: false, error: r.error }
    const s = (r.value as C.ExpenseSplit)
    return { ok: true, split: { total: S(s.total), mode: s.mode, shares: s.shares.map((x) => ({ member: x.memberId, percent: S(x.percent), amount: S(x.amount) })) } }
  },
  'settlement.plan': (i) => {
    const sp: C.ExpenseSplit[] = i.splits.map((w: Any) => C.decodeEntity('ExpenseSplit', w))
    const se: C.SplitSettlement[] = i.settlements.map((w: Any) => C.decodeEntity('SplitSettlement', w))
    return { balances: dmap(C.settlementBalances(sp, se)), plan: C.settlementPlan(sp, se).map((t) => ({ from: t.from, to: t.to, amount: S(t.amount) })) }
  },
  'family.can': (i) => Object.fromEntries((['manageMembers', 'manageAllowances', 'approveSpending', 'splitExpenses', 'viewFamilyView', 'addTransactions', 'manageSharedData'] as const).map((p) => [p, C.can(i.role, p)])),
  'family.visibility': (i) => {
    const a = accs(i.accounts), c = cats(i.categories), t = txs(i.transactions)
    const viewer = i.viewer ?? undefined
    return {
      transactions: C.visibleTransactions(t, a, c, viewer, i.scope).map((x) => x.id),
      accounts: C.visibleAccounts(a, viewer, i.scope).map((x) => x.id),
      categories: C.visibleCategories(c, viewer).map((x) => x.id),
    }
  },
  'family.evaluate': (i) => {
    const r = C.evaluateSpending(member(i.member), dec(i.amount), D(i.date), txs(i.transactions))
    return r.kind === 'allowed' ? { kind: 'allowed' } : { kind: 'needsApproval', limit: S(r.limit), spent: S(r.spent) }
  },
  'family.allowance': (i) => {
    const a: C.Allowance = C.decodeEntity('Allowance', i.allowance)
    const asOf = D(i.asOf)
    const r = C.payAllowance(a, asOf)
    return {
      due: C.allowanceDueMonths(a, asOf).map(ymj), last: r.allowance.lastPaidMonth ? ymj(r.allowance.lastPaidMonth) : null,
      transactions: r.transactions.map((t) => ({ date: day(t.date), amount: S(t.amount), title: t.title })),
    }
  },

  'import.csv': (i) => resJ(C.parseCSV(i.text)),
  'import.ofx': (i) => resJ(C.parseOFX(i.text)),
  'import.duplicates': (i) => {
    const cs: C.CandidateTransaction[] = i.candidates.map((c: Any) => ({ date: D(c.date), title: c.title, amount: dec(c.amount), externalId: c.externalId ?? undefined, isDuplicate: false }))
    return C.markDuplicates(cs, txs(i.existing), i.accountId ?? undefined).map((c) => c.isDuplicate)
  },
  'export.csv': (i) => C.exportCSV(txs(i.transactions), accs(i.accounts), cats(i.categories), i.tags.map((w: Any) => C.decodeEntity('Tag', w)), { delimiter: i.delimiter, decimalComma: i.decimalComma }),
  'import.suggest': (i) => {
    const s = new C.CategorySuggester(txs(i.history), i.keywords)
    return i.queries.map((q: Any) => s.suggest(q.title, q.type) ?? null)
  },
  'report.run': (i) => {
    const f = i.filter
    const filter = C.reportFilter(D(f.from), D(f.to), {
      onlyPaid: !!f.onlyPaid, categoryIds: new Set(f.categoryIds ?? []), memberIds: new Set(f.memberIds ?? []), accountIds: new Set(f.accountIds ?? []),
    })
    const r = C.runReport(filter, txs(i.transactions), cats(i.categories))
    const doc = C.buildReportDocument(r, 'Relatório', i.names, D(i.generatedOn))
    const gj = (g: C.GroupTotal) => ({ id: g.id, income: S(g.income), expense: S(g.expense), count: g.count, percent: S(g.percentOfExpense) })
    return {
      income: S(r.income), expense: S(r.expense), net: S(r.net), count: r.count, byCategory: r.byCategory.map(gj), byMember: r.byMember.map(gj), byAccount: r.byAccount.map(gj),
      byMonth: r.byMonth.map((m) => ({ month: ymj(m.month), income: S(m.income), expense: S(m.expense) })), transactionIds: r.transactions.map((t) => t.id),
      csv: C.reportCSV(doc), subtitle: doc.subtitle, generatedOn: doc.generatedOn,
    }
  },
  'tax.summary': (i) => {
    const s = C.taxSummary(i.year, txs(i.transactions), cats(i.categories), C.DEFAULT_TAX_RULES, i.memberId ?? undefined, i.onlyPaid)
    const doc = C.taxDocument(s, { categories: i.categoryNames, members: {}, accounts: {} }, i.memberName ?? undefined, D('2026-10-20'))
    return {
      totalIncome: S(s.totalIncome), incomeLines: s.incomeLines.map((l) => ({ categoryId: l.categoryId, total: S(l.total) })),
      deductionLines: s.deductionLines.map((l) => ({ kind: l.kind, categoryId: l.categoryId, total: S(l.total), count: l.count })),
      health: S(s.healthTotal), education: S(s.educationTotal), educationDeductible: S(s.educationDeductible), educationExcess: S(s.educationExcess),
      totalDeductible: S(s.totalDeductible), csv: C.reportCSV(doc), subtitle: doc.subtitle,
    }
  },
  'sync.merge': (i) => {
    const m = C.mergeSnapshots(C.decodeSnapshot(i.local), C.decodeSnapshot(i.remote))
    const s = m.snapshot
    return {
      snapshot: {
        accounts: s.accounts.map((a) => ({ id: a.id, name: a.name })), transactions: s.transactions.map((t) => ({ id: t.id, title: t.title })),
        tombstones: s.tombstones.map((t) => ({ entityType: t.entityType, entityId: t.entityId })),
      },
      applied: m.report.applied, keptLocal: m.report.keptLocal, deleted: m.report.deleted,
    }
  },
  'sync.changes': (i) => {
    const snap = C.decodeSnapshot(i.snapshot)
    const since = C.dateFromWire(i.since)
    return {
      accounts: snap.accounts.filter((a) => a.updatedAt > since).map((a) => a.id),
      transactions: snap.transactions.filter((t) => t.updatedAt > since).map((t) => t.id),
      tombstones: snap.tombstones.filter((t) => t.deletedAt > since).map((t) => t.entityId),
    }
  },
}

function decodeRule(w: Any): C.RecurrenceRule {
  const tpl = C.decodeEntity('Transaction', { id: 'X', type: 'expense', amount: 1, date: 0, title: 't', createdAt: 0, updatedAt: 0, recurrence: w })
  return tpl.recurrence!
}
function resJ(r: C.ImportResult) {
  return {
    candidates: r.candidates.map((c) => ({ date: day(c.date), title: c.title, amount: S(c.amount), externalId: c.externalId ?? null, isDuplicate: c.isDuplicate })),
    issues: r.issues.map((x) => ({ line: x.line, message: x.message })),
  }
}

let total = 0
const kindsSeen = new Set<string>()
for (const file of suites) {
  const suite = JSON.parse(readFileSync(join(dir, file), 'utf8')) as { suite: string; cases: Case[] }
  describe(`golden ${suite.suite}`, () => {
    for (const c of suite.cases) {
      total++
      kindsSeen.add(c.kind)
      it(`${c.kind}: ${c.name}`, () => {
        const run = runners[c.kind]
        if (!run) throw new Error(`sem runner para ${c.kind}`)
        const actual = JSON.parse(JSON.stringify(run(c.input), (_k, v) => (v === undefined ? null : v)))
        expect(actual).toEqual(c.expected)
      })
    }
  })
}

describe('golden cobertura', () => {
  it('há vetores e todos os tipos têm runner', () => {
    expect(total).toBeGreaterThan(300)
    for (const k of kindsSeen) expect(runners[k], k).toBeDefined()
  })
})
