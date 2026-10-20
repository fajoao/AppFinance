import SwiftUI

/// watch.home: saldo, gasto do dia e próximo vencimento, com atalho para a despesa rápida.
struct WatchHomeView: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        let d = model.dashboard
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Saldo em contas").font(.footnote).foregroundStyle(.secondary)
                    Text(d.balanceText).font(.title3.weight(.semibold)).minimumScaleFactor(0.6).lineLimit(1)
                        .accessibilityIdentifier("watch.balance")
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gasto hoje").font(.footnote).foregroundStyle(.secondary)
                    Text(d.todaySpentText).font(.headline).minimumScaleFactor(0.6).lineLimit(1)
                        .accessibilityIdentifier("watch.todaySpent")
                }
                if let title = d.nextDueTitle, let text = d.nextDueText {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Próximo vencimento").font(.footnote).foregroundStyle(.secondary)
                        Text(title).font(.footnote.weight(.semibold))
                        Text(text).font(.footnote).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("watch.nextDue")
                }
                NavigationLink { WatchQuickAddView() } label: { Label("Nova despesa", systemImage: "mic.fill") }
                    .accessibilityIdentifier("watch.add")
                Text(d.freshnessText).font(.caption2).foregroundStyle(d.isStale ? Color.orange : Color.secondary)
                    .accessibilityIdentifier("watch.freshness")
            }
        }
        .navigationTitle("Finanças")
    }
}

#Preview("Relógio") {
    NavigationStack { WatchHomeView() }.environment(WatchModel())
}
