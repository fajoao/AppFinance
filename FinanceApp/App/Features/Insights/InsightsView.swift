import SwiftUI

/// insights: previsão do saldo, alertas, gastos atípicos, assinaturas e sugestões de economia.
/// Tudo é calculado no aparelho, por estatística simples (sem IA nem servidor); cada card mostra "Como calculamos".
struct InsightsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.valuesHidden) private var hidden

    var body: some View {
        let report = store.insightsReport()
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                if store.scopedTransactions.isEmpty {
                    EmptyState(symbol: "lightbulb", title: "Ainda não há o que analisar",
                               message: "Registre alguns lançamentos. Com 3 meses de histórico os insights ficam bem melhores.")
                        .accessibilityIdentifier("insights.empty")
                } else {
                    if !report.hasEnoughHistory {
                        Label("Há poucos meses de dados. Previsões e gastos atípicos ficam mais confiáveis com 3 meses ou mais.", systemImage: "info.circle")
                            .font(.footnote).foregroundStyle(Color.textSecondary)
                            .accessibilityIdentifier("insights.fewData")
                    }
                    forecastHeader(report.forecastEndOfMonth)
                    ForEach(report.insights.filter { $0.kind == .forecast }) { InsightCard(insight: $0) }
                    group(.negativeRisk, report, title: "Atenção", kinds: [.negativeRisk, .anomaly])
                    recurrences(report)
                    group(.saving, report, title: "Sugestões de economia", kinds: [.saving])
                }
                Text("Estes insights são estimativas locais baseadas nos seus lançamentos. Não são recomendação financeira e não usam inteligência artificial nem servidores.")
                    .font(.footnote).foregroundStyle(Color.textTertiary)
                    .accessibilityIdentifier("insights.disclaimer")
            }
            .padding(.horizontal, Space.screenMargin)
            .padding(.vertical, Space.lg)
        }
        .refreshableStore()
        .background(Color.canvas)
        .navigationTitle("Insights")
        .inlineNavigationTitle()
        .accessibilityIdentifier("insights")
    }

    @ViewBuilder
    private func forecastHeader(_ f: BalanceForecast) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(f.days > 0 ? "Saldo previsto em \(Fmt.date(f.endDate))" : "Saldo hoje").font(.subheadline).foregroundStyle(Color.textSecondary)
            SplitAmount(value: f.projectedBalance, style: .large).accessibilityIdentifier("insights.forecast.amount")
            HStack(spacing: Space.sm) {
                Badge(text: "Confiança \(f.confidence.displayName)", tone: f.confidence == .high ? .ok : .neutral)
                if f.goesNegative { Badge(text: "Pode ficar negativo", tone: .danger) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("insights.forecast")
    }

    @ViewBuilder
    private func group(_ lead: InsightKind, _ report: InsightsReport, title: String, kinds: [InsightKind]) -> some View {
        let items = report.insights.filter { kinds.contains($0.kind) }
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(title)
            if items.isEmpty {
                Text(lead == .saving ? "Sem sugestões por enquanto." : "Nenhum alerta. Seus gastos estão dentro do padrão.")
                    .font(.subheadline).foregroundStyle(Color.textSecondary).padding(.horizontal, Space.xs)
                    .accessibilityIdentifier(lead == .saving ? "insights.savings.empty" : "insights.alerts.empty")
            } else {
                ForEach(items) { InsightCard(insight: $0) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(lead == .saving ? "insights.savings" : "insights.alerts")
    }

    @ViewBuilder
    private func recurrences(_ report: InsightsReport) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader("Assinaturas e recorrências")
            if report.recurrences.isEmpty {
                Text("Nenhuma recorrência detectada ainda. O app procura a mesma descrição repetida em intervalo regular.")
                    .font(.subheadline).foregroundStyle(Color.textSecondary).padding(.horizontal, Space.xs)
                    .accessibilityIdentifier("insights.subscriptions.empty")
            } else {
                ListGroup {
                    ForEach(Array(report.recurrences.prefix(10).enumerated()), id: \.element.id) { index, r in
                        ListRow(title: r.title, subtitle: "\(InsightsPresentation.frequencyText(r.frequency)), próxima em \(Fmt.date(r.nextExpectedDate))\(r.isDeclared ? "" : ", ainda não marcada como recorrente")") {
                            Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(Color.brandPrimary).frame(width: 28).accessibilityHidden(true)
                        } trailing: {
                            Text(store.money(r.typicalAmount)).font(.body).foregroundStyle(Color.textPrimary).monospacedDigit()
                        }
                        if index < min(report.recurrences.count, 10) - 1 { RowSeparator(inset: 56) }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("insights.subscriptions")
                ForEach(report.insights.filter { $0.kind == .subscription }) { InsightCard(insight: $0) }
            }
        }
    }
}

/// Um insight com o texto e o cálculo recolhível.
struct InsightCard: View {
    let insight: Insight
    @Environment(\.valuesHidden) private var hidden
    @State private var expanded = false

    private var tint: Color {
        switch insight.severity {
        case .critical: return .danger
        case .warning: return .warning
        case .info: return .brandPrimary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .top, spacing: Space.md) {
                Image(systemName: InsightsPresentation.symbol(for: insight.kind)).foregroundStyle(tint).frame(width: 28).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(insight.title).font(.headline).foregroundStyle(Color.textPrimary).fixedSize(horizontal: false, vertical: true)
                    Text(InsightsPresentation.text(insight.message, hidden: hidden)).font(.subheadline).foregroundStyle(Color.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button(expanded ? "Ocultar cálculo" : "Como calculamos") { expanded.toggle() }
                .buttonStyle(LinkButtonStyle())
                .accessibilityIdentifier("insights.explain.\(insight.id)")
            if expanded {
                VStack(alignment: .leading, spacing: Space.xs) {
                    ForEach(Array(insight.explanation.enumerated()), id: \.offset) { _, line in
                        Text(InsightsPresentation.text(line, hidden: hidden)).font(.footnote).foregroundStyle(Color.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityIdentifier("insights.explanation.\(insight.id)")
            }
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("insights.item.\(insight.id)")
    }
}

/// Cartão do Início: os dois insights mais importantes e um atalho para a tela completa.
struct InsightsHomeCard: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.valuesHidden) private var hidden

    var body: some View {
        let top = Array(store.insightsReport().insights.prefix(2))
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(title: "Insights") {
                Button("Ver todos") { router.showInsights() }
                    .buttonStyle(LinkButtonStyle())
                    .accessibilityIdentifier("home.insights.seeAll")
            }
            ListGroup {
                if top.isEmpty {
                    EmptyState(symbol: "lightbulb", title: "Sem insights ainda", message: "Eles aparecem conforme você registra lançamentos.")
                } else {
                    ForEach(Array(top.enumerated()), id: \.element.id) { index, insight in
                        Button { router.showInsights() } label: {
                            ListRow(title: insight.title, subtitle: InsightsPresentation.text(insight.message, hidden: hidden)) {
                                Image(systemName: InsightsPresentation.symbol(for: insight.kind))
                                    .foregroundStyle(insight.severity == .critical ? Color.danger : (insight.severity == .warning ? Color.warning : Color.brandPrimary))
                                    .frame(width: 28).accessibilityHidden(true)
                            } trailing: {
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.textTertiary).accessibilityHidden(true)
                            }
                        }
                        .buttonStyle(.plain)
                        if index < top.count - 1 { RowSeparator(inset: 56) }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.insights")
    }
}

#Preview("Insights") {
    NavigationStack { InsightsView() }.previewing(PreviewData.demo).environment(Router())
}

#Preview("Insights, escuro") {
    NavigationStack { InsightsView() }.previewing(PreviewData.demo, dark: true).environment(Router())
}

#Preview("Insights, vazio") {
    NavigationStack { InsightsView() }.previewing(PreviewData.empty).environment(Router())
}

#Preview("Insights, valores ocultos") {
    NavigationStack { InsightsView() }.environment(\.valuesHidden, true).previewing(PreviewData.demo).environment(Router())
}

#Preview("Início: cartão de insights") {
    InsightsHomeCard().padding().previewing(PreviewData.demo).environment(Router())
}
