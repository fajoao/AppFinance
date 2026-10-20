// Lógica de tela testável, sem React (equivalente a FinanceApp/App/Logic). Toda regra financeira vem de src/core.
import * as C from '../core'
import {
  Account, Category, CategoryKind, CreditCard, Dec, FamilyMember, Invoice, Tag, Transaction, TransactionType, UUID, YearMonth,
  ZERO, dec,
} from '../core'
import { fmtMoney as fmtPlain } from './format'

// ---------- Categorias padrão ----------
interface CatSpec { name: string; kind: CategoryKind; icon: string; token: string; keywords: string[] }
export const CATEGORY_SPECS: CatSpec[] = [
  { name: 'Moradia', kind: 'expense', icon: 'house', token: 'catMoradia', keywords: ['aluguel', 'energia', 'enel', 'agua', 'condominio', 'internet', 'iptu', 'conta de luz'] },
  { name: 'Mercado', kind: 'expense', icon: 'cart', token: 'catMercado', keywords: ['mercado', 'carrefour', 'assai', 'padaria', 'pao de acucar', 'feira', 'acougue', 'hortifruti', 'ifood', 'atacad'] },
  { name: 'Transporte', kind: 'expense', icon: 'car', token: 'catTransporte', keywords: ['uber', '99 pop', '99pop', 'posto', 'gasolina', 'metro', 'onibus', 'estacionamento', 'pedagio'] },
  { name: 'Lazer', kind: 'expense', icon: 'ticket', token: 'catLazer', keywords: ['cinema', 'netflix', 'spotify', 'show', 'restaurante', 'viagem', 'hotel', 'bar do'] },
  { name: 'Saúde', kind: 'expense', icon: 'heart', token: 'catSaude', keywords: ['farmacia', 'drogasil', 'droga', 'medic', 'consulta', 'dentista', 'exame', 'academia'] },
  { name: 'Educação', kind: 'expense', icon: 'book', token: 'catEducacao', keywords: ['escola', 'curso', 'livro', 'faculdade', 'mensalidade', 'ingles'] },
  { name: 'Outros', kind: 'expense', icon: 'ellipsis.circle', token: 'catOutros', keywords: [] },
  { name: 'Salário', kind: 'income', icon: 'briefcase', token: 'income', keywords: ['salario', 'holerite'] },
  { name: 'Freelance', kind: 'income', icon: 'laptopcomputer', token: 'income', keywords: ['freela', 'cliente', 'projeto'] },
  { name: 'Rendimentos', kind: 'income', icon: 'chart.line.uptrend.xyaxis', token: 'income', keywords: ['rendimento', 'juros', 'dividendo'] },
  { name: 'Outros', kind: 'income', icon: 'ellipsis.circle', token: 'income', keywords: [] },
]

export function makeDefaultCategories(): Category[] {
  return CATEGORY_SPECS.map((s) =>
    C.mkCategory({
      name: s.name, kind: s.kind, icon: s.icon, colorHex: s.token,
      taxKind: s.kind === 'expense' ? (s.name === 'Saúde' ? 'health' : s.name === 'Educação' ? 'education' : undefined) : undefined,
    }),
  )
}

export function categoryKeywords(categories: Category[], kind: CategoryKind): Record<UUID, string[]> {
  const out: Record<UUID, string[]> = {}
  for (const c of categories) {
    if (c.kind !== kind || c.parentId) continue
    const spec = CATEGORY_SPECS.find((s) => s.name === c.name && s.kind === kind)
    if (spec && spec.keywords.length) out[c.id] = spec.keywords
  }
  return out
}

/** O nome do ícone SF (convenção do iOS) vira o ícone web. */
const SF_TO_WEB: Record<string, string> = {
  house: 'house', cart: 'cart', car: 'car', ticket: 'ticket', heart: 'heart', book: 'book', 'ellipsis.circle': 'dots',
  briefcase: 'briefcase', laptopcomputer: 'laptop', 'chart.line.uptrend.xyaxis': 'trend', tag: 'tag',
}
export const webIcon = (sf?: string): string => (sf && SF_TO_WEB[sf]) || 'tag'

