import SwiftUI
import Charts

/// plan.debts: dívidas cadastradas, total e acesso ao simulador.
struct DebtsView: View {
    @Environment(AppStore.self) private var store
    @State private var editing: DebtTarget?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Total devido").font(.subheadline).foregroundStyle(Color.textSecondary)
                    SplitAmount(value: store.totalDebt, style: .large, color: store.debts.isEmpty ? Color.textPrimary : Color.danger)
                        .accessibilityIdentifier("plan.debts.total")
                }
                if store.debts.isEmpty {
                    EmptyState(symbol: "checkmark.seal", title: "Nenhuma dívida cadastrada",
                               message: "Cadastre empréstimos, financiamentos e o rotativo do cartão para comparar formas de quitar.",
                               actionTitle: "Nova dívida", actionIdentifier: "plan.debts.add.empty") { editing = .new }
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                } else {
                    ListGroup {
                        SeparatedRows(items: store.debts) { debt in
                            Button { editing = .edit(debt.id) } label: {
                                ListRow(title: debt.name,
                                        subtitle: "\(Fmt.monthlyRate(debt.monthlyInterestRate)), mínimo \(store.money(debt.minimumPayment))"
                                            + (debt.dueDay.map { ", vence dia \($0)" } ?? "")) {
                                    Image(systemName: "creditcard").foregroundStyle(Color.danger).frame(width: 28).accessibilityHidden(true)
                                } trailing: { AmountText(balance: -debt.balance) }
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("plan.debts.row.\(debt.name)")
                        }
                    }
                    NavigationLink { DebtSimulatorView() } label: {
                        Label("Simular quitação", systemImage: "chart.line.downtrend.xyaxis").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("plan.debts.simulate")
                    Button { editing = .new } label: { Label("Nova dívida", systemImage: "plus") }
                        .buttonStyle(.secondary).accessibilityIdentifier("plan.debts.add")
                }
            }
            .padding(.horizontal, Space.screenMargin)
            .padding(.vertical, Space.lg)
        }
        .background(Color.canvas)
        .navigationTitle("Dívidas")
        .inlineNavigationTitle()
        .sheet(item: $editing) { target in
            DebtFormSheet(debtId: target.debtId)
                .presentationDetents([.large]).presentationCornerRadius(Radius.sheet)
        }
        .accessibilityIdentifier("plan.debts")
    }
}

enum DebtTarget: Identifiable, Hashable {
    case new, edit(UUID)
    var id: String { switch self { case .new: return "new"; case .edit(let id): return id.uuidString } }
    var debtId: UUID? { if case .edit(let id) = self { return id } else { return nil } }
}

/// plan.debts.form: nome, saldo, juros ao mês, pagamento mínimo e dia de vencimento.
struct DebtFormSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let debtId: UUID?
    @State private var draft = DebtDraft()
    @State private var showErrors = false
    @State private var confirmDelete = false
    @State private var didSetup = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    LabeledField(label: "Nome", text: $draft.name, prompt: "Ex.: Empréstimo pessoal",
                                 error: showErrors ? draft.nameError : nil, identifier: "plan.debts.form.name")
                    LabeledField(label: "Saldo devedor", text: $draft.balanceText, prompt: "0,00",
                                 error: showErrors ? draft.balanceError : nil, isDecimal: true, identifier: "plan.debts.form.balance")
                    LabeledField(label: "Juros ao mês (%)", text: $draft.rateText, prompt: "Ex.: 2,5",
                                 error: showErrors ? draft.rateError : nil, isDecimal: true, identifier: "plan.debts.form.rate")
                    LabeledField(label: "Pagamento mínimo", text: $draft.minimumText, prompt: "0,00",
                                 error: showErrors ? draft.minimumError : nil, isDecimal: true, identifier: "plan.debts.form.minimum")
                    LabeledField(label: "Dia do vencimento (opcional)", text: $draft.dueDayText, prompt: "1 a 31",
                                 error: showErrors ? draft.dueDayError : nil, isDecimal: true, identifier: "plan.debts.form.dueDay")
                    Button(debtId == nil ? "Cadastrar dívida" : "Salvar alterações") { save() }
                        .buttonStyle(.primary).accessibilityIdentifier("plan.debts.form.save")
                    if debtId != nil {
                        Button("Excluir dívida") { confirmDelete = true }
                            .buttonStyle(LinkButtonStyle(tone: .danger)).frame(maxWidth: .infinity)
                            .accessibilityIdentifier("plan.debts.form.delete")
                    }
                }
                .padding(Space.screenMargin)
            }
            .scrollDismissesKeyboard(.interactively)
            .dismissesKeyboardOnTap()
            .background(Color.canvas)
            .navigationTitle(debtId == nil ? "Nova dívida" : "Editar dívida")
            .inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
            .confirmationDialog("Excluir esta dívida?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Excluir", role: .destructive) {
                    if let debtId, store.attempt({ try store.deleteDebt(id: debtId) }) { dismiss() }
                }
            }
        }
        .onAppear {
            guard !didSetup else { return }
            didSetup = true
            if let debtId, let d = store.debts.first(where: { $0.id == debtId }) { draft = DebtDraft(editing: d) }
        }
        .toastHost()
        .accessibilityIdentifier("plan.debts.form")
    }

    private func save() {
        guard draft.isValid else { showErrors = true; return }
        if store.attempt({ try store.saveDebt(draft) }) { store.show("Dívida salva."); dismiss() }
    }
}

