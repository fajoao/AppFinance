import { Dec, ZERO, dec, rounded, sum } from './decimal'
import { YearMonth, components, startOfDay, ymCmp, ymKey, ymLabel, ymOf } from './calendar'
import { categoryFamily } from './planning'
import * as Money from './money'
import { formatDateBR } from './importing'
import { Category, TaxDeductionKind, Transaction, UUID, isInvoicePayment } from './models'

export interface ReportFilter {
  from: Date
  to: Date
  categoryIds: Set<UUID>
  memberIds: Set<UUID>
  accountIds: Set<UUID>
  onlyPaid: boolean
}
export const reportFilter = (from: Date, to: Date, o: Partial<ReportFilter> = {}): ReportFilter => ({
  from, to, categoryIds: new Set(), memberIds: new Set(), accountIds: new Set(), onlyPaid: false, ...o,
})

export interface GroupTotal { id: UUID | null; income: Dec; expense: Dec; count: number; percentOfExpense: Dec }
export interface MonthTotal { month: YearMonth; income: Dec; expense: Dec; net: Dec }
export interface ReportResult {
  filter: ReportFilter; income: Dec; expense: Dec; net: Dec; count: number
  byCategory: GroupTotal[]; byMember: GroupTotal[]; byAccount: GroupTotal[]; byMonth: MonthTotal[]; transactions: Transaction[]
}

export function runReport(filter: ReportFilter, txs: Transaction[], categories: Category[]): ReportResult {
  const family = new Set<UUID>()
  for (const id of filter.categoryIds) for (const x of categoryFamily(id, categories)) family.add(x)
  const from = startOfDay(filter.from).getTime(), to = startOfDay(filter.to).getTime()
  const selected = txs.filter((tx) => {
    if (tx.type === 'transfer' || isInvoicePayment(tx)) return false
    const day = startOfDay(tx.date).getTime()
    if (day < from || day > to) return false
    if (filter.onlyPaid && tx.status !== 'paid') return false
    if (family.size > 0 && !(tx.categoryId !== undefined && family.has(tx.categoryId))) return false
    if (filter.memberIds.size > 0 && !(tx.memberId !== undefined && filter.memberIds.has(tx.memberId))) return false
    if (filter.accountIds.size > 0 && !(tx.accountId !== undefined && filter.accountIds.has(tx.accountId))) return false
    return true
  }).sort((a, b) => (a.date.getTime() !== b.date.getTime() ? a.date.getTime() - b.date.getTime() : a.createdAt.getTime() - b.createdAt.getTime()))

  const income = sum(selected.filter((t) => t.type === 'income').map((t) => t.amount))
  const expense = sum(selected.filter((t) => t.type === 'expense').map((t) => t.amount))

  const group = (key: (t: Transaction) => UUID | undefined): GroupTotal[] => {
    const map = new Map<UUID | null, { inc: Dec; exp: Dec; n: number }>()
    for (const tx of selected) {
      const k = key(tx) ?? null
      const v = map.get(k) ?? { inc: ZERO, exp: ZERO, n: 0 }
      if (tx.type === 'income') v.inc = v.inc.plus(tx.amount)
      else v.exp = v.exp.plus(tx.amount)
      v.n++
      map.set(k, v)
    }
    return [...map].map(([id, v]) => ({
      id, income: v.inc, expense: v.exp, count: v.n, percentOfExpense: expense.isZero() ? ZERO : rounded(v.exp.times(100).div(expense)),
    })).sort((a, b) => {
      if (!a.expense.eq(b.expense)) return b.expense.comparedTo(a.expense)
      if (!a.income.eq(b.income)) return b.income.comparedTo(a.income)
      const x = a.id ?? '', y = b.id ?? ''
      return x < y ? -1 : x > y ? 1 : 0
    })
  }

  const months = new Map<string, { m: YearMonth; inc: Dec; exp: Dec }>()
  for (const tx of selected) {
    const m = ymOf(tx.date), k = ymKey(m)
    const v = months.get(k) ?? { m, inc: ZERO, exp: ZERO }
    if (tx.type === 'income') v.inc = v.inc.plus(tx.amount)
    else v.exp = v.exp.plus(tx.amount)
    months.set(k, v)
  }
  const byMonth = [...months.values()].map((v) => ({ month: v.m, income: v.inc, expense: v.exp, net: v.inc.minus(v.exp) }))
    .sort((a, b) => ymCmp(a.month, b.month))

  return {
    filter, income, expense, net: income.minus(expense), count: selected.length,
    byCategory: group((t) => t.categoryId), byMember: group((t) => t.memberId), byAccount: group((t) => t.accountId),
    byMonth, transactions: selected,
  }
}

