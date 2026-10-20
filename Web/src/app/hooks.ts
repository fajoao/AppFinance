import { useEffect, useMemo, useState } from 'react'
import * as C from '../core'
import { Account, Category, CreditCard, FamilyMember, Invoice, Transaction, UUID, YearMonth } from '../core'
import { Lookup, makeLookup } from './logic'
import { useApp } from './store'

/** Hoje (dia civil); atualiza ao virar o dia. */
export function useToday(): Date {
  const [d, setD] = useState(() => C.todayCivil())
  useEffect(() => {
    const t = setInterval(() => { const n = C.todayCivil(); setD((o) => (C.isSameDay(o, n) ? o : n)) }, 60_000)
    return () => clearInterval(t)
  }, [])
  return d
}

export interface View {
  today: Date
  month: YearMonth
  accounts: Account[]          // visíveis, inclui arquivadas
  activeAccounts: Account[]    // visíveis e não arquivadas
  categories: Category[]
  tags: C.Tag[]
  cards: CreditCard[]
  activeCards: CreditCard[]
  invoices: Invoice[]
  transactions: Transaction[]  // visíveis na visão atual
  members: FamilyMember[]
  me?: FamilyMember
  hasFamily: boolean
  lookup: Lookup
  hide: boolean
  scope: C.FamilyScope
}

/** Dados da visão atual (Família × Individual) já com a regra de privacidade do Core aplicada. */
export function useView(): View {
  const data = useApp((s) => s.data)
  const settings = useApp((s) => s.settings)
  const month = useApp((s) => s.month)
  const today = useToday()
  return useMemo(() => {
    const members = data.familyMembers
    const hasFamily = members.length > 0
    const me = members.find((m) => m.id === settings.activeMemberId) ?? (hasFamily ? members.find((m) => m.role === 'admin') : undefined)
    const dependent = me?.role === 'dependent'
    const scope: C.FamilyScope = hasFamily && me && (settings.scope === 'individual' || dependent) ? { kind: 'member', id: me.id } : { kind: 'family' }
    let accounts = data.accounts, categories = data.categories, transactions = data.transactions
    if (hasFamily) {
      accounts = C.visibleAccounts(data.accounts, me?.id, scope)
      categories = C.visibleCategories(data.categories, me?.id)
      transactions = C.visibleTransactions(data.transactions, data.accounts, data.categories, me?.id, scope)
    }
    const cards = data.creditCards
    return {
      today, month, accounts, activeAccounts: accounts.filter((a) => !a.isArchived), categories, tags: data.tags, cards,
      activeCards: cards.filter((c) => !c.isArchived), invoices: data.invoices, transactions, members, me, hasFamily, scope,
      lookup: makeLookup({ accounts, categories, tags: data.tags, cards, members }), hide: settings.hideValues,
    }
  }, [data, settings.activeMemberId, settings.scope, settings.hideValues, month, today])
}

export function useById<T extends { id: UUID }>(list: T[]): Map<UUID, T> {
  return useMemo(() => new Map(list.map((x) => [x.id, x])), [list])
}