/// plan.debts.simulator: avalanche × bola de neve, com prazo, juros e gráfico de comparação.
struct DebtSimulatorView: View {
    @Environment(AppStore.self) private var store
    @State private var budgetText = ""
    @State private var didSetup = false

    private var budget: Decimal? { Money.parse(budgetText, style: .comma) }
    private var minimum: Decimal { DebtSimulation.minimumBudget(store.debts) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                if store.debts.isEmpty {
                    EmptyState(symbol: "tray", title: "Cadastre uma dívida para simular",
                               message: "O simulador compara pagar primeiro a dívida de maiores juros (avalanche) ou a de menor saldo (bola de neve).")
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                } else {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        LabeledField(label: "Quanto você paga por mês, no total", text: $budgetText, prompt: "0,00",
                                     isDecimal: true, identifier: "plan.debts.simulator.budget")
                        Text("Mínimo para cobrir todas as dívidas: \(store.money(minimum)). O que passar disso acelera a quitação.")
                            .font(.footnote).foregroundStyle(Color.textSecondary)
                    }
                    result
                }
            }
            .padding(.horizontal, Space.screenMargin)
            .padding(.vertical, Space.lg)
        }
        .scrollDismissesKeyboard(.interactively)
        .dismissesKeyboardOnTap()
        .background(Color.canvas)
        .navigationTitle("Simulador de quitação")
        .inlineNavigationTitle()
        .onAppear {
            guard !didSetup else { return }
            didSetup = true
            let suggested = (minimum * Decimal(string: "1.2", locale: nil)!).rounded(scale: 0, mode: .up)
            budgetText = MoneyDisplay.number(suggested)
        }
        .accessibilityIdentifier("plan.debts.simulator")
    }

    @ViewBuilder
    private var result: some View {
        if let budget {
            switch Result(catching: { try store.simulateDebts(monthlyBudget: budget) }) {
            case .success(let c): comparison(c)
            case .failure(let e):
                Label((e as? FinanceError)?.description ?? "Não foi possível simular.", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline).foregroundStyle(Color.danger).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("plan.debts.simulator.error")
            }
        } else {
            Text("Digite um valor para comparar.").font(.subheadline).foregroundStyle(Color.textSecondary)
        }
    }

    private func comparison(_ c: DebtComparison) -> some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            if !c.isFeasible {
                Label(c.onlyOneFeasible == nil ? "Com este valor os juros superam os pagamentos e a dívida não zera. Aumente o valor mensal."
                                               : "Com este valor uma das estratégias não consegue quitar: os juros de uma dívida maior superam o que sobra para ela.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline).foregroundStyle(Color.danger).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("plan.debts.simulator.infeasible")
            }
            Text(summaryText(c))
                .font(.headline).foregroundStyle(Color.textPrimary).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("plan.debts.simulator.summary")
            strategyCard(.avalanche, c)
            strategyCard(.snowball, c)
            chart(c)
        }
    }

    private func summaryText(_ c: DebtComparison) -> String {
        if let only = c.onlyOneFeasible {
            return only == .avalanche ? "Só a avalanche (maiores juros primeiro) consegue quitar tudo com este valor."
                                      : "Só a bola de neve (menores saldos primeiro) consegue quitar tudo com este valor."
        }
        if !c.isFeasible { return "Nenhuma estratégia quita com este valor. Aumente o valor mensal." }
        return c.interestSavedByAvalanche > 0
            ? "Pagar primeiro os maiores juros (avalanche) economiza \(store.money(c.interestSavedByAvalanche)) em juros."
            : "As duas estratégias custam o mesmo em juros. A bola de neve quita as menores dívidas primeiro e costuma motivar mais."
    }

    private func strategyCard(_ s: PayoffStrategy, _ c: DebtComparison) -> some View {
        let r = c.result(for: s)
        let title = s == .avalanche ? "Avalanche" : "Bola de neve"
        let hint = s == .avalanche ? "Maiores juros primeiro" : "Menores saldos primeiro"
        return HighlightBlock {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(Color.textPrimary)
                    Text(hint).font(.footnote).foregroundStyle(Color.textSecondary)
                }
                Spacer()
                if c.recommended == s { Badge(text: c.isFeasible ? "Menos juros" : "Recomendada", tone: .ok) }
            }
            if r.feasible {
                row("Prazo", "\(DebtSimulation.durationText(months: r.months))" + (c.payoffDate(s, today: store.today).map { ", até \(Fmt.monthYearShort($0))" } ?? ""))
            } else {
                row("Prazo", "Não quita")
            }
            row("Juros pagos", store.money(r.totalInterest))
            row("Total pago", store.money(r.totalPaid))
            if !r.payoffOrder.isEmpty {
                let names = r.payoffOrder.compactMap { id in store.debts.first { $0.id == id }?.name }
                Text("Ordem: " + names.joined(separator: " → ")).font(.footnote).foregroundStyle(Color.textSecondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan.debts.simulator.\(s.rawValue)")
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).font(.subheadline).foregroundStyle(Color.textSecondary)
            Spacer(minLength: Space.md)
            Text(value).font(.body.weight(.medium)).foregroundStyle(Color.textPrimary).monospacedDigit().multilineTextAlignment(.trailing)
        }
    }

    private func chart(_ c: DebtComparison) -> some View {
        let names = [PayoffStrategy.avalanche: "Avalanche", .snowball: "Bola de neve"]
        return VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader("Saldo devedor mês a mês")
            Chart(c.chartPoints) { p in
                LineMark(x: .value("Mês", p.month), y: .value("Saldo", NSDecimalNumber(decimal: p.balance).doubleValue))
                    .foregroundStyle(by: .value("Estratégia", names[p.strategy] ?? ""))
                    .lineStyle(StrokeStyle(lineWidth: 2.5, dash: p.strategy == .snowball ? [6, 4] : []))
            }
            .chartForegroundStyleScale(["Avalanche": Color.brandPrimary, "Bola de neve": Color.warning])
            .chartXAxisLabel("Meses")
            .chartYAxis(.hidden)
            .frame(height: 200)
            .padding(Space.md)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Gráfico do saldo devedor. Avalanche quita em \(c.avalanche.months) meses e bola de neve em \(c.snowball.months) meses.")
            .accessibilityIdentifier("plan.debts.simulator.chart")
        }
    }
}

#Preview("Dívidas") {
    NavigationStack { DebtsView() }.previewing(PreviewData.demo)
}

#Preview("Dívidas vazio") {
    NavigationStack { DebtsView() }.previewing(PreviewData.empty)
}

#Preview("Simulador") {
    NavigationStack { DebtSimulatorView() }.previewing(PreviewData.demo)
}

#Preview("Simulador, escuro, texto grande") {
    NavigationStack { DebtSimulatorView() }.previewing(PreviewData.demo, dark: true).dynamicTypeSize(.accessibility2)
}

#Preview("Nova dívida") {
    DebtFormSheet(debtId: nil).previewing(PreviewData.demo)
}