/** colorHex guarda o nome do token ("catMoradia"); vira variável CSS. */
export function catColorVar(cat: Category | undefined, byId: Map<UUID, Category>): string {
  let c = cat
  for (let i = 0; c && i < 5; i++) {
    const t = c.colorHex
    if (t && (t.startsWith('cat') || t === 'income')) return t === 'income' ? 'var(--income)' : `var(--${t.replace(/([A-Z])/g, '-$1').toLowerCase()})`
    c = c.parentId ? byId.get(c.parentId) : undefined
  }
  return 'var(--cat-outros)'
}

// ---------- Rascunho de lançamento ----------
export type RepeatKind = 'none' | 'installments' | 'monthly' | 'weekly'
export interface Draft {
  editingId?: UUID
  type: TransactionType
  amount: Dec
  title: string
  categoryId?: UUID
  /** conta ou cartão de origem */
  source?: { kind: 'account' | 'card'; id: UUID }
  destinationAccountId?: UUID
  date: Date
  repeat: RepeatKind
  installments: number
  tagIds: UUID[]
  note: string
  memberId?: UUID
}
export const newDraft = (date: Date, type: TransactionType = 'expense', accountId?: UUID): Draft => ({
  type, amount: ZERO, title: '', date, repeat: 'none', installments: 2, tagIds: [], note: '',
  source: accountId ? { kind: 'account', id: accountId } : undefined,
})
export function draftFrom(tx: Transaction): Draft {
  const suffix = tx.installment ? ` (${tx.installment.number}/${tx.installment.total})` : ''
  return {
    editingId: tx.id, type: tx.type, amount: tx.amount, title: suffix && tx.title.endsWith(suffix) ? tx.title.slice(0, -suffix.length) : tx.title,
    categoryId: tx.categoryId,
    source: tx.creditCardId && !tx.invoiceId ? { kind: 'card', id: tx.creditCardId } : tx.accountId ? { kind: 'account', id: tx.accountId } : undefined,
    destinationAccountId: tx.destinationAccountId, date: tx.date, repeat: 'none', installments: 2, tagIds: tx.tagIds, note: tx.note ?? '', memberId: tx.memberId,
  }
}

export type DraftError = 'zeroAmount' | 'missingSource' | 'missingDestination' | 'sameAccount' | 'cardNotFound'
export const DRAFT_MESSAGES: Record<DraftError, string> = {
  zeroAmount: 'Digite um valor maior que zero.',
  missingSource: 'Escolha a conta ou o cartão.',
  missingDestination: 'Escolha a conta de destino.',
  sameAccount: 'Origem e destino devem ser contas diferentes.',
  cardNotFound: 'Cartão não encontrado.',
}
export class DraftFailure extends Error {
  constructor(public code: DraftError) { super(DRAFT_MESSAGES[code]) }
}

export function validateDraft(d: Draft): DraftError | null {
  if (!d.amount.gt(0)) return 'zeroAmount'
  if (d.type === 'transfer') {
    if (d.source?.kind !== 'account') return 'missingSource'
    if (!d.destinationAccountId) return 'missingDestination'
    if (d.source.id === d.destinationAccountId) return 'sameAccount'
  } else if (!d.source) return 'missingSource'
  return null
}
export const effectiveTitle = (d: Draft): string => d.title.trim() || (d.type === 'expense' ? 'Despesa' : d.type === 'income' ? 'Receita' : 'Transferência')
export const saveLabel = (d: Draft): string =>
  d.editingId ? 'Salvar alterações' : d.type === 'expense' ? 'Salvar despesa' : d.type === 'income' ? 'Salvar receita' : 'Salvar transferência'

/** Parcelas calculadas pelo Core (a última absorve o resto de centavos). */
export function installmentSummary(d: Draft): string | null {
  if (d.repeat !== 'installments' || !d.amount.gt(0)) return null
  const v = C.splitInstallments(d.amount, d.installments)
  const first = v[0]!, last = v[v.length - 1]!
  const f = (x: Dec) => fmtPlain(x)
  return `${d.installments}x de ${f(first)}${last.eq(first) ? '' : `, última ${f(last)}`}`
}

