import Foundation

/// Dados de demonstração (launch argument `-seedDemo`): espelham o protótipo (`Prototype/index.html`).
/// Os saldos finais das contas são ajustados via `initialBalance` usando o BalanceEngine do Core.
enum DemoSeed {
    static func make(today: Date) -> FinanceSnapshot {
        var snap = FinanceSnapshot()
        let ym = YearMonth(today)
        let todayDay = FinanceCalendar.components(today).day
        /// Dia `d` do mês corrente, nunca no futuro (meses curtos/início de mês colapsam em hoje).
        func cur(_ d: Int) -> Date { ym.date(day: min(d, todayDay)) }
        func prev(_ d: Int) -> Date { ym.previous.date(day: d) }
        func next(_ d: Int) -> Date { ym.next.date(day: d) }
        func later(_ d: Int) -> Date { d >= todayDay ? ym.date(day: d) : ym.next.date(day: d) }

        // Categorias
        let cats = DefaultCategories.make()
        snap.categories = cats
        func cat(_ name: String, _ kind: CategoryKind = .expense) -> UUID { cats.first { $0.name == name && $0.kind == kind }!.id }

        // Tags
        let tagNames = ["família", "casa", "amigos", "trabalho", "viagem"]
        snap.tags = tagNames.map { Tag(name: $0) }
        func tag(_ n: String) -> UUID { snap.tags.first { $0.name == n }!.id }

        // Contas (saldo final alvo; initialBalance ajustado no fim)
        var nubank = Account(name: "Nubank", type: .checking)
        var itau = Account(name: "Itaú", type: .checking)
        var poup = Account(name: "Poupança Caixa", type: .savings)
        var carteira = Account(name: "Dinheiro", type: .wallet)
        var tesouro = Account(name: "Tesouro Selic 2029", type: .investment)
        let targets: [UUID: Decimal] = [nubank.id: dec("4812.37"), itau.id: dec("1240.90"), poup.id: dec("12850.00"),
                                        carteira.id: dec("86.50"), tesouro.id: dec("18420.15")]

        // Cartões
        let cnu = CreditCard(name: "Nubank Mastercard", limit: 8000, closingDay: 3, dueDay: 10, paymentAccountId: nubank.id)
        let citau = CreditCard(name: "Itaú Visa Platinum", limit: 6000, closingDay: 25, dueDay: 5, paymentAccountId: itau.id)
        snap.creditCards = [cnu, citau]

        var txs: [Transaction] = []
        func add(_ type: TransactionType, _ title: String, _ amount: String, _ date: Date, category: UUID? = nil,
                 account: UUID? = nil, card: CreditCard? = nil, tags: [String] = [], status: TransactionStatus = .paid,
                 recurring: RecurrenceFrequency? = nil, installment: (Int, Int)? = nil, to: UUID? = nil) {
            var t = Transaction(type: type, amount: dec(amount), date: date, title: title, status: status,
                                accountId: card == nil ? account : nil, destinationAccountId: to, categoryId: category,
                                tagIds: tags.map(tag), creditCardId: card?.id)
            if let recurring { t.recurrence = RecurrenceRule(frequency: recurring) }
            if let installment {
                t.installment = InstallmentInfo(number: installment.0, total: installment.1, groupId: UUID())
                t.title = "\(title) (\(installment.0)/\(installment.1))"
            }
            txs.append(t)
        }

        // Mês anterior (para comparação)
        add(.income, "Salário", "7850.00", prev(5), category: cat("Salário", .income), account: nubank.id)
        add(.income, "Rendimento da poupança", "64.22", prev(1), category: cat("Rendimentos", .income), account: poup.id)
        add(.expense, "Aluguel", "1850.00", prev(5), category: cat("Moradia"), account: itau.id)
        add(.expense, "Condomínio", "420.00", prev(10), category: cat("Moradia"), account: itau.id)
        add(.expense, "Escola de inglês", "690.00", prev(10), category: cat("Educação"), account: itau.id)
        add(.expense, "Supermercado", "980.00", prev(12), category: cat("Mercado"), account: nubank.id)
        add(.expense, "Uber", "300.00", prev(14), category: cat("Transporte"), account: nubank.id)
        add(.expense, "Cinema", "150.00", prev(20), category: cat("Lazer"), account: nubank.id)
        add(.expense, "Farmácia", "98.00", prev(22), category: cat("Saúde"), account: nubank.id)
        // Faturas do ciclo anterior (pagas no mês corrente)
        add(.expense, "Compras do mês", "1104.77", prev(12), category: cat("Mercado"), card: cnu)
        add(.expense, "Restaurante", "1000.00", prev(25), category: cat("Lazer"), card: cnu)
        add(.expense, "Combustível", "630.22", prev(10), category: cat("Transporte"), card: citau)
        add(.expense, "Compras diversas", "1000.00", prev(18), category: cat("Outros"), card: citau)

        // Mês corrente
        add(.income, "Rendimento da poupança", "64.22", cur(1), category: cat("Rendimentos", .income), account: poup.id)
        add(.expense, "Presente da Bia", "120.00", cur(2), category: cat("Outros"), account: nubank.id, tags: ["família"])
        add(.expense, "Posto Shell", "220.00", cur(3), category: cat("Transporte"), card: citau)
        add(.expense, "Carrefour", "612.40", cur(4), category: cat("Mercado"), card: cnu)
        add(.income, "Salário", "7850.00", cur(5), category: cat("Salário", .income), account: nubank.id, recurring: .monthly)
        add(.expense, "Aluguel", "1850.00", cur(5), category: cat("Moradia"), account: itau.id, recurring: .monthly)
        add(.expense, "Netflix", "44.90", cur(6), category: cat("Lazer"), card: cnu, recurring: .monthly)
        add(.expense, "Spotify Família", "34.90", cur(6), category: cat("Lazer"), card: citau, recurring: .monthly)
        add(.transfer, "Reserva do mês", "500.00", cur(6), account: nubank.id, to: poup.id)
        add(.expense, "Geladeira Brastemp", "389.90", cur(7), category: cat("Outros"), card: cnu, tags: ["casa"], installment: (3, 10))
        add(.expense, "Drogasil", "76.35", cur(8), category: cat("Saúde"), card: cnu)
        add(.expense, "Uber", "32.80", cur(9), category: cat("Transporte"), card: cnu)
        add(.expense, "Condomínio", "420.00", cur(10), category: cat("Moradia"), account: itau.id, recurring: .monthly)
        add(.expense, "Escola de inglês", "690.00", cur(10), category: cat("Educação"), account: itau.id, recurring: .monthly)
        add(.expense, "Pão de Açúcar", "288.90", cur(11), category: cat("Mercado"), card: citau)
        add(.expense, "iFood", "89.90", cur(12), category: cat("Mercado"), card: cnu)
        add(.expense, "Cinema Kinoplex", "96.00", cur(12), category: cat("Lazer"), card: cnu, tags: ["família"])
        add(.expense, "Recarga do metrô", "50.00", cur(13), category: cat("Transporte"), account: nubank.id)
        add(.income, "Freelance Studio Ipê", "1200.00", cur(14), category: cat("Freelance", .income), account: nubank.id, tags: ["trabalho"])
        add(.expense, "Consulta dermatologista", "250.00", cur(14), category: cat("Saúde"), account: nubank.id)
        add(.expense, "Livros Amazon", "43.30", cur(15), category: cat("Educação"), card: citau, installment: (1, 3))
        add(.expense, "Feira livre", "74.00", cur(16), category: cat("Mercado"), account: carteira.id)
        add(.expense, "Uber", "27.40", cur(17), category: cat("Transporte"), card: cnu)
        add(.expense, "Bar do Zé", "182.50", cur(18), category: cat("Lazer"), card: citau, tags: ["amigos"])
        add(.expense, "Padaria Real", "23.50", cur(18), category: cat("Mercado"), account: carteira.id)
        add(.expense, "Assaí Atacadista", "418.30", cur(19), category: cat("Mercado"), card: cnu)

        // Contas a pagar/receber (pendentes)
        add(.expense, "Energia (Enel)", "189.40", cur(15), category: cat("Moradia"), account: itau.id, status: .pending)
        add(.expense, "Internet Vivo Fibra", "119.99", later(20), category: cat("Moradia"), account: itau.id, status: .pending)
        add(.expense, "IPTU, parcela 9 de 10", "212.35", later(28), category: cat("Moradia"), account: itau.id, status: .pending)
        add(.income, "Studio Ipê (freelance)", "1800.00", later(30), category: cat("Freelance", .income), account: nubank.id, status: .pending)
        add(.expense, "Seguro do carro", "248.00", next(12), category: cat("Transporte"), account: itau.id, status: .pending)

        // Pagamento das faturas anteriores via Core (cria Invoice + transferência sem destino)
        var invoices: [Invoice] = []
        for (card, payDay) in [(cnu, 10), (citau, 5)] {
            let month = CreditCardEngine.invoiceMonth(forPurchaseOn: prev(15), card: card)
            let s = CreditCardEngine.summary(card: card, month: month, transactions: txs, asOf: cur(payDay))
            if s.total > 0, let accountId = card.paymentAccountId,
               let result = try? CreditCardEngine.pay(s, card: card, from: accountId, on: cur(payDay)) {
                invoices.append(result.invoice)
                txs.append(result.payment)
            }
        }

        // Ajusta saldos iniciais para os alvos
        for (index, acc) in [nubank, itau, poup, carteira, tesouro].enumerated() {
            var a = acc
            let current = BalanceEngine.balance(of: a, transactions: txs)
            a.initialBalance += (targets[a.id] ?? 0) - current
            switch index { case 0: nubank = a; case 1: itau = a; case 2: poup = a; case 3: carteira = a; default: tesouro = a }
        }
        snap.accounts = [nubank, itau, poup, carteira, tesouro]
        snap.transactions = txs
        snap.invoices = invoices

        // Orçamentos
        let limits: [(String, String)] = [("Moradia", "2400"), ("Mercado", "1500"), ("Transporte", "600"), ("Lazer", "420"),
                                          ("Saúde", "500"), ("Educação", "1000"), ("Outros", "800")]
        snap.budgets = limits.map { Budget(categoryId: cat($0.0), month: ym, limit: dec($0.1)) }

        // Metas
        snap.goals = [
            Goal(name: "Reserva de emergência", targetAmount: 30000, currentAmount: 18000, deadline: FinanceCalendar.date(ym.year + 1, 12, 31)),
            Goal(name: "Viagem à Chapada dos Veadeiros", targetAmount: 6000, currentAmount: 3200, deadline: FinanceCalendar.addMonths(ym.date(day: 28), 9)),
            Goal(name: "Notebook novo", targetAmount: 7500, currentAmount: 2100, deadline: FinanceCalendar.addMonths(ym.date(day: 28), 5)),
        ]

        // Fase 2: dívidas, carteira de investimentos e histórico de aportes
        snap.debts = [
            Debt(name: "Cartão rotativo Itaú", balance: 6500, monthlyInterestRate: dec("0.1450"), minimumPayment: 650, dueDay: 5),
            Debt(name: "Empréstimo pessoal", balance: 8000, monthlyInterestRate: dec("0.0320"), minimumPayment: 420, dueDay: 15),
            Debt(name: "Financiamento do notebook", balance: 3100, monthlyInterestRate: dec("0.0189"), minimumPayment: 310, dueDay: 20),
        ]
        func inv(_ name: String, _ ticker: String?, _ cls: AssetClass, _ qty: String, _ avg: String, _ quote: String?) -> Investment {
            Investment(name: name, ticker: ticker, assetClass: cls, quantity: dec(qty), averagePrice: dec(avg),
                       quote: quote.map(dec), quoteDate: quote == nil ? nil : cur(1))
        }
        snap.investments = [
            inv("CDB Banco Inter 110% CDI", nil, .fixedIncome, "1", "5000.00", "5230.40"),
            inv("Petrobras", "PETR4", .stock, "100", "32.40", "36.10"),
            inv("Maxi Renda", "MXRF11", .reit, "200", "10.05", "10.31"),
            inv("Bitcoin", "BTC", .crypto, "0.0042", "310000.00", "335000.00"),
        ]
        var history: [GoalContribution] = []
        for g in snap.goals {
            for back in 0..<3 {
                let amount: Decimal = g.name.hasPrefix("Reserva") ? 1000 : (g.name.hasPrefix("Viagem") ? 400 : 350)
                history.append(GoalContribution(goalId: g.id, amount: amount, date: ym.adding(months: -back).date(day: min(8, todayDay + (back == 0 ? 0 : 8))),
                                                note: nil))
            }
        }
        snap.goalContributions = history
        return snap
    }

