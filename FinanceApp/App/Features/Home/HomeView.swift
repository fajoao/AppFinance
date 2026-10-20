import SwiftUI
import Charts

/// home.dashboard: saldo, resultado do mês, receitas × despesas, "Para onde foi" e próximos vencimentos.
struct HomeView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.valuesHidden) private var hidden

    var body: some View {
        // Resumo, gráficos e comparação seguem o mês visualizado. O saldo em contas, os próximos vencimentos e os
        // insights descrevem o "agora" e não mudam com o seletor.
        let month = store.viewedMonth
        let summary = store.summary(for: month)
        let previous = SummaryEngine.summary(month: month.previous, transactions: store.scopedTransactions)
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxxl) {
                MonthPicker(inset: false)   // dentro da rolagem: acompanha o gesto de puxar e o título grande
                hero
                if store.scopedTransactions.isEmpty {
                    EmptyState(symbol: "plus.circle", title: "Registre seu primeiro lançamento",
                               message: "Leva poucos toques. O app sugere a categoria pela descrição.",
                               actionTitle: "Novo lançamento", actionIdentifier: "home.empty.new") { router.presentNew() }
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                } else {
                    result(summary)
                    if summary.income == 0 && summary.expense == 0 {
                        EmptyState(symbol: "calendar", title: "Sem lançamentos em \(DateText.monthNameLower(month))",
                                   message: "Escolha outro mês ou registre um lançamento.",
                                   actionTitle: "Novo lançamento", actionIdentifier: "home.month.empty.new") { router.presentNew() }
                            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                            .accessibilityIdentifier("home.month.empty")
                    } else {
                        IncomeExpenseChart(summary: summary, previousMonth: month.previous)
                        WhereItWent(rows: DashboardModel.categoryRows(current: summary, previous: previous, lookup: store.lookup),
                                    previousMonth: month.previous)
                    }
                    if store.isViewingCurrentMonth { InsightsHomeCard() }
                }
                upcoming
            }
            .padding(.horizontal, Space.screenMargin)
            .padding(.vertical, Space.lg)
        }
        .refreshableStore()
        .background(Color.canvas)
        .navigationTitle("Início")
        .largeNavigationTitle()
        .toolbar {
            ToolbarItemGroup(placement: .trailingBar) {
                RefreshButton()
                if store.hasHousehold { profileMenu }
                Button { store.updatePreferences { $0.hideValues.toggle() } } label: {
                    Image(systemName: hidden ? "eye.slash" : "eye")
                }
                .accessibilityLabel(hidden ? "Mostrar valores" : "Ocultar valores")
                .accessibilityIdentifier("home.hideValues")
                NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
                    .accessibilityLabel("Ajustes")
                    .accessibilityIdentifier("home.settings")
            }
        }
        .accessibilityIdentifier("home.dashboard")
    }

    /// home.profile: troca de perfil e de visão (família × individual).
    private var profileMenu: some View {
        Menu {
            ForEach(store.members) { m in
                Button { store.setActiveMember(m.id) } label: {
                    Label(m.name, systemImage: m.id == store.activeMember?.id ? "checkmark" : m.role.symbol)
                }
            }
            if store.canViewFamily {
                Divider()
                Picker("Visão", selection: Binding(get: { store.preferences.viewScope }, set: { store.setViewScope($0) })) {
                    ForEach(ViewScopePreference.allCases) { Text($0.title).tag($0) }
                }
            }
        } label: {
            Image(systemName: store.isFamilyView ? "person.2" : "person.crop.circle")
        }
        .accessibilityLabel("Perfil: \(store.activeMember?.name ?? ""), visão \(store.isFamilyView ? "da família" : "individual")")
        .accessibilityIdentifier("home.profile")
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Saldo em contas").font(.subheadline).foregroundStyle(Color.textSecondary)
            CountUpSplitAmount(value: store.liquidBalance)
                .accessibilityIdentifier("home.balance")
        }
        .padding(.top, Space.sm)
    }

    private func result(_ s: MonthlySummary) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("Resultado do mês").font(.subheadline).foregroundStyle(Color.textSecondary)
            SplitAmount(value: s.balance, style: .large)
                .accessibilityIdentifier("home.result")
            Text("Receitas menos despesas em \(DateText.monthNameLower(store.viewedMonth))")
                .font(.footnote).foregroundStyle(Color.textTertiary)
        }
    }

    private var upcoming: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(title: "Próximos vencimentos") {
                Button("Ver todas") { router.show(plan: .bills) }
                    .buttonStyle(LinkButtonStyle())
                    .accessibilityIdentifier("home.bills.seeAll")
            }
            let bills = store.upcomingBills()
            ListGroup {
                if bills.isEmpty {
                    EmptyState(symbol: "checkmark.circle", title: "Nenhuma conta pendente", message: "Tudo em dia por aqui.")
                } else {
                    ForEach(Array(bills.enumerated()), id: \.element.id) { index, bill in
                        BillSummaryRow(bill: bill, today: store.today)
                        if index < bills.count - 1 { RowSeparator() }
                    }
                }
            }
            .accessibilityIdentifier("home.upcoming")
        }
    }
}

