import { Dec, ZERO } from './decimal'
import { YearMonth, isBeforeDay, ymContains, ymCmp, ymDate, ymLabel, ymNext, ymOf } from './calendar'
import { FinanceError, invalidState } from './errors'
import {
  Account, Allowance, ApprovalRequest, Category, FamilyMember, Household, MemberRole, Transaction, UUID,
  isInvoicePayment, mkHousehold, mkMember, mkTransaction, newId,
} from './models'

export type FamilyPermission =
  | 'manageMembers' | 'manageAllowances' | 'approveSpending' | 'splitExpenses' | 'viewFamilyView' | 'addTransactions' | 'manageSharedData'

export type FamilyScope = { kind: 'family' } | { kind: 'member'; id: UUID }

export function can(role: MemberRole, permission: FamilyPermission): boolean {
  switch (role) {
    case 'admin': return true
    case 'member': return permission !== 'manageMembers' && permission !== 'manageAllowances'
    case 'dependent': return permission === 'addTransactions'
  }
}

const requireName = (raw: string): string => {
  const n = raw.trim()
  if (!n) throw invalidState('Informe um nome.')
  return n
}

export function createHousehold(name: string, adminName: string, email?: string): { household: Household; admin: FamilyMember } {
  const household = mkHousehold({ name: name.trim() })
  const admin = mkMember({ householdId: household.id, name: adminName.trim(), role: 'admin', email })
  return { household, admin }
}

export function addMember(h: Household, name: string, role: MemberRole, email: string | undefined, actor: FamilyMember): FamilyMember {
  if (actor.householdId !== h.id || !can(actor.role, 'manageMembers')) throw new FinanceError('permissionDenied')
  return mkMember({ householdId: h.id, name: requireName(name), role, email })
}

export function setSpendingLimit(member: FamilyMember, limit: Dec | undefined, actor: FamilyMember): FamilyMember {
  if (actor.householdId !== member.householdId || !can(actor.role, 'manageMembers')) throw new FinanceError('permissionDenied')
  if (member.role !== 'dependent') throw invalidState('Só dependentes têm limite de gastos.')
  if (limit && limit.lt(0)) throw new FinanceError('invalidAmount')
  return { ...member, monthlySpendingLimit: limit, updatedAt: new Date() }
}

const adminCount = (members: FamilyMember[], excluding?: UUID): number =>
  members.filter((m) => m.role === 'admin' && m.id !== excluding).length

export function changeRole(member: FamilyMember, role: MemberRole, members: FamilyMember[], actor: FamilyMember): FamilyMember {
  if (actor.householdId !== member.householdId || !can(actor.role, 'manageMembers')) throw new FinanceError('permissionDenied')
  if (member.role === 'admin' && role !== 'admin' && adminCount(members, member.id) === 0) throw new FinanceError('lastAdmin')
  const m = { ...member, role, updatedAt: new Date() }
  if (role !== 'dependent') delete m.monthlySpendingLimit
  return m
}

export function validateRemoval(member: FamilyMember, members: FamilyMember[], actor: FamilyMember): void {
  if (actor.householdId !== member.householdId || !can(actor.role, 'manageMembers')) throw new FinanceError('permissionDenied')
  if (member.role === 'admin' && adminCount(members, member.id) === 0) throw new FinanceError('lastAdmin')
}

// MARK: Privacidade e visões

export function visibleAccounts(accounts: Account[], viewer: UUID | undefined, scope: FamilyScope): Account[] {
  if (scope.kind === 'family') return accounts.filter((a) => a.visibility === 'shared')
  return accounts.filter((a) => a.visibility === 'shared' || (a.ownerId === scope.id && viewer === scope.id))
}

export const visibleCategories = (categories: Category[], viewer: UUID | undefined): Category[] =>
  categories.filter((c) => c.visibility === 'shared' || (c.ownerId !== undefined && c.ownerId === viewer))

export function visibleTransactions(
  txs: Transaction[], accounts: Account[], categories: Category[], viewer: UUID | undefined, scope: FamilyScope,
): Transaction[] {
  const accById = new Map(accounts.map((a) => [a.id, a]))
  const catById = new Map(categories.map((c) => [c.id, c]))
  return txs.filter((tx) => {
    const account = tx.accountId ? accById.get(tx.accountId) : undefined
    const category = tx.categoryId ? catById.get(tx.categoryId) : undefined
    if (account && account.visibility === 'private' && account.ownerId !== viewer) return false
    if (category && category.visibility === 'private' && category.ownerId !== viewer) return false
    if (scope.kind === 'family') return account?.visibility !== 'private' && category?.visibility !== 'private'
    return tx.memberId === scope.id || (tx.memberId === undefined && account?.ownerId === scope.id)
  })
}

// MARK: Aprovação de gastos de dependentes

