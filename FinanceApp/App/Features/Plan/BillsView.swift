import SwiftUI

struct InvoiceTarget: Identifiable, Hashable {
    let cardId: UUID
    let month: YearMonth
    var id: String { "\(cardId.uuidString)-\(month.label)" }
}

/// plan.bills: calendário do mês com pontos por status, totais e lista filtrável por dia.
struct BillsView: View {
    @Environment(AppStore.self) private var store
    @Environment(Router.self) private var router
    @State private var selectedDay: Date?
    @State private var payTarget: InvoiceTarget?

    /// O calendário segue o mês global do seletor (`MonthPicker`), inclusive meses futuros com o que o Core já projeta.
    private var shownMonth: YearMonth { store.viewedMonth }

    var body: some View {
        let all = store.billItems
        let inMonth = BillsModel.items(all, in: shownMonth)
        let totals = BillsModel.totals(inMonth)
        let visible = selectedDay.map { day in inMonth.filter { FinanceCalendar.isSameDay($0.dueDate, day) } } ?? inMonth
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                MonthPicker(inset: false)   // dentro da rolagem: acompanha o gesto de puxar e o título grande
                calendar(bills: inMonth)
                HStack(spacing: Space.md) {
                    totalBlock("A pagar", totals.toPay, id: "plan.bills.totalPay", role: .positive)
                    totalBlock("A receber", totals.toReceive, id: "plan.bills.totalReceive", role: .income)
                }
                list(visible)
                Button { router.presentNew(type: .expense, date: FinanceCalendar.addDays(store.today, 1)) } label: {
                    Label("Nova conta a pagar", systemImage: "plus")
                }
                .buttonStyle(.secondary)
                .accessibilityIdentifier("plan.bills.add")
            }
            .padding(.horizontal, Space.screenMargin)
            .padding(.vertical, Space.lg)
        }
        .refreshableStore()
        .onChange(of: store.viewedMonth) { _, _ in selectedDay = nil }
        .sheet(item: $payTarget) { target in
            PayInvoiceSheet(cardId: target.cardId, month: target.month)
                .presentationDetents([.large])
                .presentationCornerRadius(Radius.sheet)
        }
        .accessibilityIdentifier("plan.bills")
    }

    // MARK: Calendário

    private func calendar(bills: [BillItem]) -> some View {
        let weeks = BillsModel.calendarWeeks(for: shownMonth)
        return VStack(spacing: Space.sm) {
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    Text(DateText.weekdays1[i]).font(.caption.weight(.semibold)).foregroundStyle(Color.textSecondary)
                        .frame(maxWidth: .infinity).accessibilityHidden(true)
                }
            }
            ForEach(weeks.indices, id: \.self) { w in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { d in
                        if let day = weeks[w][d] { dayCell(day, bills: bills) } else { Color.clear.frame(maxWidth: .infinity, minHeight: 46) }
                    }
                }
            }
            legend
        }
        .padding(Space.md)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }

    private func dayCell(_ day: Date, bills: [BillItem]) -> some View {
        let number = FinanceCalendar.components(day).day
        let dots = BillsModel.dots(on: day, bills: bills, today: store.today)
        let isSelected = selectedDay.map { FinanceCalendar.isSameDay($0, day) } ?? false
        let isToday = FinanceCalendar.isSameDay(day, store.today)
        let count = bills.filter { FinanceCalendar.isSameDay($0.dueDate, day) }.count
        return Button { selectedDay = isSelected ? nil : day } label: {
            VStack(spacing: 3) {
                Text("\(number)").font(.callout.weight(isToday ? .bold : .regular)).monospacedDigit()
                    .foregroundStyle(isSelected ? Color.brandPrimary : Color.textPrimary)
                HStack(spacing: 2) {
                    ForEach(Array(dots.prefix(3).enumerated()), id: \.offset) { _, tone in
                        Circle().fill(tone.fill).frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(isSelected ? Color.brandSoft : Color.clear, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(isToday ? Color.brandPrimary : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(number) de \(DateText.monthNameLower(shownMonth))" + (count > 0 ? ", \(count) \(count == 1 ? "conta" : "contas")" : ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("plan.bills.day.\(number)")
    }

    private var legend: some View {
        FlowLayout(spacing: Space.md) {
            legendItem("Atrasada", .danger); legendItem("Vence logo", .warning); legendItem("Pendente", .neutral)
            legendItem("A receber", .brand); legendItem("Paga", .ok)
        }
        .padding(.top, Space.xs)
    }

    private func legendItem(_ text: String, _ tone: BillStatus.Tone) -> some View {
        HStack(spacing: Space.xs) {
            Circle().fill(tone.fill).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(text).font(.caption).foregroundStyle(Color.textSecondary)
        }
    }

    private func totalBlock(_ title: String, _ value: Decimal, id: String, role: AmountRole) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title).font(.footnote).foregroundStyle(Color.textSecondary)
            Text(store.money(value)).font(.title3.weight(.semibold)).monospacedDigit()
                .foregroundStyle(store.preferences.hideValues ? Color.textPrimary : role.color)
                .lineLimit(1).minimumScaleFactor(0.6)
        }
        .padding(Space.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(id)
    }

    // MARK: Lista

    @ViewBuilder
    private func list(_ bills: [BillItem]) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(title: selectedDay.map { "Dia \(FinanceCalendar.components($0).day)" } ?? "Neste mês") {
                if selectedDay != nil {
                    Button("Ver mês todo") { selectedDay = nil }.buttonStyle(LinkButtonStyle())
                        .accessibilityIdentifier("plan.bills.clearDay")
                }
            }
            ListGroup {
                if bills.isEmpty {
                    EmptyState(symbol: "calendar.badge.checkmark", title: "Nenhuma conta aqui",
                               message: selectedDay == nil ? "Nada vence neste mês." : "Nada vence neste dia.")
                } else {
                    ForEach(Array(bills.enumerated()), id: \.element.id) { index, bill in
                        BillRow(bill: bill, today: store.today) { act(bill) }
                        if index < bills.count - 1 { RowSeparator() }
                    }
                }
            }
        }
    }

    private func act(_ bill: BillItem) {
        if let cardId = bill.cardId, let m = bill.invoiceMonth {
            payTarget = InvoiceTarget(cardId: cardId, month: m)
        } else if let id = bill.transactionId {
            if store.attempt({ try store.markPaid(transactionId: id) }) {
                Haptics.success()
                store.show(bill.direction == .receivable ? "Recebimento registrado." : "Conta paga.")
            }
        }
    }
}

/// Linha de conta com status e ação ("Pagar", "Recebi").
struct BillRow: View {
    @Environment(AppStore.self) private var store
    let bill: BillItem
    let today: Date
    let action: () -> Void

    var body: some View {
        let status = BillsModel.status(of: bill, today: today)
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(alignment: .firstTextBaseline, spacing: Space.md) {
                Image(systemName: bill.isInvoice ? "creditcard" : (bill.direction == .receivable ? "arrow.down.circle" : "doc.text"))
                    .foregroundStyle(Color.brandPrimary).frame(width: 28).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(bill.title).font(.body).foregroundStyle(Color.textPrimary).lineLimit(2)
                    Text("Vence em \(DateText.dayMonthShort(bill.dueDate))").font(.footnote).foregroundStyle(Color.textSecondary)
                }
                Spacer(minLength: Space.sm)
                AmountText(bill.amount, sign: .none, role: bill.direction == .receivable ? .income : .positive)
            }
            HStack {
                Badge(text: status.label, tone: status.tone)
                Spacer()
                if !bill.isPaid {
                    Button(bill.direction == .receivable ? "Recebi" : (bill.isInvoice ? "Pagar fatura" : "Pagar"), action: action)
                        .buttonStyle(LinkButtonStyle())
                        .accessibilityIdentifier("plan.bills.pay.\(bill.title)")
                }
            }
            .padding(.leading, 40)
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("plan.bills.row")
    }
}

