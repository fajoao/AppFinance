// Dados de exemplo (equivalente ao DemoSeed do app iOS). Saldos finais ajustados via initialBalance usando o Core.
import * as C from '../core'
import { Snapshot, Transaction, TransactionType, UUID, dec, emptySnapshot } from '../core'
import { makeDefaultCategories } from './logic'

export function makeDemoSnapshot(today: Date): Snapshot {
  const snap = emptySnapshot()
  const ym = C.ymOf(today)
  const todayDay = C.components(today).day
  const cur = (d: number) => C.ymDate(ym, Math.min(d, todayDay))
  const prev = (d: number) => C.ymDate(C.ymPrev(ym), d)
  const next = (d: number) => C.ymDate(C.ymNext(ym), d)
  const later = (d: number) => (d >= todayDay ? C.ymDate(ym, d) : C.ymDate(C.ymNext(ym), d))

  const cats = makeDefaultCategories()
  snap.categories = cats
  const cat = (name: string, kind: 'income' | 'expense' = 'expense'): UUID => cats.find((c) => c.name === name && c.kind === kind)!.id
  snap.tags = ['família', 'casa', 'amigos', 'trabalho', 'viagem'].map((name) => C.mkTag({ name }))
  const tag = (n: string): UUID => snap.tags.find((t) => t.name === n)!.id

  const accNames: [string, C.AccountType, string][] = [
    ['Nubank', 'checking', '4812.37'], ['Itaú', 'checking', '1240.90'], ['Poupança Caixa', 'savings', '12850.00'],
    ['Dinheiro', 'wallet', '86.50'], ['Tesouro Selic 2029', 'investment', '18420.15'],
  ]
  const accounts = accNames.map(([name, type]) => C.mkAccount({ name, type }))
  const [nubank, itau, poup, carteira] = accounts as [C.Account, C.Account, C.Account, C.Account, C.Account]
  const cnu = C.mkCard({ name: 'Nubank Mastercard', limit: dec(8000), closingDay: 3, dueDay: 10, paymentAccountId: nubank.id })
  const citau = C.mkCard({ name: 'Itaú Visa Platinum', limit: dec(6000), closingDay: 25, dueDay: 5, paymentAccountId: itau.id })
  snap.creditCards = [cnu, citau]

  const txs: Transaction[] = []
  const add = (
    type: TransactionType, title: string, amount: string, date: Date,
    o: { category?: UUID; account?: UUID; card?: C.CreditCard; tags?: string[]; status?: 'paid' | 'pending'; recurring?: 'monthly'; installment?: [number, number]; to?: UUID } = {},
  ) => {
    const t = C.mkTransaction({
      type, amount: dec(amount), date, title, status: o.status ?? 'paid', accountId: o.card ? undefined : o.account, destinationAccountId: o.to,
      categoryId: o.category, tagIds: (o.tags ?? []).map(tag), creditCardId: o.card?.id,
    })
    if (o.recurring) t.recurrence = { frequency: 'monthly', interval: 1 }
    if (o.installment) { t.installment = { number: o.installment[0], total: o.installment[1], groupId: C.newId() }; t.title = `${title} (${o.installment[0]}/${o.installment[1]})` }
    txs.push(t)
  }
  const inc = (n: string) => cat(n, 'income')

  add('income', 'Salário', '7850.00', prev(5), { category: inc('Salário'), account: nubank.id })
  add('income', 'Rendimento da poupança', '64.22', prev(1), { category: inc('Rendimentos'), account: poup.id })
  add('expense', 'Aluguel', '1850.00', prev(5), { category: cat('Moradia'), account: itau.id })
  add('expense', 'Condomínio', '420.00', prev(10), { category: cat('Moradia'), account: itau.id })
  add('expense', 'Escola de inglês', '690.00', prev(10), { category: cat('Educação'), account: itau.id })
  add('expense', 'Supermercado', '980.00', prev(12), { category: cat('Mercado'), account: nubank.id })
  add('expense', 'Uber', '300.00', prev(14), { category: cat('Transporte'), account: nubank.id })
  add('expense', 'Cinema', '150.00', prev(20), { category: cat('Lazer'), account: nubank.id })
  add('expense', 'Farmácia', '98.00', prev(22), { category: cat('Saúde'), account: nubank.id })
  add('expense', 'Compras do mês', '1104.77', prev(12), { category: cat('Mercado'), card: cnu })
  add('expense', 'Restaurante', '1000.00', prev(25), { category: cat('Lazer'), card: cnu })
  add('expense', 'Combustível', '630.22', prev(10), { category: cat('Transporte'), card: citau })
  add('expense', 'Compras diversas', '1000.00', prev(18), { category: cat('Outros'), card: citau })

  add('income', 'Rendimento da poupança', '64.22', cur(1), { category: inc('Rendimentos'), account: poup.id })
  add('expense', 'Presente da Bia', '120.00', cur(2), { category: cat('Outros'), account: nubank.id, tags: ['família'] })
  add('expense', 'Posto Shell', '220.00', cur(3), { category: cat('Transporte'), card: citau })
  add('expense', 'Carrefour', '612.40', cur(4), { category: cat('Mercado'), card: cnu })
  add('income', 'Salário', '7850.00', cur(5), { category: inc('Salário'), account: nubank.id, recurring: 'monthly' })
  add('expense', 'Aluguel', '1850.00', cur(5), { category: cat('Moradia'), account: itau.id, recurring: 'monthly' })
  add('expense', 'Netflix', '44.90', cur(6), { category: cat('Lazer'), card: cnu, recurring: 'monthly' })
  add('expense', 'Spotify Família', '34.90', cur(6), { category: cat('Lazer'), card: citau, recurring: 'monthly' })
  add('transfer', 'Reserva do mês', '500.00', cur(6), { account: nubank.id, to: poup.id })
  add('expense', 'Geladeira Brastemp', '389.90', cur(7), { category: cat('Outros'), card: cnu, tags: ['casa'], installment: [3, 10] })
  add('expense', 'Drogasil', '76.35', cur(8), { category: cat('Saúde'), card: cnu })
  add('expense', 'Uber', '32.80', cur(9), { category: cat('Transporte'), card: cnu })
  add('expense', 'Condomínio', '420.00', cur(10), { category: cat('Moradia'), account: itau.id, recurring: 'monthly' })
  add('expense', 'Escola de inglês', '690.00', cur(10), { category: cat('Educação'), account: itau.id, recurring: 'monthly' })
  add('expense', 'Pão de Açúcar', '288.90', cur(11), { category: cat('Mercado'), card: citau })
  add('expense', 'iFood', '89.90', cur(12), { category: cat('Mercado'), card: cnu })
  add('expense', 'Cinema Kinoplex', '96.00', cur(12), { category: cat('Lazer'), card: cnu, tags: ['família'] })
  add('expense', 'Recarga do metrô', '50.00', cur(13), { category: cat('Transporte'), account: nubank.id })
  add('income', 'Freelance Studio Ipê', '1200.00', cur(14), { category: inc('Freelance'), account: nubank.id, tags: ['trabalho'] })
  add('expense', 'Consulta dermatologista', '250.00', cur(14), { category: cat('Saúde'), account: nubank.id })
  add('expense', 'Livros Amazon', '43.30', cur(15), { category: cat('Educação'), card: citau, installment: [1, 3] })
  add('expense', 'Feira livre', '74.00', cur(16), { category: cat('Mercado'), account: carteira.id })
  add('expense', 'Uber', '27.40', cur(17), { category: cat('Transporte'), card: cnu })
  add('expense', 'Bar do Zé', '182.50', cur(18), { category: cat('Lazer'), card: citau, tags: ['amigos'] })
  add('expense', 'Padaria Real', '23.50', cur(18), { category: cat('Mercado'), account: carteira.id })
  add('expense', 'Assaí Atacadista', '418.30', cur(19), { category: cat('Mercado'), card: cnu })

  add('expense', 'Energia (Enel)', '189.40', cur(15), { category: cat('Moradia'), account: itau.id, status: 'pending' })
  add('expense', 'Internet Vivo Fibra', '119.99', later(20), { category: cat('Moradia'), account: itau.id, status: 'pending' })
  add('expense', 'IPTU, parcela 9 de 10', '212.35', later(28), { category: cat('Moradia'), account: itau.id, status: 'pending' })
  add('income', 'Studio Ipê (freelance)', '1800.00', later(30), { category: inc('Freelance'), account: nubank.id, status: 'pending' })
  add('expense', 'Seguro do carro', '248.00', next(12), { category: cat('Transporte'), account: itau.id, status: 'pending' })

  // Pagamento das faturas anteriores via Core
  const invoices: C.Invoice[] = []
  for (const [card, payDay] of [[cnu, 10], [citau, 5]] as [C.CreditCard, number][]) {
    const month = C.invoiceMonthFor(prev(15), card)
    const s = C.summary(card, month, txs, [], cur(payDay))
    if (s.total.gt(0) && card.paymentAccountId) {
      const r = C.payInvoice(s, card, undefined, card.paymentAccountId, cur(payDay))
      invoices.push(r.invoice)
      txs.push(r.payment)
    }
  }
  accounts.forEach((a, i) => {
    const current = C.balanceOf(a, txs)
    a.initialBalance = a.initialBalance.plus(dec(accNames[i]![2]).minus(current))
  })
  snap.accounts = accounts
  snap.transactions = txs
  snap.invoices = invoices

  const limits: [string, string][] = [['Moradia', '2400'], ['Mercado', '1500'], ['Transporte', '600'], ['Lazer', '420'], ['Saúde', '500'], ['Educação', '1000'], ['Outros', '800']]
  snap.budgets = limits.map(([n, l]) => C.mkBudget({ categoryId: cat(n), month: ym, limit: dec(l) }))
  snap.goals = [
    C.mkGoal({ name: 'Reserva de emergência', targetAmount: dec(30000), currentAmount: dec(18000), deadline: C.civil(ym.year + 1, 12, 31) }),
    C.mkGoal({ name: 'Viagem à Chapada dos Veadeiros', targetAmount: dec(6000), currentAmount: dec(3200), deadline: C.addMonths(C.ymDate(ym, 28), 9) }),
    C.mkGoal({ name: 'Notebook novo', targetAmount: dec(7500), currentAmount: dec(2100), deadline: C.addMonths(C.ymDate(ym, 28), 5) }),
  ]
  snap.debts = [
    C.mkDebt({ name: 'Cartão rotativo', balance: dec('3200'), monthlyInterestRate: dec('0.1299'), minimumPayment: dec('320'), dueDay: 10 }),
    C.mkDebt({ name: 'Empréstimo pessoal', balance: dec('8400'), monthlyInterestRate: dec('0.0299'), minimumPayment: dec('450'), dueDay: 15 }),
    C.mkDebt({ name: 'Financiamento notebook', balance: dec('1500'), monthlyInterestRate: dec('0.0199'), minimumPayment: dec('150'), dueDay: 20 }),
  ]
  snap.investments = [
    C.mkInvestment({ name: 'Tesouro Selic 2029', assetClass: 'fixedIncome', quantity: dec(1), averagePrice: dec('17500'), quote: dec('18420.15') }),
    C.mkInvestment({ name: 'Petrobras PN', ticker: 'PETR4', assetClass: 'stock', quantity: dec(100), averagePrice: dec('30.5'), quote: dec('35.25') }),
    C.mkInvestment({ name: 'Fundo logístico', ticker: 'HGLG11', assetClass: 'reit', quantity: dec(12), averagePrice: dec('160.33'), quote: dec('158.4') }),
  ]
  return snap
}