export function buildTransactions(d: Draft, cards: CreditCard[], today: Date): Transaction[] {
  const err = validateDraft(d)
  if (err) throw new DraftFailure(err)
  const status = C.isBeforeDay(today, d.date) ? 'pending' : 'paid'
  const note = d.note.trim() || undefined
  const title = effectiveTitle(d)
  const withRecurrence = (t: Transaction): Transaction => {
    if (d.repeat === 'monthly') t.recurrence = { frequency: 'monthly', interval: 1 }
    if (d.repeat === 'weekly') t.recurrence = { frequency: 'weekly', interval: 1 }
    return t
  }
  if (d.type === 'transfer') {
    const t = C.makeTransfer(d.source!.id, d.destinationAccountId!, d.amount, d.date, title, status)
    t.note = note; t.tagIds = d.tagIds; t.memberId = d.memberId
    return [withRecurrence(t)]
  }
  if (d.source!.kind === 'card') {
    const card = cards.find((c) => c.id === d.source!.id)
    if (!card) throw new DraftFailure('cardNotFound')
    const list = C.makePurchase(card, title, d.amount, d.date, d.repeat === 'installments' ? d.installments : 1, d.categoryId, d.tagIds)
    list.forEach((t) => { t.note = note; t.memberId = d.memberId })
    if (list.length === 1) withRecurrence(list[0]!)
    return list
  }
  const base = C.mkTransaction({
    type: d.type, amount: d.amount, date: d.date, title, status, accountId: d.source!.id, categoryId: d.categoryId, tagIds: d.tagIds, note, memberId: d.memberId,
  })
  if (d.repeat === 'installments') {
    const list = C.makeInstallments(base, d.installments)
    list[0]!.status = status
    return list
  }
  return [withRecurrence(base)]
}

export function updateTransaction(d: Draft, original: Transaction, today: Date): Transaction {
  const err = validateDraft(d)
  if (err) throw new DraftFailure(err)
  const t: Transaction = { ...original, amount: d.amount, date: d.date }
  const base = effectiveTitle(d)
  t.title = original.installment ? `${base} (${original.installment.number}/${original.installment.total})` : base
  t.categoryId = d.type === 'transfer' ? undefined : d.categoryId
  t.tagIds = d.tagIds
  t.note = d.note.trim() || undefined
  t.memberId = d.memberId
  if (d.source!.kind === 'card') { t.creditCardId = d.source!.id; t.accountId = undefined }
  else { t.accountId = d.source!.id; if (original.creditCardId && !original.invoiceId) t.creditCardId = undefined }
  t.destinationAccountId = d.type === 'transfer' ? d.destinationAccountId : undefined
  if (!C.isCardPurchase(t) && C.isBeforeDay(today, d.date)) t.status = 'pending'
  t.updatedAt = new Date()
  return t
}

// ---------- Contas a pagar ----------
export interface BillItem {
  id: string; title: string; amount: Dec; dueDate: Date; direction: 'payable' | 'receivable'; isPaid: boolean
  transactionId?: UUID; cardId?: UUID; invoiceMonth?: YearMonth; categoryId?: UUID
}
export type BillTone = 'ok' | 'danger' | 'warning' | 'brand' | 'neutral'
export interface BillStatus { label: string; tone: BillTone }
export const ALERT_WINDOW_DAYS = 3

export function billStatus(b: BillItem, today: Date): BillStatus {
  const receivable = b.direction === 'receivable'
  if (b.isPaid) return { label: receivable ? 'Recebido' : 'Pago', tone: 'ok' }
  const d = C.daysBetween(today, b.dueDate)
  if (d < 0) return { label: receivable ? 'Recebimento atrasado' : `Atrasado ${-d} ${-d === 1 ? 'dia' : 'dias'}`, tone: 'danger' }
  if (receivable) return { label: 'A receber', tone: 'brand' }
  if (d === 0) return { label: 'Vence hoje', tone: 'warning' }
  if (d <= ALERT_WINDOW_DAYS) return { label: d === 1 ? 'Vence amanhã' : `Vence em ${d} dias`, tone: 'warning' }
  return { label: 'Pendente', tone: 'neutral' }
}

