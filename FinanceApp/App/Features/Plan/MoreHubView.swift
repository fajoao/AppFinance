import SwiftUI

/// plan.more: porta de entrada de dívidas, fluxo de caixa, relatórios, IR, patrimônio, família e categorias.
struct MoreHubView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.sm) {
                    SectionHeader("Planejamento")
                    ListGroup {
                        row(.insights, "Insights", "Gastos atípicos, previsão do saldo, assinaturas e economia", "lightbulb", "plan.more.insights")
                        RowSeparator(inset: 56)
                        row(.debts, "Dívidas e simulador", store.debts.isEmpty ? "Cadastre e compare estratégias de quitação" : "Total \(store.money(store.totalDebt))",
                            "creditcard.trianglebadge.exclamationmark", "plan.more.debts")
                        RowSeparator(inset: 56)
                        row(.cashFlow, "Fluxo de caixa projetado", "Saldo previsto em 30, 60 e 90 dias", "chart.line.uptrend.xyaxis", "plan.more.cashflow")
                    }
                }
                VStack(alignment: .leading, spacing: Space.sm) {
                    SectionHeader("Relatórios e impostos")
                    ListGroup {
                        row(.reports, "Relatórios", "Por período, categoria, membro e conta. Exporta PDF e CSV", "doc.text.magnifyingglass", "plan.more.reports")
                        RowSeparator(inset: 56)
                        row(.tax, "Resumo para o Imposto de Renda", "Rendimentos e despesas dedutíveis do ano", "building.columns", "plan.more.tax")
                    }
                }
                VStack(alignment: .leading, spacing: Space.sm) {
                    SectionHeader("Patrimônio e família")
                    ListGroup {
                        row(.netWorth, "Patrimônio líquido", "Ativos menos dívidas e faturas, mês a mês", "scalemass", "plan.more.networth")
                        RowSeparator(inset: 56)
                        row(.family, "Família", store.hasHousehold ? "\(store.household?.name ?? "Família"), \(store.members.count) \(store.members.count == 1 ? "pessoa" : "pessoas")" : "Perfis, divisão de despesas, mesada",
                            "person.2", "plan.more.family")
                        RowSeparator(inset: 56)
                        row(.categories, "Categorias", "Visibilidade e despesas dedutíveis no IR", "tag", "plan.more.categories")
                    }
                }
            }
            .padding(.horizontal, Space.screenMargin)
            .padding(.vertical, Space.lg)
        }
        .refreshableStore()
        .accessibilityIdentifier("plan.more")
    }

    private func row(_ destination: MoreDestination, _ title: String, _ subtitle: String, _ symbol: String, _ id: String) -> some View {
        NavigationLink(value: destination) {
            ListRow(title: title, subtitle: subtitle) {
                Image(systemName: symbol).foregroundStyle(Color.brandPrimary).frame(width: 28).accessibilityHidden(true)
            } trailing: {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.textTertiary).accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}

#Preview("Mais") {
    NavigationStack { MoreHubView() }.previewing(PreviewData.demo)
}

#Preview("Mais, escuro") {
    NavigationStack { MoreHubView() }.previewing(PreviewData.demo, dark: true)
}
