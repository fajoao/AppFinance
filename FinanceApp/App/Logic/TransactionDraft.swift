import Foundation

enum DraftError: Error, Equatable {
    case zeroAmount, missingSource, missingDestination, sameAccount, cardNotFound

    var message: String {
        switch self {
        case .zeroAmount: return "Digite um valor maior que zero."
        case .missingSource: return "Escolha a conta ou o cartão."
        case .missingDestination: return "Escolha a conta de destino."
        case .sameAccount: return "Origem e destino devem ser contas diferentes."
        case .cardNotFound: return "Cartão não encontrado."
        }
    }
}

/// Estado do formulário "Novo lançamento" (transaction.new). Toda a regra de cálculo (parcelas, cartão,
/// transferência) é delegada aos motores do Core; aqui só há montagem e validação do formulário.
struct TransactionDraft: Equatable, Sendable {
    enum Source: Equatable, Sendable { case account(UUID), card(UUID) }

    enum Repeat: Equatable, Sendable {
        case none, installments(Int), monthly, weekly

        static let installmentRange = 2...24

        var title: String {
            switch self {
            case .none: return "Não repete"
            case .installments(let n): return "Parcelado em \(n)x"
            case .monthly: return "Todo mês"
            case .weekly: return "Toda semana"
            }
        }
    }

    var type: TransactionType = .expense
    var keypad = AmountKeypad()
    var title: String = ""
    var categoryId: UUID? = nil
    /// true quando a categoria veio do CategorySuggester (mostra "Sugerida").
    private(set) var categoryIsSuggested = false
    private var categoryChosenByUser = false
    var source: Source? = nil
    var destinationAccountId: UUID? = nil
    var date: Date
    var repeatRule: Repeat = .none
    var tagIds: [UUID] = []
    var note: String = ""
    /// Membro da família a quem o lançamento é atribuído (nil = ninguém / sem grupo familiar).
    var memberId: UUID? = nil
    /// Caminho relativo do comprovante (ver `AttachmentStorage`).
    var attachmentPath: String? = nil
    /// Identificador do documento de origem (NFC-e, PIX): evita lançar a mesma nota duas vezes.
    var externalId: String? = nil
    /// Preenchido ao editar um lançamento existente.
    private(set) var editingId: UUID? = nil
    private(set) var editingInstallment: InstallmentInfo? = nil

    init(date: Date, type: TransactionType = .expense, defaultAccountId: UUID? = nil) {
        self.date = date
        self.type = type
        if let defaultAccountId { source = .account(defaultAccountId) }
    }

    /// Abre um lançamento existente para edição. Repetição/parcelamento não são editáveis aqui
    /// (use a exclusão por grupo para parcelas); cada parcela pode ter valor, data e dados ajustados.
    init(editing tx: Transaction) {
        self.date = tx.date
        self.type = tx.type
        self.keypad = AmountKeypad(value: tx.amount)
        self.title = tx.installment == nil ? tx.title : Self.stripInstallmentSuffix(tx.title, info: tx.installment!)
        self.categoryId = tx.categoryId
        self.categoryChosenByUser = tx.categoryId != nil
        if let card = tx.creditCardId, tx.invoiceId == nil { source = .card(card) }
        else if let a = tx.accountId { source = .account(a) }
        self.destinationAccountId = tx.destinationAccountId
        self.tagIds = tx.tagIds
        self.note = tx.note ?? ""
        self.memberId = tx.memberId
        self.attachmentPath = tx.attachmentPath
        self.editingId = tx.id
        self.editingInstallment = tx.installment
    }

    var isEditing: Bool { editingId != nil }

    /// Pré-preenche com o que veio do QR da NFC-e ou do OCR. A pessoa confere tudo antes de salvar.
    /// Data no futuro distante é ignorada (provável erro de leitura); o tipo só muda para receita se o comprovante for de PIX recebido.
    mutating func apply(_ prefill: ReceiptPrefill, today: Date, suggester: CategorySuggester?, validKind: (UUID) -> Bool = { _ in true }) {
        if prefill.type == .income, type == .expense { changeType(.income) }
        if let amount = prefill.amount, amount > 0 { keypad = AmountKeypad(value: amount) }
        if let date = prefill.date, FinanceCalendar.daysBetween(today, date) <= 400 { self.date = date }
        if let title = prefill.title, !title.isEmpty { self.title = title }
        if let note = prefill.note, !note.isEmpty { self.note = note }
        externalId = prefill.externalId
        descriptionChanged(suggester: suggester, validKinds: validKind)
    }

    private static func stripInstallmentSuffix(_ title: String, info: InstallmentInfo) -> String {
        let suffix = " (\(info.number)/\(info.total))"
        return title.hasSuffix(suffix) ? String(title.dropLast(suffix.count)) : title
    }

    var amount: Decimal { keypad.value }

    var canSave: Bool { amount > 0 }

    var saveTitle: String {
        if isEditing { return "Salvar alterações" }
        switch type {
        case .expense: return "Salvar despesa"
        case .income: return "Salvar receita"
        case .transfer: return "Salvar transferência"
        }
    }

    // MARK: Categoria

    mutating func chooseCategory(_ id: UUID?) {
        categoryId = id
        categoryChosenByUser = id != nil
        categoryIsSuggested = false
    }

    /// Chamar quando a descrição muda. Só sugere se a pessoa ainda não escolheu categoria.
    mutating func descriptionChanged(suggester: CategorySuggester?, validKinds: (UUID) -> Bool = { _ in true }) {
        guard type != .transfer, !categoryChosenByUser else { return }
        if let id = suggester?.suggest(for: title, type: type), validKinds(id) {
            categoryId = id; categoryIsSuggested = true
        } else if categoryIsSuggested {
            categoryId = nil; categoryIsSuggested = false
        }
    }