/// Linha compacta de conta a pagar (Início).
struct BillSummaryRow: View {
    let bill: BillItem
    let today: Date

    var body: some View {
        let status = BillsModel.status(of: bill, today: today)
        ListRow(title: bill.title, subtitle: "Vence em \(DateText.dayMonthShort(bill.dueDate))") {
            Image(systemName: bill.isInvoice ? "creditcard" : (bill.direction == .receivable ? "arrow.down.circle" : "doc.text"))
                .foregroundStyle(Color.brandPrimary).frame(width: 28)
                .accessibilityHidden(true)
        } trailing: {
            VStack(alignment: .trailing, spacing: Space.xs) {
                AmountText(bill.amount, sign: .none, role: bill.direction == .receivable ? .income : .positive)
                Badge(text: status.label, tone: status.tone)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Receitas × despesas

struct IncomeExpenseChart: View {
    @Environment(AppStore.self) private var store
    @Environment(\.valuesHidden) private var hidden
    let summary: MonthlySummary
    let previousMonth: YearMonth

    private struct Datum: Identifiable {
        let label: String
        let value: Double       // Decimal -> Double somente para desenhar o gráfico
        let previous: Double
        let color: Color
        var id: String { label }
    }

    private func plot(_ d: Decimal) -> Double { NSDecimalNumber(decimal: d).doubleValue }

    var body: some View {
        let data = [
            Datum(label: "Receitas", value: plot(summary.income), previous: plot(summary.comparison.previousIncome), color: .income),
            Datum(label: "Despesas", value: plot(summary.expense), previous: plot(summary.comparison.previousExpense), color: .neutral),
        ]
        let top = max(data.map { max($0.value, $0.previous) }.max() ?? 1, 1)
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader("Receitas × despesas")
            VStack(alignment: .leading, spacing: Space.md) {
                Chart(data) { d in
                    BarMark(x: .value("Valor", d.value), y: .value("Tipo", d.label), height: .fixed(22))
                        .foregroundStyle(d.color)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    BarMark(xStart: .value("Mês anterior", max(d.previous - top * 0.006, 0)),
                            xEnd: .value("Mês anterior", d.previous + top * 0.006),
                            y: .value("Tipo", d.label), height: .fixed(30))
                        .foregroundStyle(Color.textPrimary)
                }
                .chartXScale(domain: 0...(top * 1.04))
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 96)
                .accessibilityHidden(true)   // os números abaixo dizem o mesmo, em texto
                VStack(alignment: .leading, spacing: Space.sm) {
                    valueLine("Receitas", summary.income, summary.comparison.previousIncome, tone: .income)
                    valueLine("Despesas", summary.expense, summary.comparison.previousExpense, tone: .textPrimary)
                }
                HStack(spacing: Space.xs) {
                    Rectangle().fill(Color.textPrimary).frame(width: 3, height: 12).accessibilityHidden(true)
                    Text("Marca: \(DateText.monthNameLower(previousMonth))").font(.footnote).foregroundStyle(Color.textSecondary)
                }
            }
            .padding(Space.lg)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .accessibilityIdentifier("home.incomeExpense")
    }

    private func valueLine(_ title: String, _ value: Decimal, _ previous: Decimal, tone: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.subheadline).foregroundStyle(Color.textSecondary)
            Spacer(minLength: Space.sm)
            VStack(alignment: .trailing, spacing: 0) {
                Text(store.money(value)).font(.body.weight(.medium)).monospacedDigit()
                    .foregroundStyle(hidden ? Color.textPrimary : tone)
                Text("\(DateText.monthShort(previousMonth)) \(store.money(previous))").font(.footnote).monospacedDigit()
                    .foregroundStyle(Color.textSecondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hidden ? "\(title), valores ocultos"
                            : "\(title) \(MoneyDisplay.spoken(value)), mês anterior \(MoneyDisplay.spoken(previous))")
    }
}

// MARK: - Para onde foi

struct WhereItWent: View {
    @Environment(\.valuesHidden) private var hidden
    @Environment(AppStore.self) private var store
    let rows: [CategoryRow]
    let previousMonth: YearMonth

    private func plot(_ d: Decimal) -> Double { NSDecimalNumber(decimal: d).doubleValue }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader("Para onde foi")
            if rows.isEmpty {
                EmptyState(symbol: "chart.bar", title: "Sem despesas neste mês")
                    .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            } else {
                let top = max(rows.map { max(plot($0.amount), plot($0.previousAmount)) }.max() ?? 1, 1)
                VStack(alignment: .leading, spacing: Space.lg) {
                    Chart(rows) { r in
                        BarMark(x: .value("Gasto", plot(r.amount)), y: .value("Categoria", r.name), height: .fixed(18))
                            .foregroundStyle(color(for: r))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                            .annotation(position: .top, alignment: .leading, spacing: 2) {
                                Text(r.name).font(.caption).foregroundStyle(Color.textSecondary)
                            }
                        if r.previousAmount > 0 {
                            BarMark(xStart: .value("Mês anterior", max(plot(r.previousAmount) - top * 0.006, 0)),
                                    xEnd: .value("Mês anterior", plot(r.previousAmount) + top * 0.006),
                                    y: .value("Categoria", r.name), height: .fixed(26))
                                .foregroundStyle(Color.textPrimary)
                        }
                    }
                    .chartXScale(domain: 0...(top * 1.04))
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .frame(height: CGFloat(rows.count) * 46 + 8)
                    .accessibilityHidden(true)   // a lista abaixo traz os mesmos dados em texto
                    VStack(alignment: .leading, spacing: Space.md) {
                        ForEach(rows) { r in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(r.name).font(.subheadline).foregroundStyle(Color.textPrimary)
                                    Spacer(minLength: Space.sm)
                                    Text(store.money(r.amount)).font(.subheadline.weight(.medium)).monospacedDigit()
                                        .foregroundStyle(Color.textPrimary)
                                }
                                Text(verbatim: "\(NSDecimalNumber(decimal: r.percentOfTotal.rounded(scale: 0)).intValue)% do total · "
                                     + DashboardModel.deltaText(r.deltaPercent, previous: previousMonth))
                                    .font(.footnote).foregroundStyle(Color.textSecondary).monospacedDigit()
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .padding(Space.lg)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            }
        }
        .accessibilityIdentifier("home.whereItWent")
    }

    private func color(for r: CategoryRow) -> Color {
        let category = r.categoryId.flatMap { store.lookup.categories[$0] }
        return Color.category(CategoryStyle.token(for: category, in: store.lookup))
    }
}

#Preview("Início com dados") {
    NavigationStack { HomeView() }.previewing(PreviewData.demo).environment(Router())
}

#Preview("Início vazio") {
    NavigationStack { HomeView() }.previewing(PreviewData.empty).environment(Router())
}

#Preview("Início, valores grandes e negativos") {
    NavigationStack { HomeView() }.previewing(PreviewData.extremes).environment(Router())
}

#Preview("Início, escuro, valores ocultos") {
    NavigationStack { HomeView() }.previewing(PreviewData.demo, dark: true)
        .environment(Router()).environment(\.valuesHidden, true)
}

#Preview("Início, texto grande") {
    NavigationStack { HomeView() }.previewing(PreviewData.demo).environment(Router()).dynamicTypeSize(.accessibility2)
}