// MARK: Documento exportável

export interface ReportNames { categories: Record<UUID, string>; members: Record<UUID, string>; accounts: Record<UUID, string> }
export interface ReportRow { label: string; value: string; amount?: Dec; detail?: string }
export interface ReportSection { title: string; rows: ReportRow[] }
export interface ReportDocument {
  title: string; subtitle: string; generatedOn: string; sections: ReportSection[]; footer: string
}

export function reportCSV(doc: ReportDocument): string {
  const esc = (s: string) => (s.includes(';') || s.includes('"') || s.includes('\n') ? '"' + s.replace(/"/g, '""') + '"' : s)
  const out = ['Seção;Item;Valor']
  for (const s of doc.sections) {
    for (const r of s.rows) {
      const value = r.amount ? Money.plain(r.amount) : r.value
      out.push([esc(s.title), esc(r.label), esc(value)].join(';'))
    }
  }
  return out.join('\n') + '\n'
}

export function buildReportDocument(r: ReportResult, title: string, names: ReportNames, generatedOn: Date): ReportDocument {
  const rows = (list: GroupTotal[], lookup: Record<UUID, string>, none: string): ReportRow[] =>
    list.map((g) => {
      const label = g.id ? lookup[g.id] ?? 'Sem nome' : none
      const net = g.expense.gt(0) || g.income.isZero() ? g.expense : g.income
      return { label, value: Money.format(net), amount: net, detail: g.expense.gt(0) ? `${g.percentOfExpense.toString()}%` : 'receita' }
    })
  const sections: ReportSection[] = [
    {
      title: 'Resumo',
      rows: [
        { label: 'Receitas', value: Money.format(r.income), amount: r.income },
        { label: 'Despesas', value: Money.format(r.expense), amount: r.expense },
        { label: 'Saldo', value: Money.format(r.net), amount: r.net },
        { label: 'Lançamentos', value: String(r.count) },
      ],
    },
    { title: 'Por categoria', rows: rows(r.byCategory, names.categories, 'Sem categoria') },
    { title: 'Por membro', rows: rows(r.byMember, names.members, 'Sem membro') },
    { title: 'Por conta', rows: rows(r.byAccount, names.accounts, 'Cartão ou sem conta') },
    {
      title: 'Por mês',
      rows: r.byMonth.map((m) => ({
        label: ymLabel(m.month), value: Money.format(m.net), amount: m.net,
        detail: `receitas ${Money.format(m.income)}, despesas ${Money.format(m.expense)}`,
      })),
    },
  ]
  return {
    title, subtitle: `Período: ${formatDateBR(r.filter.from)} a ${formatDateBR(r.filter.to)}`,
    generatedOn: `Gerado em ${formatDateBR(generatedOn)}`, sections, footer: 'Gerado localmente pelo app Finanças. Valores em reais (BRL).',
  }
}

// MARK: Imposto de Renda

export interface TaxRules { educationAnnualLimit: Dec | null }
export const DEFAULT_TAX_RULES: TaxRules = { educationAnnualLimit: dec('3561.50') }

export interface TaxIncomeLine { categoryId: UUID | null; total: Dec }
export interface TaxDeductionLine { kind: TaxDeductionKind; categoryId: UUID | null; total: Dec; count: number }
export interface TaxSummary {
  year: number; incomeLines: TaxIncomeLine[]; totalIncome: Dec; deductionLines: TaxDeductionLine[]
  healthTotal: Dec; educationTotal: Dec; educationDeductible: Dec; educationExcess: Dec; totalDeductible: Dec
}

export function effectiveTaxKind(categoryId: UUID | undefined, categories: Category[]): TaxDeductionKind | undefined {
  let current = categoryId
  let guard = 0
  while (current !== undefined && guard < 20) {
    const c = categories.find((x) => x.id === current)
    if (!c) break
    if (c.taxKind) return c.taxKind
    current = c.parentId
    guard++
  }
  return undefined
}

export function taxSummary(
  year: number, txs: Transaction[], categories: Category[], rules: TaxRules = DEFAULT_TAX_RULES, memberId?: UUID, onlyPaid = true,
): TaxSummary {
  const list = txs.filter((t) =>
    t.type !== 'transfer' && !isInvoicePayment(t) && components(t.date).year === year &&
    (!onlyPaid || t.status === 'paid') && (memberId === undefined || t.memberId === memberId))
  const incomes = new Map<UUID | null, Dec>()
  const deductions = new Map<string, TaxDeductionLine>()
  const educationByPerson = new Map<UUID | null, Dec>()
  let health = ZERO, education = ZERO
  for (const tx of list) {
    if (tx.type === 'income') {
      const k = tx.categoryId ?? null
      incomes.set(k, (incomes.get(k) ?? ZERO).plus(tx.amount))
      continue
    }
    const kind = effectiveTaxKind(tx.categoryId, categories)
    if (!kind) continue
    const key = `${kind}|${tx.categoryId ?? ''}`
    const line = deductions.get(key) ?? { kind, categoryId: tx.categoryId ?? null, total: ZERO, count: 0 }
    line.total = line.total.plus(tx.amount); line.count++
    deductions.set(key, line)
    if (kind === 'health') health = health.plus(tx.amount)
    else {
      education = education.plus(tx.amount)
      const p = tx.memberId ?? null
      educationByPerson.set(p, (educationByPerson.get(p) ?? ZERO).plus(tx.amount))
    }
  }
  const deductible = sum([...educationByPerson.values()].map((v) => (rules.educationAnnualLimit && v.gt(rules.educationAnnualLimit) ? rules.educationAnnualLimit : v)))
  const incomeLines = [...incomes].map(([categoryId, total]) => ({ categoryId, total })).sort((a, b) => {
    if (!a.total.eq(b.total)) return b.total.comparedTo(a.total)
    const x = a.categoryId ?? '', y = b.categoryId ?? ''
    return x < y ? -1 : x > y ? 1 : 0
  })
  const lines = [...deductions.values()].sort((a, b) => {
    if (a.kind !== b.kind) return a.kind < b.kind ? -1 : 1
    if (!a.total.eq(b.total)) return b.total.comparedTo(a.total)
    const x = a.categoryId ?? '', y = b.categoryId ?? ''
    return x < y ? -1 : x > y ? 1 : 0
  })
  return {
    year, incomeLines, totalIncome: sum([...incomes.values()]), deductionLines: lines, healthTotal: health, educationTotal: education,
    educationDeductible: deductible, educationExcess: education.minus(deductible), totalDeductible: health.plus(deductible),
  }
}

export function taxDocument(s: TaxSummary, names: ReportNames, memberName: string | undefined, generatedOn: Date): ReportDocument {
  const incomeRows = s.incomeLines.map((l) => ({
    label: (l.categoryId && names.categories[l.categoryId]) || 'Sem categoria', value: Money.format(l.total), amount: l.total,
  }))
  const kindName: Record<TaxDeductionKind, string> = { health: 'Saúde', education: 'Educação' }
  const deductionRows = s.deductionLines.map((l) => ({
    label: (l.categoryId && names.categories[l.categoryId]) || kindName[l.kind], value: Money.format(l.total), amount: l.total,
    detail: `${kindName[l.kind]}, ${l.count} lançamentos`,
  }))
  const totals: ReportRow[] = [
    { label: 'Total de rendimentos', value: Money.format(s.totalIncome), amount: s.totalIncome },
    { label: 'Saúde (sem limite)', value: Money.format(s.healthTotal), amount: s.healthTotal },
    { label: 'Educação (informada)', value: Money.format(s.educationTotal), amount: s.educationTotal },
    { label: 'Educação dedutível (limite por pessoa)', value: Money.format(s.educationDeductible), amount: s.educationDeductible },
    { label: 'Total dedutível', value: Money.format(s.totalDeductible), amount: s.totalDeductible },
  ]
  return {
    title: `Resumo para o Imposto de Renda ${s.year}`,
    subtitle: memberName ? `Ano-calendário ${s.year}, ${memberName}` : `Ano-calendário ${s.year}, toda a família`,
    generatedOn: `Gerado em ${formatDateBR(generatedOn)}`,
    sections: [
      { title: 'Rendimentos', rows: incomeRows }, { title: 'Despesas dedutíveis', rows: deductionRows }, { title: 'Totais', rows: totals },
    ],
    footer: 'Este resumo é um auxílio e não substitui informes de rendimentos, recibos e notas fiscais. Confira regras e limites vigentes com a Receita Federal.',
  }
}

