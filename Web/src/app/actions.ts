// Operações de negócio sobre o estado (equivalente ao AppStore do iOS). Regras financeiras vêm de src/core.
import * as C from '../core'
import {
  Account, AccountType, Budget, CreditCard, Dec, Debt, FamilyMember, Goal, Investment, MemberRole, Transaction, UUID, YearMonth, ZERO,
} from '../core'
import { Draft, DraftFailure, buildTransactions, makeDefaultCategories, recurrencesToCreate, updateTransaction } from './logic'
import { makeDemoSnapshot } from './seed'
import { Change, useApp } from './store'
import { authApi, Session } from './api'
import { syncNow } from './syncClient'
import { db } from './db'

const st = () => useApp.getState()
export class UserError extends Error {}
const fail = (m: string): never => { throw new UserError(m) }

export function viewerId(): UUID | undefined {
  const { data, settings } = st()
  return data.familyMembers.find((m) => m.id === settings.activeMemberId)?.id ?? data.familyMembers.find((m) => m.role === 'admin')?.id
}
export const viewer = (): FamilyMember | undefined => st().data.familyMembers.find((m) => m.id === viewerId())
const today = (): Date => C.todayCivil()

// ---------- Lançamentos ----------
export type SaveResult = { kind: 'saved'; count: number } | { kind: 'approval' }

export function saveDraft(draft: Draft): SaveResult {
  const s = st()
  if (draft.editingId) {
    const original = s.data.transactions.find((t) => t.id === draft.editingId)
    if (!original) return fail('Lançamento não encontrado.')
    s.put('Transaction', updateTransaction(draft, original, today()))
    checkBudgetAlerts()
    return { kind: 'saved', count: 1 }
  }
  const me = viewer()
  const d: Draft = { ...draft, memberId: draft.memberId ?? me?.id }
  // Dependente acima do limite: vira pedido de aprovação (nenhum saldo muda até um responsável aprovar).
  if (me && me.role === 'dependent' && d.type === 'expense') {
    const decision = C.evaluateSpending(me, d.amount, d.date, s.data.transactions)
    if (decision.kind === 'needsApproval') {
      const acc = d.source?.kind === 'account' ? d.source.id : undefined
      s.put('ApprovalRequest', C.makeApprovalRequest(me, d.title.trim() || 'Despesa', d.amount, d.date, acc, d.categoryId))
      return { kind: 'approval' }
    }
  }
  const list = buildTransactions(d, s.data.creditCards, today())
  s.putMany('Transaction', list)
  materializeRecurrences()
  checkBudgetAlerts()
  return { kind: 'saved', count: list.length }
}

export function materializeRecurrences(horizonDays = 120): void {
  const s = st()
  const end = C.addDays(today(), horizonDays)
  const out: Transaction[] = []
  for (const tpl of s.data.transactions) {
    if (!tpl.recurrence) continue
    out.push(...C.generateRecurrences(tpl, tpl.date, end, [...s.data.transactions, ...out]))
  }
  if (out.length) s.putMany('Transaction', out)
}
export { recurrencesToCreate }

export function deleteTransaction(tx: Transaction, scope: C.InstallmentScope = 'thisOnly'): void {
  const s = st()
  const ids = C.idsToDelete(tx, scope, s.data.transactions)
  // excluir pagamento de fatura devolve o valor à fatura
  const upd: Partial<Change> = { put: [] }
  for (const id of ids) {
    const t = s.data.transactions.find((x) => x.id === id)
    if (t?.invoiceId) {
      const inv = s.data.invoices.find((i) => i.id === t.invoiceId)
      if (inv) {
        const next = { ...inv, paidAmount: C.dmax(inv.paidAmount.minus(t.amount), ZERO), paidAt: undefined, updatedAt: new Date() }
        upd.put!.push(['Invoice', next])
      }
    }
  }
  if (upd.put!.length) s.commit(upd)
  s.del('Transaction', ...ids)
}