export function billItems(txs: Transaction[], cards: CreditCard[], invoices: Invoice[], today: Date, horizon = 3): BillItem[] {
  const out: BillItem[] = []
  for (const tx of txs) {
    if (tx.type === 'transfer' || C.isCardPurchase(tx)) continue
    const scheduled = tx.recurrence || tx.recurrenceParentId || tx.installment
    if (tx.status !== 'pending' && !scheduled) continue
    out.push({
      id: `tx-${tx.id}`, title: tx.title, amount: tx.amount, dueDate: tx.date, direction: tx.type === 'income' ? 'receivable' : 'payable',
      isPaid: tx.status === 'paid', transactionId: tx.id, categoryId: tx.categoryId,
    })
  }
  for (const card of cards) {
    if (card.isArchived) continue
    for (const s of C.upcomingInvoices(card, txs, invoices, today, horizon)) {
      if (!s.total.gt(0)) continue
      const paid = s.status === 'paid'
      out.push({
        id: `inv-${card.id}-${C.ymLabel(s.invoice.month)}`, title: `Fatura ${card.name}`, amount: paid ? s.total : s.remaining,
        dueDate: s.invoice.dueDate, direction: 'payable', isPaid: paid, cardId: card.id, invoiceMonth: s.invoice.month,
      })
    }
  }
  return out.sort((a, b) => a.dueDate.getTime() - b.dueDate.getTime() || a.title.localeCompare(b.title, 'pt-BR'))
}
export const billsIn = (all: BillItem[], m: YearMonth): BillItem[] => all.filter((b) => C.ymContains(m, b.dueDate))
export function billTotals(items: BillItem[]): { toPay: Dec; toReceive: Dec } {
  let pay = ZERO, rec = ZERO
  for (const b of items) {
    if (b.isPaid) continue
    if (b.direction === 'payable') pay = pay.plus(b.amount); else rec = rec.plus(b.amount)
  }
  return { toPay: pay, toReceive: rec }
}
export function calendarWeeks(m: YearMonth): (Date | null)[][] {
  const cells: (Date | null)[] = Array.from({ length: C.ymFirst(m).getUTCDay() }, () => null)
  for (let d = 1; d <= C.daysInMonth(m); d++) cells.push(C.ymDate(m, d))
  while (cells.length % 7 !== 0) cells.push(null)
  const weeks: (Date | null)[][] = []
  for (let i = 0; i < cells.length; i += 7) weeks.push(cells.slice(i, i + 7))
  return weeks
}
export function billDots(day: Date, bills: BillItem[], today: Date): BillTone[] {
  const tones = new Set(bills.filter((b) => C.isSameDay(b.dueDate, day)).map((b) => billStatus(b, today).tone))
  return (['danger', 'warning', 'brand', 'neutral', 'ok'] as BillTone[]).filter((t) => tones.has(t))
}

// ---------- Filtros de lançamentos ----------
export type FilterPeriod = 'thisMonth' | 'lastMonth' | 'last30Days' | 'thisYear' | 'all'
export const PERIOD_TITLES: Record<FilterPeriod, string> = {
  thisMonth: 'Este mês', lastMonth: 'Mês passado', last30Days: 'Últimos 30 dias', thisYear: 'Este ano', all: 'Tudo',
}
export interface TxFilter {
  query: string; period: FilterPeriod; type: 'all' | TransactionType
  sourceIds: Set<UUID>; categoryIds: Set<UUID>; tagId?: UUID; min?: Dec; max?: Dec
}
export const emptyFilter = (): TxFilter => ({ query: '', period: 'thisMonth', type: 'all', sourceIds: new Set(), categoryIds: new Set() })
export function advancedCount(f: TxFilter): number {
  return (f.period !== 'thisMonth' ? 1 : 0) + (f.type !== 'all' ? 1 : 0) + (f.sourceIds.size ? 1 : 0) + (f.categoryIds.size ? 1 : 0) + (f.min || f.max ? 1 : 0) + (f.tagId ? 1 : 0)
}