#Preview("A pagar") {
    NavigationStack { BillsView() }.previewing(PreviewData.demo).environment(Router())
}

#Preview("A pagar vazio") {
    NavigationStack { BillsView() }.previewing(PreviewData.empty).environment(Router())
}

#Preview("A pagar, escuro, texto grande") {
    NavigationStack { BillsView() }.previewing(PreviewData.demo, dark: true).environment(Router())
        .dynamicTypeSize(.accessibility2)
}

#Preview("Linhas de conta: atrasada, longa, paga") {
    let store = PreviewData.demo
    ListGroup {
        BillRow(bill: BillItem(id: "1", title: "Energia (Enel) com um nome bastante longo para quebrar linha", amount: dec("189.40"),
                               dueDate: FinanceCalendar.date(2026, 10, 15), direction: .payable, isPaid: false), today: PreviewData.today) {}
        RowSeparator()
        BillRow(bill: BillItem(id: "2", title: "Studio Ipê", amount: dec("1800"), dueDate: FinanceCalendar.date(2026, 10, 30),
                               direction: .receivable, isPaid: false), today: PreviewData.today) {}
        RowSeparator()
        BillRow(bill: BillItem(id: "3", title: "Aluguel", amount: dec("1850"), dueDate: FinanceCalendar.date(2026, 10, 5),
                               direction: .payable, isPaid: true), today: PreviewData.today) {}
    }
    .padding()
    .background(Color.canvas)
    .previewing(store)
}