export function markPaid(id: UUID, paid = true): void {
  const s = st()
  const tx = s.data.transactions.find((t) => t.id === id)
  if (!tx) return fail('Lançamento não encontrado.')
  s.put('Transaction', { ...tx, status: paid ? 'paid' : 'pending' })
}

export function setTransactionTags(txId: UUID, tagIds: UUID[]): void {
  const tx = st().data.transactions.find((t) => t.id === txId)
  if (tx) st().put('Transaction', { ...tx, tagIds })
}

export function createTag(name: string): C.Tag {
  const n = name.trim()
  if (!n) fail('Informe um nome.')
  const exists = st().data.tags.find((t) => C.normalizeText(t.name) === C.normalizeText(n))
  if (exists) return exists
  const tag = C.mkTag({ name: n })
  st().put('Tag', tag)
  return tag
}

// ---------- Alertas de orçamento (80% e 100%, uma vez cada) ----------
export function checkBudgetAlerts(): void {
  const s = st()
  const alerts = C.budgetAlerts(s.month, s.data.budgets, s.data.transactions, s.data.categories)
  const seen = { ...s.settings.budgetAlertsSeen }
  let changed = false
  for (const a of alerts) {
    const level = a.alert === 'exceeded' ? 100 : 80
    const key = `${a.budget.id}:${C.ymKey(a.budget.month)}`
    if ((seen[key] ?? 0) >= level) continue
    seen[key] = level
    changed = true
    const name = s.data.categories.find((c) => c.id === a.budget.categoryId)?.name ?? 'Categoria'
    s.toast(level === 100 ? `Orçamento de ${name} estourou: ${C.Money.format(a.spent.minus(a.limit))} acima do limite.` : `Orçamento de ${name} chegou a ${a.percentUsed.toFixed(0)}%.`, level === 100 ? 'danger' : 'warn')
  }
  if (changed) s.setSettings({ budgetAlertsSeen: seen })
}

// ---------- Contas e cartões ----------
export function saveAccount(p: { id?: UUID; name: string; type: AccountType; balance: Dec; visibility?: C.Visibility }): Account {
  const name = p.name.trim()
  if (!name) fail('Informe um nome.')
  const s = st()
  if (p.id) {
    const a = s.data.accounts.find((x) => x.id === p.id)!
    const next = { ...a, name, type: p.type, visibility: p.visibility ?? a.visibility }
    s.put('Account', next)
    return next
  }
  const a = C.mkAccount({ name, type: p.type, initialBalance: p.balance, visibility: p.visibility ?? 'shared', ownerId: viewerId() })
  s.put('Account', a)
  return a
}
export function archiveAccount(id: UUID, archived = true): void {
  const a = st().data.accounts.find((x) => x.id === id)
  if (a) st().put('Account', { ...a, isArchived: archived })
}
export function reconcileAccount(account: Account, statement: Dec): void {
  const s = st()
  const adj = C.reconciliationAdjustment(account, statement, s.data.transactions, today())
  if (!adj) { s.toast('A conta já está conciliada.'); return }
  s.put('Transaction', { ...adj, memberId: viewerId() })
  s.toast(`Ajuste de ${C.Money.format(adj.amount)} lançado.`)
}
export function saveCard(p: { id?: UUID; name: string; limit: Dec; closingDay: number; dueDay: number; paymentAccountId?: UUID }): CreditCard {
  const name = p.name.trim()
  if (!name) fail('Informe um nome.')
  if (!p.limit.gte(0)) fail('Limite inválido.')
  if (p.closingDay < 1 || p.closingDay > 31 || p.dueDay < 1 || p.dueDay > 31) fail('Os dias devem ficar entre 1 e 31.')
  const s = st()
  if (p.id) {
    const c = s.data.creditCards.find((x) => x.id === p.id)!
    const next = { ...c, name, limit: p.limit, closingDay: p.closingDay, dueDay: p.dueDay, paymentAccountId: p.paymentAccountId }
    s.put('CreditCard', next)
    return next
  }
  const c = C.mkCard({ name, limit: p.limit, closingDay: p.closingDay, dueDay: p.dueDay, paymentAccountId: p.paymentAccountId, ownerId: viewerId() })
  s.put('CreditCard', c)
  return c
}
export function archiveCard(id: UUID): void {
  const c = st().data.creditCards.find((x) => x.id === id)
  if (c) st().put('CreditCard', { ...c, isArchived: true })
}
export function payInvoice(card: CreditCard, month: YearMonth, amount: Dec | undefined, accountId: UUID): void {
  const s = st()
  const sum = C.summary(card, month, s.data.transactions, s.data.invoices, today())
  const r = wrap(() => C.payInvoice(sum, card, amount, accountId, today()))
  s.commit({ put: [['Invoice', { ...r.invoice, updatedAt: new Date() }], ['Transaction', { ...r.payment, memberId: viewerId() }]] })
}

