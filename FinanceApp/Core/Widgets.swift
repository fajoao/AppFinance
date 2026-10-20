import Foundation

// Dados compartilhados entre o app, o widget (WidgetKit) e os atalhos (App Intents).
// Sem UI e sem frameworks da Apple: compila nos três alvos e é testado com swiftc.

// MARK: - Widgets

struct WidgetDue: Codable, Sendable, Equatable {
    enum Kind: String, Codable, Sendable { case bill, invoice }
    var title: String
    var amount: Decimal
    var dueDate: Date
    var kind: Kind
    var isOverdue: Bool
}

/// O que os widgets mostram. O app grava este arquivo no App Group; o widget só lê (nunca acessa o banco inteiro).
struct WidgetSnapshot: Codable, Sendable, Equatable {
    var generatedAt: Date
    /// Saldo líquido (corrente + poupança + carteira).
    var balance: Decimal
    var todaySpent: Decimal
    var nextDue: WidgetDue?
    /// Espelha "ocultar valores": o widget mostra R$ •••• quando verdadeiro.
    var hideValues: Bool
}

extension WidgetSnapshot {
    static let maskedMoney = "R$\u{00A0}••••"
    var balanceText: String { hideValues ? Self.maskedMoney : Money.format(balance) }
    var todaySpentText: String { hideValues ? Self.maskedMoney : Money.format(todaySpent) }
    var nextDueAmountText: String { hideValues ? Self.maskedMoney : (nextDue.map { Money.format($0.amount) } ?? "") }

    /// Dados de exemplo para a galeria de widgets e placeholders.
    static func sample(today: Date) -> WidgetSnapshot {
        WidgetSnapshot(generatedAt: today, balance: dec("19000.77"), todaySpent: dec("89.90"),
                       nextDue: WidgetDue(title: "Energia (Enel)", amount: dec("189.40"), dueDate: FinanceCalendar.addDays(today, 3), kind: .bill, isOverdue: false),
                       hideValues: false)
    }
}

extension WidgetDue {
    /// "Vence hoje", "Vence amanhã", "Vence em 5 dias", "Atrasada há 2 dias".
    func statusText(today: Date) -> String {
        let d = FinanceCalendar.daysBetween(today, dueDate)
        switch d {
        case 0: return "Vence hoje"
        case 1: return "Vence amanhã"
        case 2...: return "Vence em \(d) dias"
        case -1: return "Atrasada há 1 dia"
        default: return "Atrasada há \(-d) dias"
        }
    }
}

enum WidgetDataBuilder {
    static func make(snapshot s: FinanceSnapshot, today: Date, hideValues: Bool) -> WidgetSnapshot {
        let balance = BalanceEngine.totalBalance(accounts: s.accounts, transactions: s.transactions,
                                                 types: [.checking, .savings, .wallet])
        let spent = s.transactions.reduce(Decimal(0)) { acc, tx in
            guard tx.type == .expense, !tx.isInvoicePayment, FinanceCalendar.isSameDay(tx.date, today) else { return acc }
            return acc + tx.amount
        }
        return WidgetSnapshot(generatedAt: today, balance: balance, todaySpent: spent,
                              nextDue: nextDue(snapshot: s, today: today), hideValues: hideValues)
    }

    private static func nextDue(snapshot s: FinanceSnapshot, today: Date) -> WidgetDue? {
        var candidates: [WidgetDue] = []
        for tx in s.transactions where tx.status == .pending && tx.type == .expense && !tx.isCardPurchase && !tx.isInvoicePayment {
            candidates.append(WidgetDue(title: tx.title, amount: tx.amount, dueDate: tx.date, kind: .bill,
                                        isOverdue: FinanceCalendar.isBeforeDay(tx.date, today)))
        }
        for card in s.creditCards where !card.isArchived {
            let current = CreditCardEngine.currentInvoiceMonth(card: card, asOf: today)
            for offset in -1...2 {
                let sum = CreditCardEngine.summary(card: card, month: current.adding(months: offset), transactions: s.transactions,
                                                   storedInvoices: s.invoices, asOf: today)
                guard sum.remaining > 0 else { continue }
                candidates.append(WidgetDue(title: "Fatura \(card.name)", amount: sum.remaining, dueDate: sum.invoice.dueDate,
                                            kind: .invoice, isOverdue: FinanceCalendar.isBeforeDay(sum.invoice.dueDate, today)))
            }
        }
        return candidates.min { $0.dueDate != $1.dueDate ? $0.dueDate < $1.dueDate : $0.title < $1.title }
    }
}

enum WidgetSnapshotStore {
    static func save(_ snapshot: WidgetSnapshot, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONFileStore.encoder.encode(snapshot).write(to: url, options: .atomic)
    }

    /// nil se o arquivo não existe ou está ilegível (o widget mostra o estado vazio).
    static func load(from url: URL) -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONFileStore.decoder.decode(WidgetSnapshot.self, from: data)
    }
}

// MARK: - Atalhos (Siri / App Intents)

struct QuickExpense: Equatable, Sendable {
    var title: String
    var amount: Decimal

    func makeTransaction(accountId: UUID?, categoryId: UUID?, memberId: UUID?, date: Date) -> Transaction {
        var t = Transaction(type: .expense, amount: amount, date: date, title: title, status: .paid,
                            accountId: accountId, categoryId: categoryId)
        t.memberId = memberId
        return t
    }
}

enum QuickExpenseParser {
    private static let leadingFillers: Set<String> = ["gastei", "paguei", "comprei", "gasto", "adicionar", "adicione", "despesa"]
    private static let dropAnywhere: Set<String> = ["reais", "real", "r$"]
    private static let leadingPrepositions: Set<String> = ["no", "na", "em", "de", "do", "da", "com", "para", "pra"]

    /// "gastei 45,90 no mercado" -> (Mercado, 45,90). Usa o último número da frase como valor. Valor por extenso
    /// ("quarenta reais") não é interpretado. Retorna nil sem valor ou com valor zero.
    static func parse(_ text: String) -> QuickExpense? {
        var tokens = text.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
        guard let idx = tokens.lastIndex(where: { $0.contains(where: \.isNumber) && Money.parse($0) != nil }),
              let amount = Money.parse(tokens[idx]), amount > 0 else { return nil }
        tokens.remove(at: idx)
        tokens = tokens.filter { !dropAnywhere.contains($0.lowercased()) }
        while let first = tokens.first, leadingFillers.contains(first.lowercased()) { tokens.removeFirst() }
        while let first = tokens.first, leadingPrepositions.contains(first.lowercased()) { tokens.removeFirst() }
        let raw = tokens.joined(separator: " ")
        let title = raw.isEmpty ? "Despesa" : raw.prefix(1).uppercased() + raw.dropFirst()
        return QuickExpense(title: title, amount: amount)
    }
}

// MARK: - Contêiner compartilhado (App Group)

/// Identificadores compartilhados entre o app e as extensões. Troque `com.example` pelo seu bundle id
/// (project.yml, Assets/*.entitlements e aqui) ao configurar a conta de desenvolvedor.
enum SharedContainer {
    static let appGroupID = "group.com.example.financas"
    static let widgetFileName = "widget.json"

    /// Arquivo do resumo dos widgets dentro do App Group (nil se a capability não estiver configurada).
    static func widgetFileURL(fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(widgetFileName, isDirectory: false)
    }
}
