import SwiftUI

/// reports.tax: resumo para o Imposto de Renda (rendimentos e despesas dedutíveis de saúde e educação).
struct TaxView: View {
    @Environment(AppStore.self) private var store
    @State private var year = 0
    @State private var memberId: UUID?
    @State private var pdfURL: URL?
    @State private var csvURL: URL?

    private var effectiveYear: Int { year == 0 ? FinanceCalendar.components(store.today).year : year }

    var body: some View {
        let summary = store.taxSummary(year: effectiveYear, memberId: memberId)
        let doc = store.taxDocument(summary, memberId: memberId)
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                controls
                totals(summary)
                incomeSection(summary)
                deductionSection(summary)
                Text("Este resumo é um auxílio e não substitui informes de rendimentos, recibos e notas fiscais. O limite de educação é por pessoa e muda por lei: confira as regras vigentes com a Receita Federal.")
                    .font(.footnote).foregroundStyle(Color.textSecondary)
                    .accessibilityIdentifier("reports.tax.disclaimer")
                NavigationLink { CategoriesView() } label: {
                    Label("Marcar categorias dedutíveis", systemImage: "checkmark.seal").frame(maxWidth: .infinity)
                }
                .buttonStyle(.secondary).accessibilityIdentifier("reports.tax.categories")
                if let pdfURL {
                    ShareLink(item: pdfURL) { Label("Exportar PDF", systemImage: "doc.richtext").frame(maxWidth: .infinity) }
                        .buttonStyle(.primary).accessibilityIdentifier("reports.tax.exportPDF")
                }
                if let csvURL {
                    ShareLink(item: csvURL) { Label("Exportar CSV", systemImage: "tablecells").frame(maxWidth: .infinity) }
                        .buttonStyle(.secondary).accessibilityIdentifier("reports.tax.exportCSV")
                }
            }
            .padding(.horizontal, Space.screenMargin)
            .padding(.vertical, Space.lg)
        }
        .background(Color.canvas)
        .navigationTitle("Imposto de Renda")
        .inlineNavigationTitle()
        .task(id: doc) {
            pdfURL = try? ReportPDFExporter.write(doc, baseName: "imposto-de-renda-\(summary.year)", today: store.today)
            csvURL = try? store.writeCSV(doc, baseName: "imposto-de-renda-\(summary.year)")
        }
        .accessibilityIdentifier("reports.tax")
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            Stepper(value: Binding(get: { effectiveYear }, set: { year = $0 }), in: 2000...(FinanceCalendar.components(store.today).year)) {
                Text("Ano-calendário \(String(effectiveYear))").font(.headline).foregroundStyle(Color.textPrimary)
            }
            .accessibilityIdentifier("reports.tax.year")
            if store.hasHousehold {
                Picker("Pessoa", selection: $memberId) {
                    Text("Toda a família").tag(UUID?.none)
                    ForEach(store.members) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                .accessibilityIdentifier("reports.tax.member")
            }
        }
    }

    private func totals(_ s: TaxSummary) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Total dedutível").font(.subheadline).foregroundStyle(Color.textSecondary)
                SplitAmount(value: s.totalDeductible, style: .large).accessibilityIdentifier("reports.tax.deductible")
            }
            ListGroup {
                line("Rendimentos no ano", s.totalIncome)
                RowSeparator()
                line("Saúde (sem limite)", s.healthTotal)
                RowSeparator()
                line("Educação (gasto)", s.educationTotal)
                RowSeparator()
                line("Educação dedutível (limite por pessoa)", s.educationDeductible)
                if s.educationExcess > 0 {
                    RowSeparator()
                    line("Educação acima do limite", s.educationExcess, color: .warning)
                }
            }
        }
    }

    private func line(_ label: String, _ value: Decimal, color: Color = .textSecondary) -> some View {
        ListRow(title: label) { EmptyView() } trailing: {
            Text(store.money(value)).font(.body).foregroundStyle(color).monospacedDigit()
        }
    }

    private func incomeSection(_ s: TaxSummary) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader("Rendimentos")
            if s.incomeLines.isEmpty {
                Text("Nenhuma receita registrada neste ano.").font(.subheadline).foregroundStyle(Color.textSecondary).padding(.horizontal, Space.xs)
            } else {
                ListGroup {
                    ForEach(Array(s.incomeLines.enumerated()), id: \.offset) { index, l in
                        line(store.lookup.categoryName(l.categoryId), l.total, color: .income)
                        if index < s.incomeLines.count - 1 { RowSeparator() }
                    }
                }
            }
        }
    }

    private func deductionSection(_ s: TaxSummary) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader("Despesas dedutíveis")
            if s.deductionLines.isEmpty {
                Text("Nenhuma despesa de saúde ou educação encontrada. Marque as categorias dedutíveis em Categorias.")
                    .font(.subheadline).foregroundStyle(Color.textSecondary).padding(.horizontal, Space.xs)
            } else {
                ListGroup {
                    ForEach(Array(s.deductionLines.enumerated()), id: \.offset) { index, l in
                        ListRow(title: store.lookup.categoryName(l.categoryId), subtitle: "\(l.kind.displayName), \(l.count) \(l.count == 1 ? "lançamento" : "lançamentos")") {
                            Image(systemName: l.kind == .health ? "heart" : "book").foregroundStyle(Color.brandPrimary).frame(width: 28).accessibilityHidden(true)
                        } trailing: { Text(store.money(l.total)).font(.body).monospacedDigit().foregroundStyle(Color.textSecondary) }
                        if index < s.deductionLines.count - 1 { RowSeparator(inset: 56) }
                    }
                }
            }
        }
    }
}