export type SpendingDecision = { kind: 'allowed' } | { kind: 'needsApproval'; limit: Dec; spent: Dec }

export function memberSpent(memberId: UUID, month: YearMonth, txs: Transaction[]): Dec {
  let acc = ZERO
  for (const t of txs) {
    if (t.memberId !== memberId || t.type !== 'expense' || isInvoicePayment(t) || !ymContains(month, t.date)) continue
    acc = acc.plus(t.amount)
  }
  return acc
}

export function evaluateSpending(member: FamilyMember, amount: Dec, date: Date, txs: Transaction[]): SpendingDecision {
  if (member.role !== 'dependent' || !member.monthlySpendingLimit) return { kind: 'allowed' }
  const limit = member.monthlySpendingLimit
  const spent = memberSpent(member.id, ymOf(date), txs)
  return spent.plus(amount).gt(limit) ? { kind: 'needsApproval', limit, spent } : { kind: 'allowed' }
}

export function makeApprovalRequest(m: FamilyMember, title: string, amount: Dec, date: Date, accountId?: UUID, categoryId?: UUID): ApprovalRequest {
  const now = new Date()
  return { id: newId(), memberId: m.id, title, amount, date, accountId, categoryId, status: 'pending', createdAt: now, updatedAt: now }
}

function ensureDecidable(r: ApprovalRequest, approver: FamilyMember) {
  if (!can(approver.role, 'approveSpending')) throw new FinanceError('permissionDenied')
  if (r.status !== 'pending') throw invalidState('Este pedido já foi decidido.')
}

export function approve(r: ApprovalRequest, approver: FamilyMember, now = new Date()): { request: ApprovalRequest; transaction: Transaction } {
  ensureDecidable(r, approver)
  const tx = mkTransaction({
    type: 'expense', amount: r.amount, date: r.date, title: r.title, status: 'paid', accountId: r.accountId,
    categoryId: r.categoryId, memberId: r.memberId,
  })
  return { request: { ...r, status: 'approved', decidedBy: approver.id, decidedAt: now, transactionId: tx.id, updatedAt: now }, transaction: tx }
}

export function reject(r: ApprovalRequest, approver: FamilyMember, now = new Date()): ApprovalRequest {
  ensureDecidable(r, approver)
  return { ...r, status: 'rejected', decidedBy: approver.id, decidedAt: now, updatedAt: now }
}

export const pendingApprovals = (rs: ApprovalRequest[]): ApprovalRequest[] => rs.filter((r) => r.status === 'pending')

// MARK: Mesada

export const MAX_CATCH_UP_MONTHS = 12

export function makeAllowance(
  member: FamilyMember, amount: Dec, dayOfMonth: number, from: UUID, to: UUID, startMonth: YearMonth, actor: FamilyMember,
): Allowance {
  if (actor.householdId !== member.householdId || !can(actor.role, 'manageAllowances')) throw new FinanceError('permissionDenied')
  if (member.role !== 'dependent') throw invalidState('A mesada é para dependentes.')
  if (!amount.gt(0)) throw new FinanceError('invalidAmount')
  if (dayOfMonth < 1 || dayOfMonth > 31) throw new FinanceError('invalidDay')
  if (from === to) throw new FinanceError('sameAccount')
  const now = new Date()
  return {
    id: newId(), memberId: member.id, amount, dayOfMonth, fromAccountId: from, toAccountId: to, startMonth, isActive: true,
    createdAt: now, updatedAt: now,
  }
}

export function allowanceDueMonths(a: Allowance, asOf: Date): YearMonth[] {
  if (!a.isActive) return []
  let month = a.lastPaidMonth ? ymNext(a.lastPaidMonth) : a.startMonth
  if (ymCmp(month, a.startMonth) < 0) month = a.startMonth
  const result: YearMonth[] = []
  while (!isBeforeDay(asOf, ymDate(month, a.dayOfMonth))) {
    result.push(month)
    month = ymNext(month)
    if (result.length > 1200) break
  }
  return result.slice(-MAX_CATCH_UP_MONTHS)
}

export function payAllowance(a: Allowance, asOf: Date): { allowance: Allowance; transactions: Transaction[] } {
  const months = allowanceDueMonths(a, asOf)
  const last = months[months.length - 1]
  if (!last) return { allowance: a, transactions: [] }
  const transactions = months.map((m) =>
    mkTransaction({
      type: 'transfer', amount: a.amount, date: ymDate(m, a.dayOfMonth), title: `Mesada ${ymLabel(m)}`, status: 'paid',
      accountId: a.fromAccountId, destinationAccountId: a.toAccountId, memberId: a.memberId,
    }))
  return { allowance: { ...a, lastPaidMonth: last, updatedAt: new Date() }, transactions }
}