function wrap<T>(f: () => T): T {
  try { return f() } catch (e) { if (e instanceof C.FinanceError || e instanceof DraftFailure) throw new UserError(e.message); throw e }
}
export { wrap }

// ---------- Orçamento ----------
export function setBudget(categoryId: UUID, month: YearMonth, limit: Dec): void {
  const s = st()
  const existing = s.data.budgets.find((b) => b.categoryId === categoryId && C.ymEq(b.month, month))
  if (limit.lte(0)) { if (existing) s.del('Budget', existing.id); return }
  if (existing) s.put('Budget', { ...existing, limit })
  else s.put('Budget', C.mkBudget({ categoryId, month, limit, ownerId: viewerId() }))
}
export function copyBudgetsFromPrevious(month: YearMonth): number {
  const s = st()
  const have = new Set(s.data.budgets.filter((b) => C.ymEq(b.month, month)).map((b) => b.categoryId))
  const copies = C.copyBudgets(s.data.budgets, C.ymPrev(month), month).filter((b) => !have.has(b.categoryId))
  if (copies.length) s.putMany('Budget', copies)
  return copies.length
}

// ---------- Metas ----------
export function saveGoal(p: { id?: UUID; name: string; target: Dec; deadline?: Date; saved?: Dec; memberId?: UUID }): void {
  const s = st()
  if (p.id) {
    const g = s.data.goals.find((x) => x.id === p.id)!
    s.put('Goal', wrap(() => C.editGoal(g, p.name, p.target, p.deadline)))
    return
  }
  const name = p.name.trim()
  if (!name) fail('Informe um nome.')
  if (!p.target.gt(0)) fail('Informe um valor-alvo maior que zero.')
  s.put('Goal', C.mkGoal({ name, targetAmount: p.target, currentAmount: p.saved ?? ZERO, deadline: p.deadline, memberId: p.memberId, ownerId: viewerId() }))
}
export function deleteGoal(id: UUID): void {
  const s = st()
  const entries = s.data.goalContributions.filter((c) => c.goalId === id).map((c) => c.id)
  if (entries.length) s.del('GoalContribution', ...entries)
  s.del('Goal', id)
}
/** Guarda dinheiro na meta: o valor sai da conta como transferência sem destino (não conta como despesa). */
export function contributeToGoal(goalId: UUID, amount: Dec, accountId: UUID): void {
  const s = st()
  const goal = s.data.goals.find((g) => g.id === goalId)
  if (!goal) return fail('Meta não encontrada.')
  const rec = wrap(() => C.recordContribution(goal, amount, today(), accountId))
  const outflow = C.mkTransaction({
    type: 'transfer', amount, date: today(), title: `Guardado em ${goal.name}`, status: 'paid', accountId, memberId: goal.memberId ?? viewerId(),
  })
  const entry = { ...rec.entry, transactionId: outflow.id }
  s.commit({ put: [['Goal', rec.goal], ['GoalContribution', entry], ['Transaction', outflow]] })
}
export function revertContribution(entryId: UUID): void {
  const s = st()
  const entry = s.data.goalContributions.find((c) => c.id === entryId)
  if (!entry) return
  const goal = s.data.goals.find((g) => g.id === entry.goalId)
  if (goal) s.put('Goal', C.revertContribution(goal, entry))
  if (entry.transactionId) s.del('Transaction', entry.transactionId)
  s.del('GoalContribution', entryId)
}

