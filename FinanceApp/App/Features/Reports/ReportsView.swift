import SwiftUI
import Charts

/// reports.main: relatório por período, categoria, membro e conta, com exportação em PDF e CSV.
struct ReportsView: View {
    @Environment(AppStore.self) private var store
    @State private var period: ReportPeriod = .thisMonth
    @State private var customFrom = Date()
    @State private var customTo = Date()
    @State private var categoryId: UUID?
    @State private var memberId: UUID?
    @State private var accountId: UUID?
    @State private var pdfURL: URL?
    @State private var csvURL: URL?
    @State private var didSetup = false

    private var result: ReportResult {
        store.report(period: period, custom: (FinanceCalendar.normalize(customFrom), FinanceCalendar.normalize(customTo)),
                     categoryIds: categoryId.map { [$0] } ?? [], memberIds: memberId.map { [$0] } ?? [],
                     accountIds: accountId.map { [$0] } ?? [])
    }

    var body: some View {
        let r = result
        let doc = store.reportDocument(r)
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                MonthPicker(inset: false)   // dentro da rolagem: acompanha o gesto de puxar e o título grande
                periodChips
                filters
                summary(r)
                if r.count == 0 {
                    EmptyState(symbol: "doc.text.magnifyingglass", title: "Nada neste período",
                               message: "Mude o período ou limpe os filtros para ver lançamentos.")
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                } else {
                    if r.byMonth.count > 1 { monthChart(r) }
                    group("Por categoria", rows: r.byCategory, name: { store.lookup.categoryName($0) }, id: "category")
                    if store.hasHousehold { group("Por membro", rows: r.byMember, name: { store.lookup.memberName($0) }, id: "member") }
                    group("Por conta", rows: r.byAccount, name: { $0.flatMap { store.lookup.accounts[$0]?.name } ?? "Cartão ou sem conta" }, id: "account")
                }
                exportButtons
            }
            .padding(.horizontal, Space.screenMargin)
            .padding(.vertical, Space.lg)
        }
        .refreshableStore()
        .background(Color.canvas)
        .navigationTitle("Relatórios")
        .inlineNavigationTitle()
        .task(id: doc) { await prepareExports(doc) }
        .onAppear {
            guard !didSetup else { return }
            didSetup = true
            customFrom = store.today.addingTimeInterval(-30 * 86_400); customTo = store.today
        }
        .accessibilityIdentifier("reports.main")
    }

    // MARK: Partes

    private var periodChips: some View {
        FlowLayout {
            ForEach(ReportPeriod.allCases) { p in
                Chip(title: p.title(viewed: store.viewedMonth, today: store.today), isSelected: period == p) { period = p }
                    .accessibilityIdentifier("reports.period.\(p.rawValue)")
            }
        }
    }

    @ViewBuilder
    private var filters: some View {
        if period == .custom {
            HStack {
                DatePicker("De", selection: $customFrom, displayedComponents: .date).accessibilityIdentifier("reports.from")
                DatePicker("Até", selection: $customTo, displayedComponents: .date).accessibilityIdentifier("reports.to")
            }
            .environment(\.calendar, FinanceCalendar.calendar).environment(\.timeZone, FinanceCalendar.calendar.timeZone)
        }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.sm) {
                Menu {
                    Picker("Categoria", selection: $categoryId) {
                        Text("Todas as categorias").tag(UUID?.none)
                        ForEach(store.categories.filter { $0.parentId == nil }) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                } label: { ChipLabel(title: categoryId.map { store.lookup.categoryName($0) } ?? "Categoria", systemImage: "tag", isSelected: categoryId != nil) }
                    .accessibilityIdentifier("reports.filter.category")
                if store.hasHousehold {
                    Menu {
                        Picker("Membro", selection: $memberId) {
                            Text("Todos os membros").tag(UUID?.none)
                            ForEach(store.members) { Text($0.name).tag(UUID?.some($0.id)) }
                        }
                    } label: { ChipLabel(title: memberId.map { store.lookup.memberName($0) } ?? "Membro", systemImage: "person", isSelected: memberId != nil) }
                        .accessibilityIdentifier("reports.filter.member")
                }
                Menu {
                    Picker("Conta", selection: $accountId) {
                        Text("Todas as contas").tag(UUID?.none)
                        ForEach(store.scopedAccounts) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                } label: { ChipLabel(title: accountId.flatMap { store.lookup.accounts[$0]?.name } ?? "Conta", systemImage: "building.columns", isSelected: accountId != nil) }
                    .accessibilityIdentifier("reports.filter.account")
            }
        }
    }

    private func summary(_ r: ReportResult) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Resultado do período").font(.subheadline).foregroundStyle(Color.textSecondary)
                SplitAmount(value: r.net, style: .large).accessibilityIdentifier("reports.net")
            }
            HStack(spacing: Space.md) {
                stat("Receitas", r.income, .income)
                stat("Despesas", r.expense, .textPrimary)
            }
        }
    }

    private func stat(_ label: String, _ value: Decimal, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.footnote).foregroundStyle(Color.textSecondary)
            Text(store.money(value)).font(.headline).foregroundStyle(color).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(Space.md).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func monthChart(_ r: ReportResult) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader("Mês a mês")
            Chart {
                ForEach(r.byMonth, id: \.month) { m in
                    BarMark(x: .value("Mês", DateText.monthShort(m.month)), y: .value("Valor", NSDecimalNumber(decimal: m.income).doubleValue))
                        .foregroundStyle(by: .value("Tipo", "Receitas")).position(by: .value("Tipo", "Receitas"))
                    BarMark(x: .value("Mês", DateText.monthShort(m.month)), y: .value("Valor", NSDecimalNumber(decimal: m.expense).doubleValue))
                        .foregroundStyle(by: .value("Tipo", "Despesas")).position(by: .value("Tipo", "Despesas"))
                }
            }
            .chartForegroundStyleScale(["Receitas": Color.income, "Despesas": Color.neutral])
            .chartYAxis(.hidden)
            .frame(height: 160)
            .padding(Space.md)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Gráfico de receitas e despesas por mês, \(r.byMonth.count) meses.")
        }
    }

    private func group(_ title: String, rows: [GroupTotal], name: @escaping (UUID?) -> String, id: String) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(title)
            ListGroup {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, g in
                    VStack(alignment: .leading, spacing: Space.xs) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(name(g.id)).font(.body).foregroundStyle(Color.textPrimary).lineLimit(2)
                            Spacer(minLength: Space.sm)
                            Text(store.money(g.expense > 0 ? g.expense : g.income)).font(.body.weight(.medium))
                                .foregroundStyle(g.expense > 0 ? Color.textPrimary : Color.income).monospacedDigit()
                        }
                        if g.expense > 0 {
                            ProgressBar(fraction: NSDecimalNumber(decimal: g.percentOfExpense).doubleValue / 100, tone: .neutral, height: 6)
                            Text("\(Fmt.percent(g.percentOfExpense, scale: 1)) das despesas, \(g.count) \(g.count == 1 ? "lançamento" : "lançamentos")")
                                .font(.footnote).foregroundStyle(Color.textSecondary)
                        } else {
                            Text("receita, \(g.count) \(g.count == 1 ? "lançamento" : "lançamentos")").font(.footnote).foregroundStyle(Color.textSecondary)
                        }
                    }
                    .padding(Space.lg)
                    .accessibilityElement(children: .combine)
                    if index < rows.count - 1 { RowSeparator() }
                }
            }
            .accessibilityIdentifier("reports.group.\(id)")
        }
    }

    private var exportButtons: some View {
        VStack(spacing: Space.sm) {
            if let pdfURL {
                ShareLink(item: pdfURL) { Label("Exportar PDF", systemImage: "doc.richtext").frame(maxWidth: .infinity) }
                    .buttonStyle(.primary).accessibilityIdentifier("reports.exportPDF")
            }
            if let csvURL {
                ShareLink(item: csvURL) { Label("Exportar CSV", systemImage: "tablecells").frame(maxWidth: .infinity) }
                    .buttonStyle(.secondary).accessibilityIdentifier("reports.exportCSV")
            }
        }
    }

    private func prepareExports(_ doc: ReportDocument) async {
        pdfURL = try? ReportPDFExporter.write(doc, baseName: "relatorio", today: store.today)
        csvURL = try? store.writeCSV(doc, baseName: "relatorio")
    }
}

#Preview("Relatórios") {
    NavigationStack { ReportsView() }.previewing(PreviewData.demo)
}

#Preview("Relatórios, escuro, texto grande") {
    NavigationStack { ReportsView() }.previewing(PreviewData.demo, dark: true).dynamicTypeSize(.accessibility2)
}