    /// Demonstração do grupo familiar (launch argument `-seedFamily`): Ana (admin), Bruno (membro) e Caio (dependente,
    /// limite de R$ 150), conta privada, conta do filho, mesada, divisão de despesa e meta de filho.
    static func makeFamily(today: Date) -> FinanceSnapshot {
        var snap = make(today: today)
        let ym = YearMonth(today)
        let (house, ana) = FamilyEngine.createHousehold(name: "Família Silva", adminName: "Ana", email: "ana@example.com")
        let bruno = FamilyMember(householdId: house.id, name: "Bruno", role: .member)
        let caio = FamilyMember(householdId: house.id, name: "Caio", role: .dependent, monthlySpendingLimit: 150)
        snap.households = [house]
        snap.familyMembers = [ana, bruno, caio]

        // atribui lançamentos aos membros (alternando) e define o dono das contas
        for i in snap.transactions.indices where snap.transactions[i].type == .expense && !snap.transactions[i].isInvoicePayment {
            snap.transactions[i].memberId = i % 3 == 0 ? bruno.id : ana.id
        }
        for i in snap.accounts.indices { snap.accounts[i].ownerId = ana.id }
        let kidAccount = Account(name: "Conta do Caio", type: .wallet, initialBalance: 200, visibility: .shared, ownerId: caio.id)
        let privateAccount = Account(name: "Reserva da Ana", type: .savings, initialBalance: 2300, visibility: .personal, ownerId: ana.id)
        snap.accounts += [kidAccount, privateAccount]

        // mesada (já paga neste mês) e lançamento do filho
        let nubank = snap.accounts[0]
        let allowance = Allowance(memberId: caio.id, amount: 80, dayOfMonth: 5, fromAccountId: nubank.id, toAccountId: kidAccount.id,
                                  startMonth: ym.previous, lastPaidMonth: ym.previous)
        snap.allowances = [allowance]
        var snack = Transaction(type: .expense, amount: 45, date: ym.date(day: min(8, FinanceCalendar.components(today).day)),
                                title: "Lanche da escola", status: .paid, accountId: kidAccount.id)
        snack.memberId = caio.id
        snap.transactions.append(snack)

        // divisão de despesas: Ana pagou o jantar, Bruno deve a parte dele
        if let split = try? SplitEngine.make(title: "Jantar de aniversário", total: 320, date: ym.date(day: min(12, FinanceCalendar.components(today).day)),
                                              paidBy: ana.id, participants: [ana.id, bruno.id, caio.id], mode: .equal) {
            snap.expenseSplits = [split]
        }
        // meta de filho e pedido de aprovação pendente
        snap.goals.append(Goal(name: "Bicicleta do Caio", targetAmount: 900, currentAmount: 260,
                               deadline: FinanceCalendar.addMonths(ym.date(day: 28), 6), memberId: caio.id))
        snap.approvalRequests = [ApprovalRequest(memberId: caio.id, title: "Jogo de videogame", amount: dec("199.90"),
                                                 date: ym.date(day: min(15, FinanceCalendar.components(today).day)), accountId: kidAccount.id)]
        return snap
    }
}
