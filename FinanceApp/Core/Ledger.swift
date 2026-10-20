import Foundation

enum FinanceError: Error, Equatable, CustomStringConvertible {
    case invalidAmount
    case sameAccount
    case invalidInstallmentCount
    case invalidDay
    case overpayment
    case budgetBelowMinimums(required: Decimal)
    case malformedFile(String)
    case notFound
    case invalidQuantity
    case insufficientQuantity
    case invalidPercentages
    case noParticipants
    case permissionDenied
    case lastAdmin
    case invalidState(String)

    var description: String {
        switch self {
        case .invalidAmount: return "Valor inválido"
        case .sameAccount: return "Origem e destino devem ser contas diferentes"
        case .invalidInstallmentCount: return "Número de parcelas inválido"
        case .invalidDay: return "Dia inválido"
        case .overpayment: return "Pagamento maior que o saldo da fatura"
        case .budgetBelowMinimums(let r): return "Orçamento abaixo dos pagamentos mínimos (\(Money.format(r)))"
        case .malformedFile(let m): return "Arquivo inválido: \(m)"
        case .notFound: return "Registro não encontrado"
        case .invalidQuantity: return "Quantidade inválida"
        case .insufficientQuantity: return "Quantidade maior que a posição"
        case .invalidPercentages: return "Os percentuais devem somar 100%"
        case .noParticipants: return "Escolha ao menos um participante"
        case .permissionDenied: return "Seu papel na família não permite esta ação"
        case .lastAdmin: return "A família precisa ter ao menos um administrador"
        case .invalidState(let m): return m
        }
    }
}

enum BalanceEngine {
    /// Efeito de um lançamento no saldo da conta (0 se não afeta). Compras de cartão não afetam contas.
    static func effect(of tx: Transaction, on accountId: UUID) -> Decimal {
        if tx.isCardPurchase { return 0 }
        switch tx.type {
        case .income:
            return tx.accountId == accountId ? tx.amount : 0
        case .expense:
            return tx.accountId == accountId ? -tx.amount : 0
        case .transfer:
            var v: Decimal = 0
            if tx.accountId == accountId { v -= tx.amount }
            if tx.destinationAccountId == accountId { v += tx.amount }
            return v
        }
    }

    /// Saldo = saldo inicial + efeito dos lançamentos pagos (e pendentes se `includePending`) até `asOf` (inclusive).
    static func balance(of account: Account, transactions: [Transaction], asOf: Date? = nil, includePending: Bool = false) -> Decimal {
        var total = account.initialBalance
        for tx in transactions {
            if !includePending && tx.status != .paid { continue }
            if let asOf, FinanceCalendar.startOfDay(tx.date) > FinanceCalendar.startOfDay(asOf) { continue }
            total += effect(of: tx, on: account.id)
        }
        return total
    }

    /// Soma dos saldos das contas não arquivadas (opcionalmente filtrando tipos).
    static func totalBalance(accounts: [Account], transactions: [Transaction], asOf: Date? = nil,
                             includePending: Bool = false, types: Set<AccountType>? = nil) -> Decimal {
        accounts.filter { !$0.isArchived && (types?.contains($0.type) ?? true) }
            .reduce(0) { $0 + balance(of: $1, transactions: transactions, asOf: asOf, includePending: includePending) }
    }

    /// Cria a transferência entre contas. O total do patrimônio permanece o mesmo.
    static func makeTransfer(from: UUID, to: UUID, amount: Decimal, date: Date, title: String = "Transferência",
                             status: TransactionStatus = .paid) throws -> Transaction {
        guard from != to else { throw FinanceError.sameAccount }
        guard amount > 0 else { throw FinanceError.invalidAmount }
        return Transaction(type: .transfer, amount: amount, date: date, title: title, status: status,
                           accountId: from, destinationAccountId: to)
    }

    /// Diferença entre o saldo informado no extrato e o saldo calculado (positivo = faltam entradas no app).
    static func reconciliationDifference(account: Account, statementBalance: Decimal, transactions: [Transaction], asOf: Date? = nil) -> Decimal {
        statementBalance - balance(of: account, transactions: transactions, asOf: asOf)
    }

    /// Lançamento de ajuste que zera a diferença de conciliação (nil se já conciliado).
    static func reconciliationAdjustment(account: Account, statementBalance: Decimal, transactions: [Transaction], date: Date) -> Transaction? {
        let diff = reconciliationDifference(account: account, statementBalance: statementBalance, transactions: transactions, asOf: date)
        if diff == 0 { return nil }
        return Transaction(type: diff > 0 ? .income : .expense, amount: diff.magnitude, date: date,
                           title: "Ajuste de conciliação", status: .paid, accountId: account.id)
    }
}

// MARK: - Parcelamento