// ---------- Dívidas e investimentos ----------
export function saveDebt(p: { id?: UUID; name: string; balance: Dec; ratePercent: Dec; minimum: Dec; dueDay?: number }): void {
  const name = p.name.trim()
  if (!name) fail('Informe um nome.')
  if (!p.balance.gt(0)) fail('Informe o saldo devedor.')
  if (p.ratePercent.lt(0)) fail('Juros inválidos.')
  if (p.minimum.lt(0)) fail('Pagamento mínimo inválido.')
  if (p.dueDay !== undefined && (p.dueDay < 1 || p.dueDay > 31)) fail('Dia de vencimento inválido.')
  const s = st()
  const rate = p.ratePercent.div(100)
  if (p.id) {
    const d = s.data.debts.find((x) => x.id === p.id)!
    s.put('Debt', { ...d, name, balance: p.balance, monthlyInterestRate: rate, minimumPayment: p.minimum, dueDay: p.dueDay })
  } else s.put('Debt', C.mkDebt({ name, balance: p.balance, monthlyInterestRate: rate, minimumPayment: p.minimum, dueDay: p.dueDay, ownerId: viewerId() }))
}
export function saveInvestment(p: { id?: UUID; name: string; ticker?: string; assetClass: C.AssetClass; quantity: Dec; averagePrice: Dec; quote?: Dec }): void {
  const name = p.name.trim()
  if (!name) fail('Informe um nome.')
  if (!p.quantity.gt(0)) fail('Quantidade inválida.')
  if (p.averagePrice.lt(0)) fail('Preço inválido.')
  const s = st()
  const ticker = p.ticker?.trim().toUpperCase() || undefined
  if (p.id) {
    const i = s.data.investments.find((x) => x.id === p.id)!
    s.put('Investment', { ...i, name, ticker, assetClass: p.assetClass, quantity: p.quantity, averagePrice: p.averagePrice, quote: p.quote, quoteDate: p.quote ? today() : i.quoteDate })
  } else s.put('Investment', C.mkInvestment({ name, ticker, assetClass: p.assetClass, quantity: p.quantity, averagePrice: p.averagePrice, quote: p.quote, quoteDate: p.quote ? today() : undefined, memberId: viewerId(), ownerId: viewerId() }))
}
export function positionChange(id: UUID, kind: 'buy' | 'sell', quantity: Dec, price: Dec): void {
  const i = st().data.investments.find((x) => x.id === id)!
  st().put('Investment', wrap(() => (kind === 'buy' ? C.buy(i, quantity, price) : C.sell(i, quantity, price))))
}
export function updateQuote(id: UUID, quote: Dec): void {
  const i = st().data.investments.find((x) => x.id === id)!
  st().put('Investment', wrap(() => C.updateQuote(i, quote, today())))
}
export function recordNetWorth(): void {
  const s = st()
  const nw = C.computeNetWorth(s.data.accounts.filter((a) => !a.isArchived), s.data.transactions, s.data.investments, s.data.debts, s.data.creditCards)
  const month = C.ymOf(today())
  const existing = s.data.netWorthSnapshots.find((x) => C.ymEq(x.month, month))
  if (existing) s.put('NetWorthSnapshot', { ...existing, assets: nw.assets, liabilities: nw.liabilities })
  else s.put('NetWorthSnapshot', C.netWorthSnapshot(nw, month))
  s.toast('Patrimônio de ' + C.ymLabel(month) + ' registrado.')
}

// ---------- Categorias ----------
export function addCategory(name: string, kind: C.CategoryKind, visibility: C.Visibility = 'shared', taxKind?: C.TaxDeductionKind): void {
  const n = name.trim()
  if (!n) fail('Informe um nome.')
  st().put('Category', C.mkCategory({ name: n, kind, icon: 'tag', colorHex: 'catOutros', visibility, taxKind, ownerId: viewerId() }))
}
export function updateCategory(id: UUID, p: Partial<Pick<C.Category, 'name' | 'visibility' | 'taxKind'>>): void {
  const c = st().data.categories.find((x) => x.id === id)
  if (c) st().put('Category', { ...c, ...p, ownerId: p.visibility === 'private' ? viewerId() ?? c.ownerId : c.ownerId })
}

