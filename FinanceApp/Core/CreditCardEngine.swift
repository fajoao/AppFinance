import Foundation

struct InvoiceSummary: Sendable, Equatable {
    var invoice: Invoice
    /// true se a fatura já existe no repositório (tem pagamento registrado).
    var isStored: Bool
    var total: Decimal
    var paidAmount: Decimal
    var remaining: Decimal { max(total - paidAmount, 0) }
    var status: InvoiceStatus
    var transactions: [Transaction]
}

enum CreditCardEngine {
    private static func clampDay(_ day: Int, in m: YearMonth) -> Int { min(max(day, 1), m.daysInMonth) }

    /// Data de fechamento da fatura cujo fechamento ocorre no mês `month`.
    static func closingDate(card: CreditCard, month: YearMonth) -> Date {
        month.date(day: card.closingDay)
    }

    /// Vencimento da fatura que fecha em `month`: no mesmo mês se o dia de vencimento é maior
    /// que o de fechamento; senão no mês seguinte.
    static func dueDate(card: CreditCard, month: YearMonth) -> Date {
        let dueMonth = card.dueDay > card.closingDay ? month : month.next
        return dueMonth.date(day: card.dueDay)
    }

    /// Fatura (mês de fechamento) à qual a compra pertence. Compra no dia do fechamento ou depois vai para a próxima.
    static func invoiceMonth(forPurchaseOn date: Date, card: CreditCard) -> YearMonth {
        let ym = YearMonth(date)
        let day = FinanceCalendar.components(date).day
        return day < clampDay(card.closingDay, in: ym) ? ym : ym.next
    }

    /// Fatura atual (aberta) na data `asOf`.
    static func currentInvoiceMonth(card: CreditCard, asOf: Date) -> YearMonth {
        invoiceMonth(forPurchaseOn: asOf, card: card)
    }

    static func purchases(card: CreditCard, month: YearMonth, transactions: [Transaction]) -> [Transaction] {
        transactions
            .filter { $0.creditCardId == card.id && $0.isCardPurchase && invoiceMonth(forPurchaseOn: $0.date, card: card) == month }
            .sorted { $0.date < $1.date }
    }

    /// Valor assinado de uma compra: despesa soma na fatura; receita/estorno abate.
    private static func chargeValue(_ tx: Transaction) -> Decimal {
        tx.type == .income ? -tx.amount : tx.amount
    }

    static func invoiceTotal(card: CreditCard, month: YearMonth, transactions: [Transaction]) -> Decimal {
        purchases(card: card, month: month, transactions: transactions).reduce(0) { $0 + chargeValue($1) }
    }

    static func summary(card: CreditCard, month: YearMonth, transactions: [Transaction], storedInvoices: [Invoice] = [], asOf: Date) -> InvoiceSummary {
        let items = purchases(card: card, month: month, transactions: transactions)
        let total = items.reduce(0) { $0 + chargeValue($1) }
        let stored = storedInvoices.first { $0.cardId == card.id && $0.month == month }
        let invoice = stored ?? Invoice(cardId: card.id, month: month,
                                        closingDate: closingDate(card: card, month: month),
                                        dueDate: dueDate(card: card, month: month),
                                        ownerId: card.ownerId)
        let paid = invoice.paidAmount
        let day = FinanceCalendar.startOfDay(asOf)
        let status: InvoiceStatus
        if total > 0 ? paid >= total : (stored?.paidAt != nil) {
            status = .paid
        } else if day > FinanceCalendar.startOfDay(invoice.dueDate) {
            status = .overdue
        } else if day >= FinanceCalendar.startOfDay(invoice.closingDate) {
            status = .closed
        } else {
            status = .open
        }
        return InvoiceSummary(invoice: invoice, isStored: stored != nil, total: total, paidAmount: paid,
                              status: status, transactions: items)
    }

    /// Fatura atual + as próximas `futureCount` faturas (inclui as que ainda estão fechadas/não pagas anteriores à atual).
    static func upcomingInvoices(card: CreditCard, transactions: [Transaction], storedInvoices: [Invoice] = [],
                                 asOf: Date, futureCount: Int = 3) -> [InvoiceSummary] {
        let current = currentInvoiceMonth(card: card, asOf: asOf)
        // inclui a anterior se ainda tiver saldo em aberto (fechada aguardando pagamento)
        var months: [YearMonth] = []
        let prev = current.previous
        let prevSummary = summary(card: card, month: prev, transactions: transactions, storedInvoices: storedInvoices, asOf: asOf)
        if prevSummary.total > 0 && prevSummary.status != .paid { months.append(prev) }
        months.append(current)
        for i in 1...max(futureCount, 1) where i <= futureCount { months.append(current.adding(months: i)) }
        return months.map { summary(card: card, month: $0, transactions: transactions, storedInvoices: storedInvoices, asOf: asOf) }
    }

    /// Limite usado = compras de cartão (todas, inclusive parcelas futuras) - pagamentos de fatura.
    static func usedLimit(card: CreditCard, transactions: [Transaction]) -> Decimal {
        let charges = transactions.filter { $0.creditCardId == card.id && $0.isCardPurchase }.reduce(0) { $0 + chargeValue($1) }
        let payments = transactions.filter { $0.creditCardId == card.id && $0.isInvoicePayment }.reduce(0) { $0 + $1.amount }
        return charges - payments
    }

    static func availableLimit(card: CreditCard, transactions: [Transaction]) -> Decimal {
        card.limit - usedLimit(card: card, transactions: transactions)
    }

    /// Registra a compra no cartão (parcelada se `installments > 1`). Retorna as transações a salvar.
    static func makePurchase(card: CreditCard, title: String, total: Decimal, date: Date, installments: Int = 1,
                             categoryId: UUID? = nil, tagIds: [UUID] = []) throws -> [Transaction] {
        let base = Transaction(type: .expense, amount: total, date: date, title: title, status: .paid,
                               categoryId: categoryId, tagIds: tagIds, creditCardId: card.id, ownerId: card.ownerId)
        if installments <= 1 { return [base] }
        return try InstallmentEngine.makeInstallments(from: base, count: installments)
    }

    /// Paga (total ou parcialmente) uma fatura. Retorna a fatura atualizada e o lançamento de pagamento
    /// (transferência sem destino, que reduz o saldo da conta e libera limite, sem contar como despesa).
    static func pay(_ summary: InvoiceSummary, card: CreditCard, amount: Decimal? = nil, from accountId: UUID, on date: Date) throws -> (invoice: Invoice, payment: Transaction) {
        let value = amount ?? summary.remaining
        guard value > 0 else { throw FinanceError.invalidAmount }
        guard value <= summary.remaining else { throw FinanceError.overpayment }
        var inv = summary.invoice
        inv.paidAmount += value
        inv.paymentAccountId = accountId
        inv.updatedAt = Date()
        if inv.paidAmount >= summary.total { inv.paidAt = date }
        let payment = Transaction(type: .transfer, amount: value, date: date,
                                  title: "Pagamento fatura \(card.name) \(summary.invoice.month.label)", status: .paid,
                                  accountId: accountId, creditCardId: card.id, invoiceId: inv.id, ownerId: card.ownerId)
        return (inv, payment)
    }
}