export interface Lookup {
  accounts: Map<UUID, Account>; categories: Map<UUID, Category>; tags: Map<UUID, Tag>; cards: Map<UUID, CreditCard>; members: Map<UUID, FamilyMember>
}
export function makeLookup(p: { accounts: Account[]; categories: Category[]; tags: Tag[]; cards: CreditCard[]; members: FamilyMember[] }): Lookup {
  return {
    accounts: new Map(p.accounts.map((x) => [x.id, x])), categories: new Map(p.categories.map((x) => [x.id, x])),
    tags: new Map(p.tags.map((x) => [x.id, x])), cards: new Map(p.cards.map((x) => [x.id, x])), members: new Map(p.members.map((x) => [x.id, x])),
  }
}
export const categoryName = (l: Lookup, id?: UUID): string => (id && l.categories.get(id)?.name) || 'Sem categoria'
export function sourceName(l: Lookup, tx: Transaction): string {
  if (tx.creditCardId && l.cards.get(tx.creditCardId)) return l.cards.get(tx.creditCardId)!.name
  if (tx.accountId && l.accounts.get(tx.accountId)) return l.accounts.get(tx.accountId)!.name
  return '—'
}
export function accountLabel(l: Lookup, tx: Transaction): string {
  if (tx.type === 'transfer' && !tx.invoiceId && tx.destinationAccountId && l.accounts.get(tx.destinationAccountId)) {
    return `${sourceName(l, tx)} → ${l.accounts.get(tx.destinationAccountId)!.name}`
  }
  return sourceName(l, tx)
}

export function matchesFilter(tx: Transaction, f: TxFilter, l: Lookup, today: Date, month: YearMonth): boolean {
  const m = C.ymOf(tx.date)
  switch (f.period) {
    case 'thisMonth': if (!C.ymEq(m, month)) return false; break
    case 'lastMonth': if (!C.ymEq(m, C.ymPrev(month))) return false; break
    case 'thisYear': if (tx.date.getUTCFullYear() !== month.year) return false; break
    case 'last30Days': { const d = C.daysBetween(tx.date, today); if (d < 0 || d > 30) return false; break }
  }
  if (f.type !== 'all' && tx.type !== f.type) return false
  if (f.sourceIds.size) {
    const ids = [tx.accountId, tx.destinationAccountId, tx.creditCardId].filter((x): x is string => !!x)
    if (!ids.some((i) => f.sourceIds.has(i))) return false
  }
  if (f.categoryIds.size) {
    if (!tx.categoryId) return false
    const parent = l.categories.get(tx.categoryId)?.parentId
    if (!f.categoryIds.has(tx.categoryId) && !(parent && f.categoryIds.has(parent))) return false
  }
  if (f.tagId && !tx.tagIds.includes(f.tagId)) return false
  if (f.min && tx.amount.abs().lt(f.min)) return false
  if (f.max && tx.amount.abs().gt(f.max)) return false
  const q = C.normalizeText(f.query)
  if (q) {
    const hay = [tx.title, categoryName(l, tx.categoryId), accountLabel(l, tx), ...tx.tagIds.map((t) => l.tags.get(t)?.name ?? ''), tx.note ?? '']
    if (!hay.some((h) => C.normalizeText(h).includes(q))) return false
  }
  return true
}

export interface DayGroup { date: Date; items: Transaction[]; total: Dec }
export function groupByDay(txs: Transaction[]): DayGroup[] {
  const sorted = [...txs].sort((a, b) => b.date.getTime() - a.date.getTime() || b.createdAt.getTime() - a.createdAt.getTime())
  const groups: DayGroup[] = []
  for (const t of sorted) {
    let g = groups[groups.length - 1]
    if (!g || !C.isSameDay(g.date, t.date)) { g = { date: t.date, items: [], total: ZERO }; groups.push(g) }
    g.items.push(t)
    if (t.type !== 'transfer' && !t.invoiceId) g.total = g.total.plus(C.signedAmount(t))
  }
  return groups
}

// ---------- Dados derivados ----------
export function nextDues(bills: BillItem[], today: Date, n = 3): BillItem[] {
  void today
  return bills.filter((b) => !b.isPaid && b.direction === 'payable').slice(0, n)
}

/** Materializa ocorrências pendentes das recorrências nos próximos `days` dias (idempotente). */
export function recurrencesToCreate(txs: Transaction[], today: Date, days = 60): Transaction[] {
  const end = C.addDays(today, days)
  const out: Transaction[] = []
  for (const tpl of txs) {
    if (!tpl.recurrence) continue
    out.push(...C.generateRecurrences(tpl, C.addDays(today, -31), end, [...txs, ...out]))
  }
  return out
}

export const dec0 = (s: string): Dec => dec(s)
