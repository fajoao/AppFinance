import SwiftUI

/// Aba Planejar: alterna Orçamento, A pagar e Metas.
struct PlanView: View {
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        VStack(spacing: 0) {
            SegmentedTabs(options: [(PlanSection.budget, "Orçamento"), (.bills, "A pagar"), (.goals, "Metas"), (.more, "Mais")],
                          selection: $router.planSection, identifier: "plan.segment")
                .padding(.horizontal, Space.screenMargin)
                .padding(.vertical, Space.sm)
            switch router.planSection {
            case .budget: BudgetView()
            case .bills: BillsView()
            case .goals: GoalsView()
            case .more: MoreHubView()
            }
        }
        .background(Color.canvas)
        .navigationTitle("Planejar")
        .inlineNavigationTitle()
        .toolbar { ToolbarItem(placement: .trailingBar) { RefreshButton() } }
        .navigationDestination(for: MoreDestination.self) { destination in
            switch destination {
            case .debts: DebtsView()
            case .debtSimulator: DebtSimulatorView()
            case .cashFlow: CashFlowView()
            case .reports: ReportsView()
            case .tax: TaxView()
            case .netWorth: NetWorthView()
            case .family: FamilyView()
            case .categories: CategoriesView()
            case .insights: InsightsView()
            }
        }
    }
}

#Preview("Planejar") {
    NavigationStack { PlanView() }.previewing(PreviewData.demo).environment(Router())
}

#Preview("Planejar, escuro") {
    NavigationStack { PlanView() }.previewing(PreviewData.demo, dark: true).environment(Router())
}
