import SwiftUI
import WidgetKit

// Widgets do Finanças: saldo, gastos do dia e próximo vencimento.
// A extensão NÃO acessa o banco do app: lê só o resumo (`WidgetSnapshot`) que o app grava no App Group
// (`SharedContainer`). Sem o App Group configurado ou sem dados, mostra um estado vazio claro.
// STATUS: typecheck contra o SDK do macOS; não foi executado no Simulador nem em aparelho.

struct FinanceEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    /// Dia civil de hoje (UTC meio-dia), para cálculos de vencimento.
    let today: Date
}

struct FinanceProvider: TimelineProvider {
    private func load(_ date: Date) -> FinanceEntry {
        let url = SharedContainer.widgetFileURL()
        return FinanceEntry(date: date, snapshot: url.flatMap { WidgetSnapshotStore.load(from: $0) }, today: FinanceCalendar.normalize(date))
    }

    func placeholder(in context: Context) -> FinanceEntry {
        let today = FinanceCalendar.normalize(Date())
        return FinanceEntry(date: Date(), snapshot: .sample(today: today), today: today)
    }

    func getSnapshot(in context: Context, completion: @escaping (FinanceEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : load(Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FinanceEntry>) -> Void) {
        let now = Date()
        // O app pede reloadAllTimelines a cada mudança; este refresh é só um seguro (virada do dia, "vence hoje").
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: now) ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: [load(now)], policy: .after(next)))
    }
}

extension WidgetFamily {
    /// Famílias suportadas. As acessórias (tela de bloqueio) só existem no iOS.
    static var supported: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .accessoryRectangular]
        #else
        [.systemSmall]
        #endif
    }

    var isAccessory: Bool {
        #if os(iOS)
        self == .accessoryRectangular || self == .accessoryInline || self == .accessoryCircular
        #else
        false
        #endif
    }
}

private enum WidgetPalette {
    static let brand = Color("brandPrimary")
    static let danger = Color("danger")
    static let warning = Color("warning")
    static let secondary = Color("textSecondary")
}

private struct EmptyWidgetView: View {
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "wallet.pass").font(.title3)
            Text("Abra o Finanças para ver seus dados").font(.caption).multilineTextAlignment(.center)
        }
        .foregroundStyle(WidgetPalette.secondary)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Saldo

struct BalanceWidgetView: View {
    let entry: FinanceEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let s = entry.snapshot {
                if family.isAccessory {
                    VStack(alignment: .leading) {
                        Text("Saldo em contas").font(.caption2)
                        Text(s.balanceText).font(.headline).minimumScaleFactor(0.6)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Saldo em contas", systemImage: "wallet.pass").font(.caption.weight(.semibold)).foregroundStyle(WidgetPalette.secondary)
                        Spacer(minLength: 0)
                        Text(s.balanceText).font(.title2.weight(.semibold)).monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                            .foregroundStyle(s.balance < 0 && !s.hideValues ? WidgetPalette.danger : Color.primary)
                        Text(s.nextDue.map { "\($0.title): \($0.statusText(today: entry.today).lowercased())" } ?? "Sem contas a pagar")
                            .font(.caption2).foregroundStyle(WidgetPalette.secondary).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else { EmptyWidgetView() }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .accessibilityElement(children: .combine)
    }
}

struct BalanceWidget: Widget {
    let kind = "com.example.financas.widget.balance"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FinanceProvider()) { BalanceWidgetView(entry: $0) }
            .configurationDisplayName("Saldo")
            .description("Seu saldo em contas, com o próximo vencimento.")
            .supportedFamilies(WidgetFamily.supported)
    }
}

// MARK: Gastos do dia

struct DailySpendWidgetView: View {
    let entry: FinanceEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let s = entry.snapshot {
                if family.isAccessory {
                    VStack(alignment: .leading) {
                        Text("Gasto hoje").font(.caption2)
                        Text(s.todaySpentText).font(.headline).minimumScaleFactor(0.6)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Gastos de hoje", systemImage: "cart").font(.caption.weight(.semibold)).foregroundStyle(WidgetPalette.secondary)
                        Spacer(minLength: 0)
                        Text(s.todaySpentText).font(.title2.weight(.semibold)).monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                        Text(s.todaySpent == 0 ? "Nada gasto até agora" : "Despesas lançadas hoje")
                            .font(.caption2).foregroundStyle(WidgetPalette.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else { EmptyWidgetView() }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .accessibilityElement(children: .combine)
    }
}

struct DailySpendWidget: Widget {
    let kind = "com.example.financas.widget.dailyspend"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FinanceProvider()) { DailySpendWidgetView(entry: $0) }
            .configurationDisplayName("Gastos do dia")
            .description("Quanto você gastou hoje.")
            .supportedFamilies(WidgetFamily.supported)
    }
}

// MARK: Próximo vencimento

struct NextDueWidgetView: View {
    let entry: FinanceEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let s = entry.snapshot {
                if let due = s.nextDue {
                    if family.isAccessory {
                        VStack(alignment: .leading) {
                            Text(due.title).font(.caption2).lineLimit(1)
                            Text(s.nextDueAmountText).font(.headline).minimumScaleFactor(0.6)
                            Text(due.statusText(today: entry.today)).font(.caption2)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Label("Próximo vencimento", systemImage: due.kind == .invoice ? "creditcard" : "calendar")
                                .font(.caption.weight(.semibold)).foregroundStyle(WidgetPalette.secondary)
                            Spacer(minLength: 0)
                            Text(due.title).font(.subheadline.weight(.medium)).lineLimit(2)
                            Text(s.nextDueAmountText).font(.title3.weight(.semibold)).monospacedDigit().minimumScaleFactor(0.5).lineLimit(1)
                            Text(due.statusText(today: entry.today)).font(.caption.weight(.semibold))
                                .foregroundStyle(due.isOverdue ? WidgetPalette.danger : WidgetPalette.warning)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: "checkmark.circle").font(.title3)
                        Text("Nada a pagar").font(.caption)
                    }
                    .foregroundStyle(WidgetPalette.secondary)
                }
            } else { EmptyWidgetView() }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .accessibilityElement(children: .combine)
    }
}

struct NextDueWidget: Widget {
    let kind = "com.example.financas.widget.nextdue"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FinanceProvider()) { NextDueWidgetView(entry: $0) }
            .configurationDisplayName("Próximo vencimento")
            .description("A próxima conta ou fatura a pagar.")
            .supportedFamilies(WidgetFamily.supported)
    }
}

@main
struct FinanceWidgetBundle: WidgetBundle {
    var body: some Widget {
        BalanceWidget()
        DailySpendWidget()
        NextDueWidget()
    }
}