// ---------- Importação ----------
export function commitImport(candidates: C.CandidateTransaction[], accountId: UUID): number {
  const list = candidates.filter((c) => !c.isDuplicate).map((c) => ({ ...C.candidateToTransaction(c, accountId), memberId: viewerId() }))
  if (list.length) st().putMany('Transaction', list)
  return list.length
}

// ---------- Família ----------
export function createFamily(name: string, yourName: string): void {
  const s = st()
  const n = name.trim(), y = yourName.trim()
  if (!n || !y) fail('Informe o nome da família e o seu nome.')
  const { household, admin } = C.createHousehold(n, y, s.session?.user.email)
  s.commit({ put: [['Household', household], ['FamilyMember', admin]] })
  s.setSettings({ activeMemberId: admin.id })
}
export function addMember(name: string, role: MemberRole, limit?: Dec): void {
  const s = st()
  const actor = viewer()
  const house = s.data.households[0]
  if (!actor || !house) return fail('Crie a família primeiro.')
  let m = wrap(() => C.addMember(house, name, role, undefined, actor))
  if (role === 'dependent' && limit && limit.gt(0)) m = wrap(() => C.setSpendingLimit(m, limit, actor))
  s.put('FamilyMember', m)
}
export function changeMemberRole(m: FamilyMember, role: MemberRole): void {
  const actor = viewer()!
  st().put('FamilyMember', wrap(() => C.changeRole(m, role, st().data.familyMembers, actor)))
}
export function setMemberLimit(m: FamilyMember, limit: Dec | undefined): void {
  st().put('FamilyMember', wrap(() => C.setSpendingLimit(m, limit, viewer()!)))
}
export function removeMember(m: FamilyMember): void {
  wrap(() => C.validateRemoval(m, st().data.familyMembers, viewer()!))
  st().del('FamilyMember', m.id)
  if (st().settings.activeMemberId === m.id) st().setSettings({ activeMemberId: undefined })
}
export function createSplit(p: Parameters<typeof C.makeSplit>[0], alsoExpense: { accountId?: UUID; categoryId?: UUID } | null): void {
  const s = st()
  let txId: UUID | undefined
  const put: Change['put'] = []
  if (alsoExpense?.accountId) {
    const t = C.mkTransaction({
      type: 'expense', amount: p.total, date: p.date, title: p.title, status: 'paid', accountId: alsoExpense.accountId, categoryId: alsoExpense.categoryId, memberId: p.paidBy,
    })
    txId = t.id
    put.push(['Transaction', t])
  }
  const split = wrap(() => C.makeSplit({ ...p, transactionId: txId }))
  put.push(['ExpenseSplit', split])
  s.commit({ put })
}
export function settleTransfer(t: C.SettlementTransfer): void {
  st().put('SplitSettlement', C.settle(t, today()))
}
export function createAllowance(memberId: UUID, amount: Dec, day: number, from: UUID, to: UUID): void {
  const s = st()
  const m = s.data.familyMembers.find((x) => x.id === memberId)!
  const a = wrap(() => C.makeAllowance(m, amount, day, from, to, C.ymOf(today()), viewer()!))
  s.put('Allowance', a)
  payDueAllowances()
}
export function payDueAllowances(): void {
  const s = st()
  const put: Change['put'] = []
  for (const a of s.data.allowances) {
    const r = C.payAllowance(a, today())
    if (r.transactions.length) { put.push(['Allowance', { ...r.allowance }]); r.transactions.forEach((t) => put.push(['Transaction', t])) }
  }
  if (put.length) s.commit({ put })
}
export function decideApproval(id: UUID, approve: boolean): void {
  const s = st()
  const r = s.data.approvalRequests.find((x) => x.id === id)
  const actor = viewer()
  if (!r || !actor) return
  if (approve) {
    const res = wrap(() => C.approve(r, actor))
    s.commit({ put: [['ApprovalRequest', res.request], ['Transaction', res.transaction]] })
  } else s.put('ApprovalRequest', wrap(() => C.reject(r, actor)))
}

