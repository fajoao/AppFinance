import Foundation

// Lógica do Apple Watch SEM WatchConnectivity nem SwiftUI: formato das mensagens entre iPhone e relógio, o que o relógio
// mostra e como o iPhone transforma um ditado em despesa. O transporte (WCSession) fica em arquivos próprios:
// `App/Services/WatchConnectivityBridge.swift` (iPhone) e `Watch/` (relógio). Compila nos alvos iOS, widgets e watchOS.

/// Formato das mensagens. WCSession só aceita tipos de property list, então o conteúdo vai como `Data` JSON dentro de um dicionário.
enum WatchLink {
    static let version = 1
    static let versionKey = "v"
    static let snapshotKey = "snapshot"
    static let quickAddKey = "quickAdd"

    // MARK: iPhone -> relógio (applicationContext)

    static func context(for snapshot: WidgetSnapshot) -> [String: Any] {
        let data = (try? JSONFileStore.encoder.encode(snapshot)) ?? Data()
        return [versionKey: version, snapshotKey: data]
    }

    /// nil se a mensagem não é deste formato ou vem de uma versão que este código não entende.
    static func snapshot(from context: [String: Any]) -> WidgetSnapshot? {
        guard context[versionKey] as? Int == version, let data = context[snapshotKey] as? Data else { return nil }
        return try? JSONFileStore.decoder.decode(WidgetSnapshot.self, from: data)
    }

    // MARK: relógio -> iPhone (transferUserInfo, entrega garantida e em fila)

    static func message(for request: WatchQuickAddRequest) -> [String: Any] {
        [versionKey: version, quickAddKey: (try? JSONFileStore.encoder.encode(request)) ?? Data()]
    }

    static func quickAdd(from message: [String: Any]) -> WatchQuickAddRequest? {
        guard message[versionKey] as? Int == version, let data = message[quickAddKey] as? Data else { return nil }
        return try? JSONFileStore.decoder.decode(WatchQuickAddRequest.self, from: data)
    }
}

/// Despesa rápida ditada no relógio. O `id` torna a entrega idempotente (a fila do WatchConnectivity pode repetir).
struct WatchQuickAddRequest: Codable, Sendable, Equatable {
    var id: UUID
    var text: String
    var createdAt: Date

    init(id: UUID = UUID(), text: String, createdAt: Date = Date()) {
        self.id = id; self.text = text; self.createdAt = createdAt
    }
}

enum WatchQuickAddResult: Sendable, Equatable {
    case created(Transaction)
    case duplicate
    case invalid(String)
}

enum WatchQuickAdd {
    static let maxAmount: Decimal = 1_000_000
    static let invalidMessage = "Não entendi o valor. Diga, por exemplo: \"gastei 45,90 no mercado\"."

    static func externalId(for request: WatchQuickAddRequest) -> String { "watch:" + request.id.uuidString }

    /// Pré-visualização no relógio antes de enviar. nil = não deu para entender o valor.
    static func preview(_ text: String) -> (title: String, amount: Decimal)? {
        guard let q = QuickExpenseParser.parse(text), q.amount <= maxAmount else { return nil }
        return (q.title, q.amount)
    }

    /// Transforma o pedido em lançamento no iPhone. A data é o dia em que foi ditado (nunca no futuro).
    static func process(_ request: WatchQuickAddRequest, existing: [Transaction], accountId: UUID?, categoryId: UUID?,
                        memberId: UUID?, today: Date) -> WatchQuickAddResult {
        let ext = externalId(for: request)
        if existing.contains(where: { $0.externalId == ext }) { return .duplicate }
        guard let q = QuickExpenseParser.parse(request.text), q.amount <= maxAmount else { return .invalid(invalidMessage) }
        var date = FinanceCalendar.normalize(request.createdAt)
        if FinanceCalendar.isBeforeDay(today, date) { date = today }
        var t = q.makeTransaction(accountId: accountId, categoryId: categoryId, memberId: memberId, date: date)
        t.externalId = ext
        return .created(t)
    }
}

/// Textos do relógio e das complicações, a partir do resumo gravado pelo iPhone.
struct WatchDashboard: Equatable, Sendable {
    var balanceText: String
    var todaySpentText: String
    var nextDueTitle: String?
    var nextDueText: String?
    var freshnessText: String
    /// Resumo com mais de 1 dia: o relógio avisa para abrir o app no iPhone.
    var isStale: Bool
    var hasData: Bool

    static let placeholder = WatchDashboard(balanceText: "—", todaySpentText: "—", nextDueTitle: nil, nextDueText: nil,
                                            freshnessText: "Abra o Finanças no iPhone", isStale: true, hasData: false)

    static func make(snapshot: WidgetSnapshot?, now: Date) -> WatchDashboard {
        guard let s = snapshot else { return .placeholder }
        let age = max(FinanceCalendar.daysBetween(s.generatedAt, FinanceCalendar.normalize(now)), 0)
        let fresh: String
        switch age {
        case 0: fresh = "Atualizado hoje"
        case 1: fresh = "Atualizado ontem"
        default: fresh = "Atualizado há \(age) dias"
        }
        var title: String?, due: String?
        if let d = s.nextDue {
            title = d.title
            due = "\(d.statusText(today: FinanceCalendar.normalize(now))), \(s.nextDueAmountText)"
        }
        return WatchDashboard(balanceText: s.balanceText, todaySpentText: s.todaySpentText, nextDueTitle: title, nextDueText: due,
                              freshnessText: fresh, isStale: age > 1, hasData: true)
    }

    /// Valor curto para espaços pequenos (complicação): "R$ 950", "R$ 19,0 mil", "R$ 1,2 mi". Respeita "ocultar valores".
    static func shortMoney(_ value: Decimal, hidden: Bool) -> String {
        if hidden { return WidgetSnapshot.maskedMoney }
        let n = value.magnitude
        let sign = value < 0 ? "-" : ""
        func fmt(_ v: Decimal, _ unit: String) -> String {
            sign + "R$" + Money.nbsp + "\(v.rounded(scale: 1))".replacingOccurrences(of: ".", with: ",") + " " + unit
        }
        if n >= 1_000_000 { return fmt(n / 1_000_000, "mi") }
        if n >= 1_000 { return fmt(n / 1_000, "mil") }
        return sign + "R$" + Money.nbsp + "\(n.rounded(scale: 0))"
    }
}
