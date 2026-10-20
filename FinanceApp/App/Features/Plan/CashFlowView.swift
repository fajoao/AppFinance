import SwiftUI
import Charts

/// plan.cashflow: saldo projetado em 30, 60 e 90 dias com pendências, recorrências e faturas.
struct CashFlowView: View {
    @Environment(AppStore.self) private var store
    @State private var days = 30

    var body: some View {
        let projection = store.cashFlow(days: days)
        let summary = CashFlowModel.summary(projection)
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                SegmentedTabs(options: [(30, "30 dias"), (60, "60 dias"), (90, "90 dias")], selection: $days, identifier: "plan.cashflow.horizon")
                headline(summary)
                chart(projection)
                totals(projection, summary)
                items(projection)
            }
            .padding(.horizontal, Space.screenMargin)
            .padding(.vertical, Space.lg)
        }
        .background(Color.canvas)
        .navigationTitle("Fluxo de caixa")
        .inlineNavigationTitle()
        .accessibilityIdentifier("plan.cashflow")
    }

    private func headline(_ s: CashFlowSummary) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Saldo previsto em \(s.days) dias").font(.subheadline).foregroundStyle(Color.textSecondary)
            SplitAmount(value: s.endingBalance, style: .large).accessibilityIdentifier("plan.cashflow.ending")
            Label(s.headline, systemImage: s.goesNegative ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.subheadline).foregroundStyle(s.goesNegative ? Color.danger : Color.income)
                .accessibilityIdentifier("plan.cashflow.headline")
        }
    }

    private func chart(_ p: CashFlowProjection) -> some View {
        let points = CashFlowModel.chartPoints(p, today: store.today)
        return Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, pt in
                AreaMark(x: .value("Data", pt.date), y: .value("Saldo", NSDecimalNumber(decimal: pt.balance).doubleValue))
                    .foregroundStyle(Color.brandPrimary.opacity(0.12))
                LineMark(x: .value("Data", pt.date), y: .value("Saldo", NSDecimalNumber(decimal: pt.balance).doubleValue))
                    .foregroundStyle(Color.brandPrimary)
                    .interpolationMethod(.stepEnd)
            }
            RuleMark(y: .value("Zero", 0)).foregroundStyle(Color.danger.opacity(0.7)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .chartYAxis(.hidden)
        .frame(height: 180)
        .padding(Space.md)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gráfico do saldo projetado. Começa em \(MoneyDisplay.spoken(p.startingBalance, hidden: store.preferences.hideValues)) e termina em \(MoneyDisplay.spoken(p.endingBalance, hidden: store.preferences.hideValues)).")
        .accessibilityIdentifier("plan.cashflow.chart")
    }

    private func totals(_ p: CashFlowProjection, _ s: CashFlowSummary) -> some View {
        ListGroup {
            line("Saldo hoje", store.money(p.startingBalance))
            RowSeparator()
            line("Entradas previstas", store.money(p.totalIn))
            RowSeparator()
            line("Saídas previstas", store.money(p.totalOut))
            RowSeparator()
            line("Menor saldo" + (s.lowestDate.map { " (\(DateText.dayMonthShort($0)))" } ?? ""), store.money(p.lowestBalance),
                 color: p.goesNegative ? Color.danger : Color.textSecondary)
        }
    }

    private func line(_ label: String, _ value: String, color: Color = .textSecondary) -> some View {
        ListRow(title: label) { EmptyView() } trailing: {
            Text(value).font(.body).foregroundStyle(color).monospacedDigit()
        }
    }

    @ViewBuilder
    private func items(_ p: CashFlowProjection) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader("Lançamentos previstos")
            if p.items.isEmpty {
                Text("Nada previsto neste período. Contas a pagar, recorrências e faturas aparecem aqui.")
                    .font(.subheadline).foregroundStyle(Color.textSecondary).padding(.horizontal, Space.xs)
            } else {
                ListGroup {
                    ForEach(Array(p.items.prefix(40).enumerated()), id: \.offset) { index, item in
                        ListRow(title: item.label, subtitle: DateText.weekdayDayMonth(item.date)) { EmptyView() } trailing: {
                            AmountText(item.amount.magnitude, sign: item.amount < 0 ? .expense : .income, role: item.amount < 0 ? .expense : .income)
                        }
                        if index < min(p.items.count, 40) - 1 { RowSeparator() }
                    }
                }
            }
        }
    }
}

#Preview("Fluxo de caixa") {
    NavigationStack { CashFlowView() }.previewing(PreviewData.demo)
}

#Preview("Fluxo de caixa, escuro") {
    NavigationStack { CashFlowView() }.previewing(PreviewData.demo, dark: true)
}
