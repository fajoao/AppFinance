import { Dec, ZERO, dmax, sum } from './decimal'
import {
  YearMonth, components, daysInMonth, startOfDay, ymAdd, ymDate, ymEq, ymNext, ymOf, ymPrev,
} from './calendar'
import { FinanceError } from './errors'
import { makeInstallments } from './ledger'
import { CreditCard, Invoice, InvoiceStatus, Transaction, UUID, isCardPurchase, isInvoicePayment, mkTransaction, newId } from './models'

export interface InvoiceSummary {
  invoice: Invoice
  /** true se a fatura já existe no repositório (tem pagamento registrado). */
  isStored: boolean
  total: Dec
  paidAmount: Dec
  remaining: Dec
  status: InvoiceStatus
  transactions: Transaction[]
}

const clampDay = (day: number, m: YearMonth): number => Math.min(Math.max(day, 1), daysInMonth(m))

export const closingDate = (card: CreditCard, month: YearMonth): Date => ymDate(month, card.closingDay)

/** Vencimento da fatura que fecha em `month`: mesmo mês se dueDay > closingDay; senão mês seguinte. */
export const dueDate = (card: CreditCard, month: YearMonth): Date =>
  ymDate(card.dueDay > card.closingDay ? month : ymNext(month), card.dueDay)

/** Mês de fechamento da fatura à qual a compra pertence. Compra no dia do fechamento ou depois vai para a próxima. */
export function invoiceMonthFor(date: Date, card: CreditCard): YearMonth {
  const m = ymOf(date)
  return components(date).day < clampDay(card.closingDay, m) ? m : ymNext(m)
}
export const currentInvoiceMonth = (card: CreditCard, asOf: Date): YearMonth => invoiceMonthFor(asOf, card)

export function purchases(card: CreditCard, month: YearMonth, txs: Transaction[]): Transaction[] {
  return txs
    .filter((t) => t.creditCardId === card.id && isCardPurchase(t) && ymEq(invoiceMonthFor(t.date, card), month))
    .sort((a, b) => a.date.getTime() - b.date.getTime())
}

const chargeValue = (t: Transaction): Dec => (t.type === 'income' ? t.amount.neg() : t.amount)

export const invoiceTotal = (card: CreditCard, month: YearMonth, txs: Transaction[]): Dec =>
  sum(purchases(card, month, txs).map(chargeValue))

export function summary(card: CreditCard, month: YearMonth, txs: Transaction[], stored: Invoice[], asOf: Date): InvoiceSummary {
  const items = purchases(card, month, txs)
  const total = sum(items.map(chargeValue))
  const found = stored.find((i) => i.cardId === card.id && ymEq(i.month, month))
  const now = new Date()
  const invoice: Invoice = found ?? {
    id: newId(), cardId: card.id, month, closingDate: closingDate(card, month), dueDate: dueDate(card, month),
    paidAmount: ZERO, ownerId: card.ownerId, createdAt: now, updatedAt: now,
  }
  const paid = invoice.paidAmount
  const day = startOfDay(asOf).getTime()
  let status: InvoiceStatus
  if (total.gt(0) ? paid.gte(total) : found?.paidAt !== undefined) status = 'paid'
  else if (day > startOfDay(invoice.dueDate).getTime()) status = 'overdue'
  else if (day >= startOfDay(invoice.closingDate).getTime()) status = 'closed'
  else status = 'open'
  return {
    invoice, isStored: found !== undefined, total, paidAmount: paid, remaining: dmax(total.minus(paid), ZERO),
    status, transactions: items,
  }
}

/** Fatura atual + as próximas `futureCount`; inclui a anterior se ainda tiver saldo em aberto. */
export function upcomingInvoices(card: CreditCard, txs: Transaction[], stored: Invoice[], asOf: Date, futureCount = 3): InvoiceSummary[] {
  const current = currentInvoiceMonth(card, asOf)
  const months: YearMonth[] = []
  const prev = ymPrev(current)
  const ps = summary(card, prev, txs, stored, asOf)
  if (ps.total.gt(0) && ps.status !== 'paid') months.push(prev)
  months.push(current)
  for (let i = 1; i <= Math.max(futureCount, 1) && i <= futureCount; i++) months.push(ymAdd(current, i))
  return months.map((m) => summary(card, m, txs, stored, asOf))
}

export function usedLimit(card: CreditCard, txs: Transaction[]): Dec {
  const charges = sum(txs.filter((t) => t.creditCardId === card.id && isCardPurchase(t)).map(chargeValue))
  const payments = sum(txs.filter((t) => t.creditCardId === card.id && isInvoicePayment(t)).map((t) => t.amount))
  return charges.minus(payments)
}
export const availableLimit = (card: CreditCard, txs: Transaction[]): Dec => card.limit.minus(usedLimit(card, txs))

/** Paga (total ou parcialmente) uma fatura. Retorna a fatura atualizada e o lançamento de pagamento. */
export function payInvoice(
  s: InvoiceSummary, card: CreditCard, amount: Dec | undefined, from: UUID, on: Date,
): { invoice: Invoice; payment: Transaction } {
  const value = amount ?? s.remaining
  if (!value.gt(0)) throw new FinanceError('invalidAmount')
  if (value.gt(s.remaining)) throw new FinanceError('overpayment')
  const inv: Invoice = { ...s.invoice, paidAmount: s.invoice.paidAmount.plus(value), paymentAccountId: from, updatedAt: new Date() }
  if (inv.paidAmount.gte(s.total)) inv.paidAt = on
  const payment = mkTransaction({
    type: 'transfer', amount: value, date: on, title: `Pagamento fatura ${card.name} ${monthLabel(s.invoice.month)}`,
    status: 'paid', accountId: from, creditCardId: card.id, invoiceId: inv.id, ownerId: card.ownerId,
  })
  return { invoice: inv, payment }
}

const monthLabel = (m: YearMonth): string => `${String(m.month).padStart(2, '0')}/${m.year}`

/** Registra a compra no cartão (parcelada se installments > 1). Retorna as transações a salvar. */
export function makePurchase(
  card: CreditCard, title: string, total: Dec, date: Date, installments = 1, categoryId?: UUID, tagIds: UUID[] = [],
): Transaction[] {
  const base = mkTransaction({
    type: 'expense', amount: total, date, title, status: 'paid', categoryId, tagIds, creditCardId: card.id, ownerId: card.ownerId,
  })
  return installments <= 1 ? [base] : makeInstallments(base, installments)
}
