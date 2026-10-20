import Foundation

enum BillDirection: Equatable, Sendable { case payable, receivable }

/// Uma "conta a pagar/receber": lançamento pendente (ou recorrente/parcelado já pago) ou fatura de cartão.
struct BillItem: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    /// Valor em aberto (faturas: o que falta pagar; se paga, o total).
    var amount: Decimal
    var dueDate: Date
    var direction: BillDirection
    var isPaid: Bool
    var transactionId: UUID? = nil
    var cardId: UUID? = nil
    var invoiceMonth: YearMonth? = nil
    var categoryId: UUID? = nil
    var isInvoice: Bool { cardId != nil }
}

enum BillStatus: Equatable, Sendable {
    case paid(receivable: Bool)
    case overdue(days: Int, receivable: Bool)
    case dueToday
    case dueSoon(days: Int)
    case pending
    case toReceive

    var label: String {
        switch self {
        case .paid(let r): return r ? "Recebido" : "Pago"
        case .overdue(let d, let r):
            if r { return "Recebimento atrasado" }
            return "Atrasado \(d) \(d == 1 ? "dia" : "dias")"
        case .dueToday: return "Vence hoje"
        case .dueSoon(let d): return d == 1 ? "Vence amanhã" : "Vence em \(d) dias"
        case .pending: return "Pendente"
        case .toReceive: return "A receber"
        }
    }

    enum Tone: Equatable, Sendable { case ok, danger, warning, brand, neutral }
    var tone: Tone {
        switch self {
        case .paid: return .ok
        case .overdue: return .danger
        case .dueToday, .dueSoon: return .warning
        case .toReceive: return .brand
        case .pending: return .neutral
        }
    }
}

enum BillsModel {
    /// Antecedência (dias) em que "vence em N dias" vira alerta.
    static let alertWindowDays = 3

    static func status(of bill: BillItem, today: Date) -> BillStatus {
        let receivable = bill.direction == .receivable
        if bill.isPaid { return .paid(receivable: receivable) }
        let d = FinanceCalendar.daysBetween(today, bill.dueDate)
        if d < 0 { return .overdue(days: -d, receivable: receivable) }
        if receivable { return .toReceive }
        if d == 0 { return .dueToday }
        if d <= alertWindowDays { return .dueSoon(days: d) }
        return .pending
    }

    /// Monta a lista de contas: lançamentos pendentes de contas, recorrências/parcelas já pagas e faturas de cartão.
    static func items(transactions: [Transaction], cards: [CreditCard], invoices: [Invoice], today: Date,
                      invoiceHorizon: Int = 3) -> [BillItem] {
        var result: [BillItem] = []
        for tx in transactions where tx.type != .transfer && !tx.isCardPurchase {
            let scheduled = tx.recurrence != nil || tx.recurrenceParentId != nil || tx.installment != nil
            guard tx.status == .pending || scheduled else { continue }
            result.append(BillItem(id: "tx-\(tx.id.uuidString)", title: tx.title, amount: tx.amount, dueDate: tx.date,
                                   direction: tx.type == .income ? .receivable : .payable, isPaid: tx.status == .paid,
                                   transactionId: tx.id, categoryId: tx.categoryId))
        }
        for card in cards where !card.isArchived {
            let list = CreditCardEngine.upcomingInvoices(card: card, transactions: transactions, storedInvoices: invoices,
                                                         asOf: today, futureCount: invoiceHorizon)
            for s in list where s.total > 0 {
                let paid = s.status == .paid
                result.append(BillItem(id: "inv-\(card.id.uuidString)-\(s.invoice.month.label)",
                                       title: "Fatura \(card.name)", amount: paid ? s.total : s.remaining,
                                       dueDate: s.invoice.dueDate, direction: .payable, isPaid: paid,
                                       cardId: card.id, invoiceMonth: s.invoice.month))
            }
        }
        return result.sorted { $0.dueDate != $1.dueDate ? $0.dueDate < $1.dueDate : $0.title < $1.title }
    }

    static func items(_ all: [BillItem], in month: YearMonth) -> [BillItem] { all.filter { month.contains($0.dueDate) } }

    /// A pagar e a receber (somente em aberto) de uma lista.
    static func totals(_ items: [BillItem]) -> (toPay: Decimal, toReceive: Decimal) {
        var pay: Decimal = 0, receive: Decimal = 0
        for b in items where !b.isPaid {
            if b.direction == .payable { pay += b.amount } else { receive += b.amount }
        }
        return (pay, receive)
    }

    /// Semanas do mês (domingo primeiro); `nil` = célula vazia.
    static func calendarWeeks(for month: YearMonth) -> [[Date?]] {
        let lead = DateText.weekdayIndex(month.firstDay)
        var cells: [Date?] = Array(repeating: nil, count: lead)
        for d in 1...month.daysInMonth { cells.append(month.date(day: d)) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    /// Tons distintos dos pontos de um dia (máx. 3), na ordem de gravidade.
    static func dots(on day: Date, bills: [BillItem], today: Date) -> [BillStatus.Tone] {
        let tones = bills.filter { FinanceCalendar.isSameDay($0.dueDate, day) }.map { status(of: $0, today: today).tone }
        let order: [BillStatus.Tone] = [.danger, .warning, .brand, .neutral, .ok]
        return order.filter(tones.contains)
    }
}

// MARK: - Lembretes

struct PlannedReminder: Equatable, Sendable {
    var id: String
    var title: String
    var body: String
    /// Dia civil + hora local do disparo.
    var year: Int, month: Int, day: Int, hour: Int
}

protocol ReminderScheduling: AnyObject {
    @MainActor func requestAuthorization() async -> Bool
    @MainActor func replaceAll(with reminders: [PlannedReminder]) async
    @MainActor func notifyNow(id: String, title: String, body: String) async
}

/// Implementação vazia (testes, UI sem permissão).
@MainActor final class NoopReminderScheduler: ReminderScheduling {
    var planned: [PlannedReminder] = []
    var immediate: [(id: String, title: String, body: String)] = []
    func requestAuthorization() async -> Bool { true }
    func replaceAll(with reminders: [PlannedReminder]) async { planned = reminders }
    func notifyNow(id: String, title: String, body: String) async { immediate.append((id, title, body)) }
}

enum ReminderPlanner {
    static let hour = 9
    /// iOS permite no máximo 64 notificações locais pendentes.
    static let maxPending = 60

    static func plan(bills: [BillItem], today: Date, daysBefore: Int) -> [PlannedReminder] {
        let lead = max(daysBefore, 0)
        var out: [PlannedReminder] = []
        for b in bills where !b.isPaid && b.direction == .payable {
            let fire = FinanceCalendar.addDays(b.dueDate, -lead)
            // dia passado não agenda; dia de hoje agenda só se ainda for antes das 9h (decidido pelo sistema)
            if FinanceCalendar.isBeforeDay(fire, today) { continue }
            let c = FinanceCalendar.components(fire)
            let body: String
            switch lead {
            case 0: body = "\(b.title) vence hoje: \(MoneyDisplay.text(b.amount))."
            case 1: body = "\(b.title) vence amanhã: \(MoneyDisplay.text(b.amount))."
            default: body = "\(b.title) vence em \(lead) dias: \(MoneyDisplay.text(b.amount))."
            }
            out.append(PlannedReminder(id: "bill-\(b.id)", title: "Conta a pagar", body: body,
                                       year: c.year, month: c.month, day: c.day, hour: hour))
        }
        return Array(out.sorted { ($0.year, $0.month, $0.day, $0.id) < ($1.year, $1.month, $1.day, $1.id) }.prefix(maxPending))
    }
}
