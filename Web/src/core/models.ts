import { Dec, ZERO } from './decimal'
import type { YearMonth } from './calendar'

// Espelho dos modelos Codable do Core Swift (FinanceApp/Core/Models*.swift). Dinheiro: Decimal (decimal.js).
// Datas: Date (dia civil = UTC 12:00). Na rede/armazenamento usa-se o formato do Swift (veja codec.ts).

export type UUID = string
/** UUID v4 em maiúsculas (como o Swift). randomUUID só existe em contexto seguro (https/localhost); há fallback para http na rede local. */
export function newId(): UUID {
  const c = globalThis.crypto
  if (c && typeof c.randomUUID === 'function') return c.randomUUID().toUpperCase()
  const b = new Uint8Array(16)
  if (c?.getRandomValues) c.getRandomValues(b)
  else for (let i = 0; i < 16; i++) b[i] = Math.floor(Math.random() * 256)
  b[6] = (b[6]! & 0x0f) | 0x40
  b[8] = (b[8]! & 0x3f) | 0x80
  const h = [...b].map((x) => x.toString(16).padStart(2, '0')).join('').toUpperCase()
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`
}

export type AccountType = 'checking' | 'savings' | 'wallet' | 'investment'
export const ACCOUNT_TYPES: AccountType[] = ['checking', 'savings', 'wallet', 'investment']
export const accountTypeName: Record<AccountType, string> = {
  checking: 'Conta corrente',
  savings: 'Poupança',
  wallet: 'Carteira',
  investment: 'Investimentos',
}
export type CategoryKind = 'income' | 'expense'
export type TransactionType = 'income' | 'expense' | 'transfer'
export type TransactionStatus = 'pending' | 'paid'
export type RecurrenceFrequency = 'weekly' | 'monthly' | 'yearly'
export type MemberRole = 'admin' | 'member' | 'dependent'
export const roleName: Record<MemberRole, string> = { admin: 'Administrador', member: 'Membro', dependent: 'Dependente' }
export type Visibility = 'shared' | 'private'
export type TaxDeductionKind = 'health' | 'education'
export type AssetClass = 'fixedIncome' | 'stock' | 'reit' | 'crypto'
export const ASSET_CLASSES: AssetClass[] = ['fixedIncome', 'stock', 'reit', 'crypto']
export const assetClassName: Record<AssetClass, string> = {
  fixedIncome: 'Renda fixa',
  stock: 'Ações',
  reit: 'FIIs',
  crypto: 'Cripto',
}
export type SplitMode = 'equal' | 'percentage'
export type ApprovalStatus = 'pending' | 'approved' | 'rejected'
export type InvoiceStatus = 'open' | 'closed' | 'paid' | 'overdue'

interface Base {
  id: UUID
  ownerId?: UUID
  createdAt: Date
  updatedAt: Date
}

export interface Account extends Base {
  name: string
  type: AccountType
  initialBalance: Dec
  currency: string
  isArchived: boolean
  visibility: Visibility
}
export interface Category extends Base {
  name: string
  kind: CategoryKind
  parentId?: UUID
  icon?: string
  colorHex?: string
  visibility: Visibility
  taxKind?: TaxDeductionKind
}
export interface Tag extends Base {
  name: string
}
export interface RecurrenceRule {
  frequency: RecurrenceFrequency
  interval: number
  endDate?: Date
  maxOccurrences?: number
}
export interface InstallmentInfo {
  number: number
  total: number
  groupId: UUID
}
export interface Transaction extends Base {
  type: TransactionType
  amount: Dec
  date: Date
  title: string
  status: TransactionStatus
  accountId?: UUID
  destinationAccountId?: UUID
  categoryId?: UUID
  tagIds: UUID[]
  creditCardId?: UUID
  invoiceId?: UUID
  installment?: InstallmentInfo
  recurrence?: RecurrenceRule
  recurrenceParentId?: UUID
  attachmentPath?: string
  note?: string
  externalId?: string
  memberId?: UUID
}
export interface CreditCard extends Base {
  name: string
  limit: Dec
  closingDay: number
  dueDay: number
  paymentAccountId?: UUID
  isArchived: boolean
}
export interface Invoice extends Base {
  cardId: UUID
  month: YearMonth
  closingDate: Date
  dueDate: Date
  paidAmount: Dec
  paidAt?: Date
  paymentAccountId?: UUID
}
export interface Budget extends Base {
  categoryId: UUID
  month: YearMonth
  limit: Dec
}
export interface Goal extends Base {
  name: string
  targetAmount: Dec
  currentAmount: Dec
  deadline?: Date
  memberId?: UUID
}
export interface Debt extends Base {
  name: string
  balance: Dec
  monthlyInterestRate: Dec
  minimumPayment: Dec
  dueDay?: number
}
export interface Household extends Base {
  name: string
}
export interface FamilyMember extends Base {
  householdId: UUID
  name: string
  role: MemberRole
  email?: string
  monthlySpendingLimit?: Dec
}
export interface GoalContribution extends Base {
  goalId: UUID
  amount: Dec
  date: Date
  accountId?: UUID
  transactionId?: UUID
  note?: string
}
export interface Investment extends Base {
  name: string
  ticker?: string
  assetClass: AssetClass
  quantity: Dec
  averagePrice: Dec
  quote?: Dec
  quoteDate?: Date
  realizedProfit: Dec
  memberId?: UUID
}
export interface NetWorthSnapshot extends Base {
  month: YearMonth
  assets: Dec
  liabilities: Dec
}
export interface SplitShare {
  memberId: UUID
  percent?: Dec
  amount: Dec
}
export interface ExpenseSplit extends Base {
  title: string
  total: Dec
  date: Date
  paidBy: UUID
  mode: SplitMode
  shares: SplitShare[]
  transactionId?: UUID
}
export interface SplitSettlement extends Base {
  fromMemberId: UUID
  toMemberId: UUID
  amount: Dec
  date: Date
}
export interface Allowance extends Base {
  memberId: UUID
  amount: Dec
  dayOfMonth: number
  fromAccountId: UUID
  toAccountId: UUID
  startMonth: YearMonth
  lastPaidMonth?: YearMonth
  isActive: boolean
}
export interface ApprovalRequest extends Base {
  memberId: UUID
  title: string
  amount: Dec
  date: Date
  accountId?: UUID
  categoryId?: UUID
  status: ApprovalStatus
  decidedBy?: UUID
  decidedAt?: Date
  transactionId?: UUID
}
export interface Tombstone extends Base {
  entityType: string
  entityId: UUID
  deletedAt: Date
}

/** Nome do tipo (igual ao nome da struct Swift) -> chave no snapshot. */
export interface EntityMap {
  Account: Account
  Category: Category
  Tag: Tag
  Transaction: Transaction
  CreditCard: CreditCard
  Invoice: Invoice
  Budget: Budget
  Goal: Goal
  Debt: Debt
  Household: Household
  FamilyMember: FamilyMember
  GoalContribution: GoalContribution
  Investment: Investment
  NetWorthSnapshot: NetWorthSnapshot
  ExpenseSplit: ExpenseSplit
  SplitSettlement: SplitSettlement
  Allowance: Allowance
  ApprovalRequest: ApprovalRequest
  Tombstone: Tombstone
}
export type EntityType = keyof EntityMap

export const COLLECTION: Record<EntityType, keyof Snapshot> = {
  Account: 'accounts',
  Category: 'categories',
  Tag: 'tags',
  Transaction: 'transactions',
  CreditCard: 'creditCards',
  Invoice: 'invoices',
  Budget: 'budgets',
  Goal: 'goals',
  Debt: 'debts',
  Household: 'households',
  FamilyMember: 'familyMembers',
  GoalContribution: 'goalContributions',
  Investment: 'investments',
  NetWorthSnapshot: 'netWorthSnapshots',
  ExpenseSplit: 'expenseSplits',
  SplitSettlement: 'splitSettlements',
  Allowance: 'allowances',
  ApprovalRequest: 'approvalRequests',
  Tombstone: 'tombstones',
}
export const ENTITY_TYPES = Object.keys(COLLECTION) as EntityType[]

export interface Snapshot {
  version: number
  accounts: Account[]
  categories: Category[]
  tags: Tag[]
  transactions: Transaction[]
  creditCards: CreditCard[]
  invoices: Invoice[]
  budgets: Budget[]
  goals: Goal[]
  debts: Debt[]
  households: Household[]
  familyMembers: FamilyMember[]
  goalContributions: GoalContribution[]
  investments: Investment[]
  netWorthSnapshots: NetWorthSnapshot[]
  expenseSplits: ExpenseSplit[]
  splitSettlements: SplitSettlement[]
  allowances: Allowance[]
  approvalRequests: ApprovalRequest[]
  tombstones: Tombstone[]
}

export function emptySnapshot(): Snapshot {
  return {
    version: 2,
    accounts: [], categories: [], tags: [], transactions: [], creditCards: [], invoices: [], budgets: [],
    goals: [], debts: [], households: [], familyMembers: [], goalContributions: [], investments: [],
    netWorthSnapshots: [], expenseSplits: [], splitSettlements: [], allowances: [], approvalRequests: [], tombstones: [],
  }
}

export const isCardPurchase = (t: Transaction): boolean => t.creditCardId !== undefined && t.invoiceId === undefined
export const isInvoicePayment = (t: Transaction): boolean => t.invoiceId !== undefined
export function signedAmount(t: Transaction): Dec {
  switch (t.type) {
    case 'income': return t.amount
    case 'expense': return t.amount.neg()
    default: return ZERO
  }
}

// ---- Fábricas (equivalentes aos inits do Swift) ----
type Init<T extends Base, Req extends keyof T> = Pick<T, Req> & Partial<Omit<T, Req>>
const stamp = (): Base => {
  const now = new Date()
  return { id: newId(), createdAt: now, updatedAt: now }
}
export const mkAccount = (p: Init<Account, 'name' | 'type'>): Account => ({
  ...stamp(), initialBalance: ZERO, currency: 'BRL', isArchived: false, visibility: 'shared', ...p,
})
export const mkCategory = (p: Init<Category, 'name' | 'kind'>): Category => ({ ...stamp(), visibility: 'shared', ...p })
export const mkTag = (p: Init<Tag, 'name'>): Tag => ({ ...stamp(), ...p })
export const mkTransaction = (p: Init<Transaction, 'type' | 'amount' | 'date' | 'title'>): Transaction => ({
  ...stamp(), status: 'paid', tagIds: [], ...p,
})
export const mkCard = (p: Init<CreditCard, 'name' | 'limit' | 'closingDay' | 'dueDay'>): CreditCard => ({
  ...stamp(), isArchived: false, ...p,
})
export const mkBudget = (p: Init<Budget, 'categoryId' | 'month' | 'limit'>): Budget => ({ ...stamp(), ...p })
export const mkGoal = (p: Init<Goal, 'name' | 'targetAmount'>): Goal => ({ ...stamp(), currentAmount: ZERO, ...p })
export const mkDebt = (p: Init<Debt, 'name' | 'balance' | 'monthlyInterestRate' | 'minimumPayment'>): Debt => ({ ...stamp(), ...p })
export const mkInvestment = (p: Init<Investment, 'name' | 'assetClass' | 'quantity' | 'averagePrice'>): Investment => ({
  ...stamp(), realizedProfit: ZERO, ...p,
})
export const mkMember = (p: Init<FamilyMember, 'householdId' | 'name'>): FamilyMember => ({ ...stamp(), role: 'member', ...p })
export const mkHousehold = (p: Init<Household, 'name'>): Household => ({ ...stamp(), ...p })