// ---------- Onboarding e dados de exemplo ----------
export function completeOnboarding(p: { accountName: string; type: AccountType; balance: Dec }): void {
  const s = st()
  const name = p.accountName.trim()
  if (!name) fail('Dê um nome para a conta.')
  if (s.data.categories.length === 0) s.putMany('Category', makeDefaultCategories())
  s.put('Account', C.mkAccount({ name, type: p.type, initialBalance: p.balance }))
  s.setSettings({ onboarded: true })
}
export function loadDemo(): void {
  const s = st()
  const snap = makeDemoSnapshot(today())
  for (const t of C.ENTITY_TYPES) {
    const list = snap[C.COLLECTION[t]] as unknown[]
    if (list.length) s.commit({ put: list.map((e) => [t, e]) as unknown as Change['put'] })
  }
  s.setSettings({ onboarded: true })
}
export async function eraseAllData(): Promise<void> {
  // apaga localmente e, se houver conta, propaga as exclusões
  const s = st()
  if (s.session) {
    const dels: Change['del'] = []
    for (const t of C.ENTITY_TYPES) for (const e of s.data[C.COLLECTION[t]] as { id: UUID }[]) dels.push([t, e.id])
    s.commit({ del: dels })
  } else await s.wipeData()
  s.setSettings({ onboarded: false, activeMemberId: undefined, budgetAlertsSeen: {} })
}

// ---------- Conta (login) ----------
async function startSession(tokens: { accessToken: string; refreshToken: string; expiresIn?: number }, user: Session['user'], household: Session['household']): Promise<void> {
  const s = st()
  const owner = await db.getMeta<string>('owner')
  // Dados de outro usuário nunca se misturam com os desta conta.
  if (owner && owner !== user.id) {
    await s.wipeData()
    s.setSettings({ onboarded: false, activeMemberId: undefined, budgetAlertsSeen: {} })
  }
  await db.setMeta('owner', user.id)
  await s.setSession({ accessToken: tokens.accessToken, refreshToken: tokens.refreshToken, expiresAt: Date.now() + (tokens.expiresIn ?? 900) * 1000, user, household })
  // dados criados antes do login (modo local) sobem para a conta
  const queued = new Set((await db.allQueue()).map((q) => q.key))
  const put: Change['put'] = []
  for (const t of C.ENTITY_TYPES) {
    for (const e of s.data[C.COLLECTION[t]] as { id: UUID; updatedAt: Date }[]) {
      if (!queued.has(`${t}:${e.id}`)) put.push([t, e] as unknown as Change['put'][number])
    }
  }
  if (!owner && put.length) {
    await db.putQueue(put.map(([t, e]) => ({ key: `${t}:${e.id}`, type: t, id: e.id, deleted: false, updatedAt: e.updatedAt.toISOString() })))
    s.setSyncInfo({ pending: (await db.allQueue()).length })
  }
  await syncNow()
  if (!st().settings.onboarded && st().data.accounts.length > 0) st().setSettings({ onboarded: true })
}

export async function register(email: string, password: string, name: string): Promise<void> {
  const r = await authApi.register({ email: email.trim(), password, name: name.trim() })
  await startSession(r, r.user, r.household)
}
export async function login(email: string, password: string): Promise<void> {
  const t = await authApi.login({ email: email.trim(), password })
  const me = await authApi.me(t.accessToken)
  await startSession(t, me.user, me.household)
}
export async function logout(): Promise<void> {
  const s = st()
  if (s.session) { try { await authApi.logout(s.session.refreshToken) } catch { /* sem rede: a sessão local é encerrada mesmo assim */ } }
  await s.setSession(null)
}

export type { Budget, Debt, Goal, Investment }