/// settings.categories: categorias, visibilidade (família) e marcação de despesas dedutíveis no IR.
struct CategoriesView: View {
    @Environment(AppStore.self) private var store
    @State private var showsNew = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                Text("Categorias de despesa marcadas como Saúde ou Educação entram no resumo do Imposto de Renda.")
                    .font(.footnote).foregroundStyle(Color.textSecondary)
                VStack(alignment: .leading, spacing: Space.sm) {
                    SectionHeader("Despesas")
                    ListGroup {
                        SeparatedRows(items: store.expenseCategories, inset: 56) { c in
                            ListRow(title: c.name, subtitle: subtitle(c)) {
                                CategoryIcon(category: c, lookup: store.lookup, size: 32)
                            } trailing: {
                                Menu {
                                    Picker("Dedutível no IR", selection: Binding(get: { c.taxKind }, set: { k in
                                        store.attempt { try store.setTaxKind(categoryId: c.id, k) }
                                    })) {
                                        Text("Não dedutível").tag(TaxDeductionKind?.none)
                                        ForEach(TaxDeductionKind.allCases, id: \.self) { Text($0.displayName).tag(TaxDeductionKind?.some($0)) }
                                    }
                                    if store.hasHousehold && (c.ownerId == nil || c.ownerId == store.viewerId) {
                                        Divider()
                                        Button(c.visibility == .shared ? "Tornar privada" : "Tornar compartilhada") {
                                            store.attempt { try store.setCategoryVisibility(categoryId: c.id, c.visibility == .shared ? .personal : .shared) }
                                        }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(Color.brandPrimary).frame(width: 44, height: 44)
                                }
                                .accessibilityLabel("Opções de \(c.name)")
                                .accessibilityIdentifier("settings.categories.menu.\(c.name)")
                            }
                        }
                    }
                }
                Button { showsNew = true } label: { Label("Nova categoria", systemImage: "plus") }
                    .buttonStyle(.secondary).accessibilityIdentifier("settings.categories.add")
            }
            .padding(.horizontal, Space.screenMargin)
            .padding(.vertical, Space.lg)
        }
        .background(Color.canvas)
        .navigationTitle("Categorias")
        .inlineNavigationTitle()
        .sheet(isPresented: $showsNew) { NewCategorySheet().presentationDetents([.medium, .large]).presentationCornerRadius(Radius.sheet) }
        .accessibilityIdentifier("settings.categories")
    }

    private func subtitle(_ c: Category) -> String? {
        var parts: [String] = []
        if let k = c.taxKind { parts.append("Dedutível: \(k.displayName)") }
        if c.visibility == .personal { parts.append("Privada") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

struct NewCategorySheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: CategoryKind = .expense
    @State private var isPrivate = false
    @State private var taxKind: TaxDeductionKind?
    @State private var showErrors = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    LabeledField(label: "Nome da categoria", text: $name, prompt: "Ex.: Pets",
                                 error: showErrors && name.trimmingCharacters(in: .whitespaces).isEmpty ? "Dê um nome para a categoria." : nil,
                                 identifier: "settings.categories.new.name")
                    Picker("Tipo", selection: $kind) {
                        Text("Despesa").tag(CategoryKind.expense); Text("Receita").tag(CategoryKind.income)
                    }
                    .pickerStyle(.segmented).accessibilityIdentifier("settings.categories.new.kind")
                    if kind == .expense {
                        VStack(alignment: .leading, spacing: Space.sm) {
                            SectionHeader("Dedutível no IR")
                            FlowLayout {
                                Chip(title: "Não", isSelected: taxKind == nil) { taxKind = nil }
                                ForEach(TaxDeductionKind.allCases, id: \.self) { k in
                                    Chip(title: k.displayName, isSelected: taxKind == k) { taxKind = k }
                                }
                            }
                        }
                    }
                    if store.hasHousehold {
                        Toggle("Categoria privada (só eu vejo)", isOn: $isPrivate).accessibilityIdentifier("settings.categories.new.private")
                    }
                    Button("Criar categoria") { save() }.buttonStyle(.primary).accessibilityIdentifier("settings.categories.new.save")
                }
                .padding(Space.screenMargin)
            }
            .dismissesKeyboardOnTap()
            .background(Color.canvas)
            .navigationTitle("Nova categoria")
            .inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
        }
        .toastHost()
    }

    private func save() {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { showErrors = true; return }
        if store.attempt({ _ = try store.addCategory(name: name, kind: kind, visibility: isPrivate ? .personal : .shared, taxKind: taxKind) }) {
            store.show("Categoria criada."); dismiss()
        }
    }
}

#Preview("Imposto de Renda") {
    NavigationStack { TaxView() }.previewing(PreviewData.demo)
}

#Preview("Categorias") {
    NavigationStack { CategoriesView() }.previewing(PreviewData.demo)
}

#Preview("Categorias, escuro") {
    NavigationStack { CategoriesView() }.previewing(PreviewData.demo, dark: true)
}