enum InstallmentEngine {
    /// Divide o total em parcelas; a última absorve o resto de centavos.
    static func split(total: Decimal, count: Int) throws -> [Decimal] {
        guard count >= 1 else { throw FinanceError.invalidInstallmentCount }
        return Money.split(total, into: count)
    }

    /// Gera as N parcelas a partir de um lançamento modelo (`amount` = total). Datas mensais a partir da data base
    /// (dia 31 vira último dia do mês, sem "deriva"). Títulos recebem " (x/y)".
    static func makeInstallments(from template: Transaction, count: Int) throws -> [Transaction] {
        let parts = try split(total: template.amount, count: count)
        let group = UUID()
        return parts.enumerated().map { (i, value) in
            var t = template
            t.id = UUID()
            t.amount = value
            t.date = FinanceCalendar.addMonths(template.date, i)
            t.installment = InstallmentInfo(number: i + 1, total: count, groupId: group)
            t.title = "\(template.title) (\(i + 1)/\(count))"
            t.recurrence = nil
            t.createdAt = Date(); t.updatedAt = t.createdAt
            // parcelas futuras de contas ficam pendentes; compras de cartão seguem o status do modelo
            if i > 0 && template.creditCardId == nil { t.status = .pending }
            return t
        }
    }
}

// MARK: - Exclusão de parcelas em grupo

enum InstallmentScope: String, Sendable, CaseIterable {
    case thisOnly, thisAndFuture, all
    var displayName: String {
        switch self {
        case .thisOnly: return "Só esta parcela"
        case .thisAndFuture: return "Esta e as seguintes"
        case .all: return "Todas as parcelas"
        }
    }
}

extension InstallmentEngine {
    /// Parcelas do mesmo grupo (inclui a própria), em ordem.
    static func groupMembers(of tx: Transaction, in transactions: [Transaction]) -> [Transaction] {
        guard let group = tx.installment?.groupId else { return [tx] }
        return transactions.filter { $0.installment?.groupId == group }.sorted { ($0.installment?.number ?? 0) < ($1.installment?.number ?? 0) }
    }

    /// Ids a excluir conforme o escopo. Lançamento sem parcelamento só exclui a si mesmo.
    static func idsToDelete(_ tx: Transaction, scope: InstallmentScope, in transactions: [Transaction]) -> [UUID] {
        guard let info = tx.installment else { return [tx.id] }
        let members = groupMembers(of: tx, in: transactions)
        switch scope {
        case .thisOnly: return [tx.id]
        case .thisAndFuture: return members.filter { ($0.installment?.number ?? 0) >= info.number }.map(\.id)
        case .all: return members.map(\.id)
        }
    }
}

// MARK: - Recorrência

enum RecurrenceEngine {
    /// Datas das ocorrências em [from, to] (inclusive). Calculadas a partir da data inicial
    /// (31/jan, 28|29/fev, 31/mar... sem deriva). A primeira ocorrência é a própria data inicial.
    static func occurrences(start: Date, rule: RecurrenceRule, from: Date, to: Date) -> [Date] {
        let interval = max(rule.interval, 1)
        var result: [Date] = []
        var k = 0
        let fromDay = FinanceCalendar.startOfDay(from), toDay = FinanceCalendar.startOfDay(to)
        while true {
            if let maxN = rule.maxOccurrences, k >= maxN { break }
            let date: Date
            switch rule.frequency {
            case .weekly: date = FinanceCalendar.addDays(start, 7 * interval * k)
            case .monthly: date = FinanceCalendar.addMonths(start, interval * k)
            case .yearly: date = FinanceCalendar.addYears(start, interval * k)
            }
            let day = FinanceCalendar.startOfDay(date)
            if day > toDay { break }
            if let end = rule.endDate, day > FinanceCalendar.startOfDay(end) { break }
            if day >= fromDay { result.append(date) }
            k += 1
            if k > 100_000 { break }
        }
        return result
    }

    /// Gera transações (pendentes, com `recurrenceParentId`) do modelo recorrente em [from, to].
    /// A própria data do modelo não é duplicada: ocorrências já existentes em `existing` (mesmo pai e dia) são puladas.
    static func generate(from template: Transaction, from start: Date, to end: Date, existing: [Transaction] = []) -> [Transaction] {
        guard let rule = template.recurrence else { return [] }
        let taken = Set(existing.filter { $0.recurrenceParentId == template.id }.map { FinanceCalendar.startOfDay($0.date) })
        return occurrences(start: template.date, rule: rule, from: start, to: end).compactMap { date in
            if FinanceCalendar.isSameDay(date, template.date) { return nil } // o modelo já representa a 1ª
            if taken.contains(FinanceCalendar.startOfDay(date)) { return nil }
            var t = template
            t.id = UUID()
            t.date = date
            t.recurrence = nil
            t.recurrenceParentId = template.id
            t.status = .pending
            t.createdAt = Date(); t.updatedAt = t.createdAt
            return t
        }
    }
}