    mutating func changeType(_ newType: TransactionType) {
        guard newType != type else { return }
        type = newType
        categoryId = nil; categoryIsSuggested = false; categoryChosenByUser = false
        if newType != .expense, case .card = source { source = nil }
        if newType == .transfer { if case .installments = repeatRule { repeatRule = .none } }
        if newType == .income { if case .installments = repeatRule { repeatRule = .none } }
        if newType != .transfer { destinationAccountId = nil }
    }

    // MARK: Parcelas

    /// Parcelas calculadas pelo Core (a última absorve o resto de centavos).
    func installmentValues() -> [Decimal] {
        guard case .installments(let n) = repeatRule, amount > 0 else { return [] }
        return (try? InstallmentEngine.split(total: amount, count: n)) ?? []
    }

    /// "12x de R$ 83,33" (ou, se houver resto: "12x de R$ 83,33, última R$ 83,37").
    func installmentSummary() -> String? {
        let values = installmentValues()
        guard let first = values.first, let last = values.last, case .installments(let n) = repeatRule else { return nil }
        var s = "\(n)x de \(MoneyDisplay.text(first))"
        if last != first { s += ", última \(MoneyDisplay.text(last))" }
        return s
    }

    // MARK: Validação e montagem

    func validate() -> DraftError? {
        guard amount > 0 else { return .zeroAmount }
        if type == .transfer {
            guard case .account(let from)? = source else { return .missingSource }
            guard let to = destinationAccountId else { return .missingDestination }
            if from == to { return .sameAccount }
        } else if source == nil { return .missingSource }
        return nil
    }

    var effectiveTitle: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        switch type {
        case .expense: return "Despesa"
        case .income: return "Receita"
        case .transfer: return "Transferência"
        }
    }

    /// Monta os lançamentos a salvar. Datas futuras ficam pendentes (aparecem em "A pagar").
    func makeTransactions(cards: [CreditCard], today: Date) throws -> [Transaction] {
        if let e = validate() { throw e }
        let status: TransactionStatus = FinanceCalendar.isBeforeDay(today, date) ? .pending : .paid
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let noteValue = trimmedNote.isEmpty ? nil : trimmedNote

        if type == .transfer {
            guard case .account(let from)? = source, let to = destinationAccountId else { throw DraftError.missingSource }
            var t = try BalanceEngine.makeTransfer(from: from, to: to, amount: amount, date: date, title: effectiveTitle, status: status)
            t.note = noteValue
            t.tagIds = tagIds
            return [withRecurrence(t)]
        }

        switch source {
        case .card(let cardId)?:
            guard let card = cards.first(where: { $0.id == cardId }) else { throw DraftError.cardNotFound }
            var count = 1
            if case .installments(let n) = repeatRule { count = n }
            var list = try CreditCardEngine.makePurchase(card: card, title: effectiveTitle, total: amount, date: date,
                                                         installments: count, categoryId: categoryId, tagIds: tagIds)
            for i in list.indices { list[i].note = noteValue }
            if case .monthly = repeatRule, list.count == 1 { list[0].recurrence = RecurrenceRule(frequency: .monthly) }
            if case .weekly = repeatRule, list.count == 1 { list[0].recurrence = RecurrenceRule(frequency: .weekly) }
            return list
        case .account(let accountId)?:
            var base = Transaction(type: type, amount: amount, date: date, title: effectiveTitle, status: status,
                                   accountId: accountId, categoryId: categoryId, tagIds: tagIds)
            base.note = noteValue
            if case .installments(let n) = repeatRule {
                var list = try InstallmentEngine.makeInstallments(from: base, count: n)
                // a 1ª parcela segue o status pela data (compra à vista no ato é paga)
                list[0].status = status
                return list
            }
            return [withRecurrence(base)]
        case nil:
            throw DraftError.missingSource
        }
    }

    /// Aplica a edição sobre o lançamento original, preservando id, parcelamento, recorrência e vínculos de fatura.
    func updatedTransaction(from original: Transaction, today: Date, now: Date = Date()) throws -> Transaction {
        if let e = validate() { throw e }
        var t = original
        t.amount = amount
        t.date = date
        t.title = original.installment.map { "\(effectiveTitle) (\($0.number)/\($0.total))" } ?? effectiveTitle
        t.categoryId = type == .transfer ? nil : categoryId
        t.tagIds = tagIds
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        t.note = trimmedNote.isEmpty ? nil : trimmedNote
        t.memberId = memberId
        t.attachmentPath = attachmentPath
        switch source {
        case .card(let id)?: t.creditCardId = id; t.accountId = nil
        case .account(let id)?: t.accountId = id; if original.creditCardId != nil, original.invoiceId == nil { t.creditCardId = nil }
        case nil: throw DraftError.missingSource
        }
        t.destinationAccountId = type == .transfer ? destinationAccountId : nil
        if !t.isCardPurchase, FinanceCalendar.isBeforeDay(today, date) { t.status = .pending }
        t.updatedAt = now
        return t
    }

    /// Define a regra de recorrência no modelo; ocorrências futuras são geradas pelo AppStore.
    private func withRecurrence(_ transaction: Transaction) -> Transaction {
        var t = transaction
        switch repeatRule {
        case .monthly: t.recurrence = RecurrenceRule(frequency: .monthly)
        case .weekly: t.recurrence = RecurrenceRule(frequency: .weekly)
        default: break
        }
        return t
    }
}
