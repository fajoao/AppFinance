import Foundation

// Rascunhos de formulário da Fase 2: texto digitado -> valores tipados + mensagens de erro inline.
// Nenhuma regra financeira aqui: as contas são feitas pelo Core.

private func parseDecimal(_ text: String) -> Decimal? { Money.parse(text, style: .comma) }
private func trimmed(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

// MARK: - Dívida

struct DebtDraft: Equatable, Sendable {
    var name = ""
    var balanceText = ""
    /// Juros em % ao mês, como a pessoa lê no contrato ("2,5").
    var rateText = ""
    var minimumText = ""
    var dueDayText = ""
    private(set) var editingId: UUID? = nil

    init() {}

    init(editing d: Debt) {
        name = d.name
        balanceText = Money.plain(d.balance)
        rateText = "\((d.monthlyInterestRate * 100).rounded(scale: 4))".replacingOccurrences(of: ".", with: ",")
        minimumText = Money.plain(d.minimumPayment)
        dueDayText = d.dueDay.map(String.init) ?? ""
        editingId = d.id
    }

    var nameError: String? { trimmed(name).isEmpty ? "Dê um nome para a dívida." : nil }
    var balanceError: String? { (parseDecimal(balanceText) ?? 0) > 0 ? nil : "Informe o saldo devedor." }
    var rateError: String? {
        guard let r = parseDecimal(rateText), r >= 0, r < 100 else { return "Informe os juros ao mês. Exemplo: 2,5" }
        return nil
    }
    var minimumError: String? {
        guard let m = parseDecimal(minimumText), m >= 0 else { return "Informe o pagamento mínimo (0 se não houver)." }
        if let b = parseDecimal(balanceText), m > b { return "O mínimo não pode passar do saldo." }
        return nil
    }
    var dueDayError: String? {
        let t = trimmed(dueDayText)
        if t.isEmpty { return nil }
        guard let d = Int(t), (1...31).contains(d) else { return "Dia inválido. Use de 1 a 31." }
        return nil
    }
    var isValid: Bool { nameError == nil && balanceError == nil && rateError == nil && minimumError == nil && dueDayError == nil }

    func build(existing: Debt? = nil) throws -> Debt {
        guard isValid, let balance = parseDecimal(balanceText), let rate = parseDecimal(rateText), let minimum = parseDecimal(minimumText) else {
            throw StoreError.invalidLimit
        }
        var d = existing ?? Debt(name: trimmed(name), balance: balance, monthlyInterestRate: rate / 100, minimumPayment: minimum)
        d.name = trimmed(name); d.balance = balance; d.monthlyInterestRate = rate / 100; d.minimumPayment = minimum
        d.dueDay = Int(trimmed(dueDayText))
        d.updatedAt = Date()
        return d
    }
}

// MARK: - Meta

struct GoalDraft: Equatable, Sendable {
    var name = ""
    var targetText = ""
    var hasDeadline = true
    var deadline: Date
    private(set) var editingId: UUID? = nil

    init(today: Date) { deadline = FinanceCalendar.addMonths(today, 12) }

    init(editing g: Goal, today: Date) {
        name = g.name
        targetText = Money.plain(g.targetAmount)
        hasDeadline = g.deadline != nil
        deadline = g.deadline ?? FinanceCalendar.addMonths(today, 12)
        editingId = g.id
    }

    var target: Decimal? { parseDecimal(targetText) }
    var nameError: String? { trimmed(name).isEmpty ? "Dê um nome para a meta." : nil }
    var targetError: String? { (target ?? 0) > 0 ? nil : "Informe um valor maior que zero." }
    var isValid: Bool { nameError == nil && targetError == nil }
    var effectiveDeadline: Date? { hasDeadline ? FinanceCalendar.normalize(deadline) : nil }
}

// MARK: - Investimento

struct InvestmentDraft: Equatable, Sendable {
    var name = ""
    var ticker = ""
    var assetClass: AssetClass = .stock
    var quantityText = ""
    var priceText = ""
    var quoteText = ""
    private(set) var editingId: UUID? = nil

    init() {}

    init(editing i: Investment) {
        name = i.name; ticker = i.ticker ?? ""; assetClass = i.assetClass
        quantityText = Money.plain(i.quantity); priceText = Money.plain(i.averagePrice)
        quoteText = i.quote.map { Money.plain($0) } ?? ""
        editingId = i.id
    }

    /// Renda fixa é cadastrada pelo valor aplicado e pelo valor atual (quantidade 1).
    var usesAmountOnly: Bool { assetClass == .fixedIncome }
    var priceLabel: String { usesAmountOnly ? "Valor aplicado" : "Preço médio" }
    var quoteLabel: String { usesAmountOnly ? "Valor atual (opcional)" : "Cotação atual (opcional)" }

    var quantity: Decimal? { usesAmountOnly ? 1 : parseDecimal(quantityText) }
    var price: Decimal? { parseDecimal(priceText) }
    var quote: Decimal? { trimmed(quoteText).isEmpty ? nil : parseDecimal(quoteText) }

    var nameError: String? { trimmed(name).isEmpty ? "Dê um nome para o ativo." : nil }
    var quantityError: String? { (quantity ?? 0) > 0 ? nil : "Informe a quantidade." }
    var priceError: String? { (price ?? -1) >= 0 && !trimmed(priceText).isEmpty ? nil : "Informe o valor." }
    var quoteError: String? { trimmed(quoteText).isEmpty || (quote ?? -1) >= 0 ? nil : "Cotação inválida." }
    var isValid: Bool { nameError == nil && quantityError == nil && priceError == nil && quoteError == nil }

    func build(existing: Investment? = nil, today: Date) throws -> Investment {
        guard isValid, let quantity, let price else { throw StoreError.invalidQuote }
        var i = existing ?? Investment(name: trimmed(name), assetClass: assetClass, quantity: quantity, averagePrice: price)
        i.name = trimmed(name)
        i.ticker = trimmed(ticker).isEmpty ? nil : trimmed(ticker).uppercased()
        i.assetClass = assetClass
        i.quantity = quantity; i.averagePrice = price
        if let q = quote { if i.quote != q { i.quoteDate = today }; i.quote = q } else { i.quote = nil; i.quoteDate = nil }
        i.updatedAt = Date()
        return i
    }
}

// MARK: - Divisão de despesa

struct SplitDraft: Equatable, Sendable {
    var title = ""
    var totalText = ""
    var paidBy: UUID?
    var participants: Set<UUID> = []
    var mode: SplitMode = .equal
    var percentTexts: [UUID: String] = [:]
    var date: Date
    /// Também lança a despesa na conta (atribuída a quem pagou).
    var createsTransaction = false
    var accountId: UUID? = nil

    init(date: Date, members: [FamilyMember] = [], paidBy: UUID? = nil) {
        self.date = date
        self.paidBy = paidBy ?? members.first?.id
        self.participants = Set(members.map(\.id))
    }

    var total: Decimal? { parseDecimal(totalText) }
    var titleError: String? { trimmed(title).isEmpty ? "Dê um nome para a despesa." : nil }
    var totalError: String? { (total ?? 0) > 0 ? nil : "Informe o valor." }
    var participantsError: String? { participants.isEmpty ? "Escolha quem divide." : nil }

    func orderedParticipants(_ members: [FamilyMember]) -> [UUID] { members.map(\.id).filter(participants.contains) }

    var percentages: [UUID: Decimal] { percentTexts.compactMapValues { parseDecimal($0) } }

    func percentSum(_ members: [FamilyMember]) -> Decimal {
        orderedParticipants(members).reduce(Decimal(0)) { $0 + (percentages[$1] ?? 0) }
    }

    var percentError: String? { nil }

    /// Distribui 100% igualmente entre os participantes (ponto de partida do modo percentual).
    mutating func fillEvenPercentages(_ members: [FamilyMember]) {
        let ids = orderedParticipants(members)
        let parts = Money.split(100, into: ids.count)
        for (id, p) in zip(ids, parts) { percentTexts[id] = Money.plain(p) }
    }

    func build(members: [FamilyMember]) throws -> ExpenseSplit {
        guard let paidBy else { throw FinanceError.noParticipants }
        guard let total else { throw FinanceError.invalidAmount }
        return try SplitEngine.make(title: trimmed(title), total: total, date: date, paidBy: paidBy,
                                    participants: orderedParticipants(members), mode: mode, percentages: percentages)
    }

    /// Prévia das partes (para mostrar enquanto digita). Vazia se ainda inválido.
    func preview(members: [FamilyMember]) -> [SplitShare] {
        (try? build(members: members).shares) ?? []
    }
}

// MARK: - Mesada

struct AllowanceDraft: Equatable, Sendable {
    var memberId: UUID?
    var amountText = ""
    var dayText = "5"
    var fromAccountId: UUID?
    var toAccountId: UUID?

    init() {}

    var amount: Decimal? { parseDecimal(amountText) }
    var amountError: String? { (amount ?? 0) > 0 ? nil : "Informe o valor da mesada." }
    var dayError: String? {
        guard let d = Int(trimmed(dayText)), (1...31).contains(d) else { return "Dia inválido. Use de 1 a 31." }
        return nil
    }
    var accountsError: String? {
        guard let f = fromAccountId, let t = toAccountId else { return "Escolha as duas contas." }
        return f == t ? "As contas devem ser diferentes." : nil
    }
    var isValid: Bool { memberId != nil && amountError == nil && dayError == nil && accountsError == nil }
}

// MARK: - Cotação / compra / venda

struct PositionChangeDraft: Equatable, Sendable {
    enum Kind: Sendable { case buy, sell }
    var kind: Kind
    var quantityText = ""
    var priceText = ""

    var quantity: Decimal? { parseDecimal(quantityText) }
    var price: Decimal? { parseDecimal(priceText) }
    var isValid: Bool { (quantity ?? 0) > 0 && (price ?? -1) >= 0 && !trimmed(priceText).isEmpty }
}
