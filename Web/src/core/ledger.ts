import { Dec, ZERO, sum } from './decimal'
import {
  addDays, addMonths, addYears, isSameDay, startOfDay,
} from './calendar'
import { FinanceError } from './errors'
import * as Money from './money'
import {
  Account, AccountType, InstallmentInfo, RecurrenceRule, Transaction, UUID, isCardPurchase, newId, mkTransaction,
} from './models'

// MARK: BalanceEngine

export function effectOf(tx: Transaction, accountId: UUID): Dec {
  if (isCardPurchase(tx)) return ZERO
  switch (tx.type) {
    case 'income': return tx.accountId === accountId ? tx.amount : ZERO
    case 'expense': return tx.accountId === accountId ? tx.amount.neg() : ZERO
    case 'transfer': {
      let v = ZERO
      if (tx.accountId === accountId) v = v.minus(tx.amount)
      if (tx.destinationAccountId === accountId) v = v.plus(tx.amount)
      return v
    }
  }
}

export function balanceOf(account: Account, transactions: Transaction[], asOf?: Date, includePending = false): Dec {
  let total = account.initialBalance
  for (const tx of transactions) {
    if (!includePending && tx.status !== 'paid') continue
    if (asOf && startOfDay(tx.date).getTime() > startOfDay(asOf).getTime()) continue
    total = total.plus(effectOf(tx, account.id))
  }
  return total
}

export function totalBalance(
  accounts: Account[], transactions: Transaction[], opts: { asOf?: Date; includePending?: boolean; types?: Set<AccountType> } = {},
): Dec {
  return sum(
    accounts
      .filter((a) => !a.isArchived && (opts.types?.has(a.type) ?? true))
      .map((a) => balanceOf(a, transactions, opts.asOf, opts.includePending ?? false)),
  )
}

export function makeTransfer(
  from: UUID, to: UUID, amount: Dec, date: Date, title = 'Transferência', status: 'paid' | 'pending' = 'paid',
): Transaction {
  if (from === to) throw new FinanceError('sameAccount')
  if (!amount.gt(0)) throw new FinanceError('invalidAmount')
  return mkTransaction({ type: 'transfer', amount, date, title, status, accountId: from, destinationAccountId: to })
}

export function reconciliationDifference(account: Account, statementBalance: Dec, transactions: Transaction[], asOf?: Date): Dec {
  return statementBalance.minus(balanceOf(account, transactions, asOf))
}

export function reconciliationAdjustment(account: Account, statementBalance: Dec, transactions: Transaction[], date: Date): Transaction | null {
  const diff = reconciliationDifference(account, statementBalance, transactions, date)
  if (diff.isZero()) return null
  return mkTransaction({
    type: diff.gt(0) ? 'income' : 'expense', amount: diff.abs(), date, title: 'Ajuste de conciliação',
    status: 'paid', accountId: account.id,
  })
}

// MARK: InstallmentEngine

export function splitInstallments(total: Dec, count: number): Dec[] {
  if (count < 1) throw new FinanceError('invalidInstallmentCount')
  return Money.split(total, count)
}

/** Gera as N parcelas a partir do lançamento modelo (amount = total). A última absorve o resto de centavos. */
export function makeInstallments(template: Transaction, count: number): Transaction[] {
  const parts = splitInstallments(template.amount, count)
  const group = newId()
  return parts.map((value, i) => {
    const now = new Date()
    const t: Transaction = {
      ...template,
      id: newId(),
      amount: value,
      date: addMonths(template.date, i),
      installment: { number: i + 1, total: count, groupId: group },
      title: `${template.title} (${i + 1}/${count})`,
      recurrence: undefined,
      createdAt: now,
      updatedAt: now,
    }
    if (i > 0 && template.creditCardId === undefined) t.status = 'pending'
    return t
  })
}

export type InstallmentScope = 'thisOnly' | 'thisAndFuture' | 'all'
export const installmentScopeName: Record<InstallmentScope, string> = {
  thisOnly: 'Só esta parcela', thisAndFuture: 'Esta e as seguintes', all: 'Todas as parcelas',
}
export const installmentLabel = (i: InstallmentInfo): string => `${i.number}/${i.total}`

export function groupMembers(tx: Transaction, all: Transaction[]): Transaction[] {
  const g = tx.installment?.groupId
  if (!g) return [tx]
  return all.filter((t) => t.installment?.groupId === g).sort((a, b) => (a.installment?.number ?? 0) - (b.installment?.number ?? 0))
}

export function idsToDelete(tx: Transaction, scope: InstallmentScope, all: Transaction[]): UUID[] {
  const info = tx.installment
  if (!info) return [tx.id]
  const members = groupMembers(tx, all)
  switch (scope) {
    case 'thisOnly': return [tx.id]
    case 'thisAndFuture': return members.filter((m) => (m.installment?.number ?? 0) >= info.number).map((m) => m.id)
    case 'all': return members.map((m) => m.id)
  }
}

// MARK: RecurrenceEngine

/** Datas das ocorrências em [from, to] (inclusive), sempre calculadas a partir da data inicial (sem deriva). */
export function occurrences(start: Date, rule: RecurrenceRule, from: Date, to: Date): Date[] {
  const interval = Math.max(rule.interval, 1)
  const result: Date[] = []
  const fromDay = startOfDay(from).getTime(), toDay = startOfDay(to).getTime()
  for (let k = 0; k <= 100_000; k++) {
    if (rule.maxOccurrences !== undefined && k >= rule.maxOccurrences) break
    let date: Date
    switch (rule.frequency) {
      case 'weekly': date = addDays(start, 7 * interval * k); break
      case 'monthly': date = addMonths(start, interval * k); break
      case 'yearly': date = addYears(start, interval * k); break
    }
    const day = startOfDay(date).getTime()
    if (day > toDay) break
    if (rule.endDate && day > startOfDay(rule.endDate).getTime()) break
    if (day >= fromDay) result.push(date)
  }
  return result
}

/** Gera ocorrências pendentes do modelo recorrente em [from, to], sem duplicar as já existentes. */
export function generateRecurrences(template: Transaction, from: Date, to: Date, existing: Transaction[] = []): Transaction[] {
  const rule = template.recurrence
  if (!rule) return []
  const taken = new Set(existing.filter((t) => t.recurrenceParentId === template.id).map((t) => startOfDay(t.date).getTime()))
  const out: Transaction[] = []
  for (const date of occurrences(template.date, rule, from, to)) {
    if (isSameDay(date, template.date)) continue
    if (taken.has(startOfDay(date).getTime())) continue
    const now = new Date()
    out.push({
      ...template, id: newId(), date, recurrence: undefined, recurrenceParentId: template.id, status: 'pending',
      createdAt: now, updatedAt: now,
    })
  }
  return out
}
