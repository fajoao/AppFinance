import SwiftUI
import WidgetKit

/// Complicação: saldo (ou gasto do dia) lido do arquivo que o app do relógio grava ao receber o resumo do iPhone.
struct ComplicationEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct ComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> ComplicationEntry { ComplicationEntry(date: Date(), snapshot: WidgetSnapshot.sample(today: FinanceCalendar.normalize(Date()))) }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : ComplicationEntry(date: Date(), snapshot: load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        let entry = ComplicationEntry(date: Date(), snapshot: load())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
    }

    private func load() -> WidgetSnapshot? { SharedContainer.widgetFileURL().flatMap { WidgetSnapshotStore.load(from: $0) } }
}

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ComplicationEntry

    var body: some View {
        let hidden = entry.snapshot?.hideValues ?? false
        let balance = entry.snapshot.map { WatchDashboard.shortMoney($0.balance, hidden: hidden) } ?? "—"
        switch family {
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Text("Saldo").font(.caption2)
                Text(balance).font(.headline).minimumScaleFactor(0.6)
                Text("Hoje " + (entry.snapshot.map { WatchDashboard.shortMoney($0.todaySpent, hidden: hidden) } ?? "—")).font(.caption2)
            }
        case .accessoryInline:
            Text("Saldo \(balance)")
        default:
            VStack { Image(systemName: "creditcard").font(.caption2); Text(balance).font(.caption2).minimumScaleFactor(0.5).lineLimit(1) }
        }
    }
}

@main
struct FinanceComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "FinanceComplication", provider: ComplicationProvider()) { entry in
            ComplicationView(entry: entry).containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Saldo")
        .description("Saldo em contas e gasto do dia.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}
