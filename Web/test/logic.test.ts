import { describe, expect, it } from 'vitest'
import * as C from '../src/core'
import { buildTransactions, newDraft, billStatus, validateDraft, DraftFailure } from '../src/app/logic'
import { fmtMoney, spokenMoney, MINUS } from '../src/app/format'
import { makeDemoSnapshot } from '../src/app/seed'

const today = C.civil(2026, 10, 20)
describe('rascunho de lançamento', () => {
  it('valor zero é inválido', () => {
    expect(validateDraft(newDraft(today))).toBe('zeroAmount')
  })
  it('parcelado em cartão usa o Core: 100,01 em 10x', () => {
    const card = C.mkCard({ name: 'X', limit: C.dec(5000), closingDay: 5, dueDay: 12 })
    const d = { ...newDraft(today), amount: C.dec('100.01'), source: { kind: 'card' as const, id: card.id }, repeat: 'installments' as const, installments: 10 }
    const list = buildTransactions(d, [card], today)
    expect(list).toHaveLength(10)
    expect(C.sum(list.map((t) => t.amount)).toString()).toBe('100.01')
    expect(list[9]!.amount.toString()).toBe('10.01')
  })
  it('data futura vira pendente e transferência exige destinos diferentes', () => {
    const a = C.mkAccount({ name: 'A', type: 'checking' })
    const d = { ...newDraft(C.civil(2026, 11, 1), 'expense', a.id), amount: C.dec(10) }
    expect(buildTransactions(d, [], today)[0]!.status).toBe('pending')
    expect(() => buildTransactions({ ...d, type: 'transfer', destinationAccountId: a.id }, [], today)).toThrow(DraftFailure)
  })
  it('recorrência mensal no dia 31 não deriva', () => {
    const a = C.mkAccount({ name: 'A', type: 'checking' })
    const [t] = buildTransactions({ ...newDraft(C.civil(2026, 1, 31), 'expense', a.id), amount: C.dec(1), repeat: 'monthly' }, [], today)
    const occ = C.generateRecurrences(t!, C.civil(2026, 1, 1), C.civil(2026, 4, 30)).map((x) => C.isoDay(x.date))
    expect(occ).toEqual(['2026-02-28', '2026-03-31', '2026-04-30'])
  })
})
describe('formatação', () => {
  it('menos tipográfico e espaço inseparável', () => {
    expect(fmtMoney(C.dec('-45.9'))).toBe(`${MINUS}R$ 45,90`)
    expect(fmtMoney(C.dec('1234.5'), { sign: 'plus' })).toBe('+R$ 1.234,50')
    expect(fmtMoney(C.dec(1), { hide: true })).toBe('R$ ••••')
  })
  it('leitura por extenso', () => {
    expect(spokenMoney(C.dec('-45.90'))).toBe('menos quarenta e cinco reais e noventa centavos')
    expect(spokenMoney(C.dec('1'))).toBe('um real')
    expect(spokenMoney(C.dec('1000.01'))).toBe('mil reais e um centavo')
    expect(spokenMoney(C.dec('5'), true)).toBe('valor oculto')
  })
})
describe('contas a pagar', () => {
  it('status por proximidade', () => {
    const b = (days: number) => ({ id: 'x', title: 't', amount: C.dec(1), dueDate: C.addDays(today, days), direction: 'payable' as const, isPaid: false })
    expect(billStatus(b(0), today).label).toBe('Vence hoje')
    expect(billStatus(b(2), today).label).toBe('Vence em 2 dias')
    expect(billStatus(b(10), today).label).toBe('Pendente')
    expect(billStatus(b(-3), today).label).toBe('Atrasado 3 dias')
  })
})
describe('dados de exemplo', () => {
  it('saldos finais batem com os alvos', () => {
    const s = makeDemoSnapshot(today)
    const nub = s.accounts.find((a) => a.name === 'Nubank')!
    expect(C.balanceOf(nub, s.transactions).toString()).toBe('4812.37')
  })
})
