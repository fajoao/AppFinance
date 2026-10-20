import SwiftUI

/// wallet.cardInvoice: abas de fatura (anterior, atual, futuras), total, datas e compras.
struct CardInvoiceView: View {
    @Environment(AppStore.self) private var store
    let cardId: UUID
    @State private var tab = 1
    @State private var payTarget: InvoiceTarget?

    var body: some View {
        Group {
            if let card = store.creditCards.first(where: { $0.id == cardId }) {
                let tabs = store.invoiceTabs(for: card)
                let summary = tabs[min(max(tab, 0), tabs.count - 1)]
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.xl) {
                        MonthPicker(inset: false)   // dentro da rolagem: acompanha o gesto de puxar e o título grande
                        tabBar(tabs, current: CreditCardEngine.currentInvoiceMonth(card: card, asOf: store.today))
                        header(summary, card: card)
                        purchases(summary)
                    }
                    .padding(.horizontal, Space.screenMargin)
                    .padding(.vertical, Space.lg)
                }
                .refreshableStore()
                .navigationTitle(card.name)
                .inlineNavigationTitle()
            } else {
                EmptyState(symbol: "creditcard", title: "Cartão não encontrado")
            }
        }
        .background(Color.canvas)
        .onChange(of: store.viewedMonth) { _, _ in tab = 1 }   // a aba 1 é sempre o mês visualizado
        .sheet(item: $payTarget) { t in
            PayInvoiceSheet(cardId: t.cardId, month: t.month).presentationDetents([.large]).presentationCornerRadius(Radius.sheet)
        }
        .accessibilityIdentifier("wallet.cardInvoice")
    }

    private func tabBar(_ tabs: [InvoiceSummary], current: YearMonth) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.sm) {
                ForEach(Array(tabs.enumerated()), id: \.offset) { i, s in
                    // Rótulos relativos à fatura vigente do cartão (hoje), não ao mês visualizado.
                    let label = DateText.monthShort(s.invoice.month) + (s.invoice.month == current ? " (atual)" : (s.invoice.month == current.previous ? " (anterior)" : ""))
                    Chip(title: label, isSelected: tab == i) { tab = i }
                        .accessibilityIdentifier("wallet.cardInvoice.tab.\(i)")
                }
            }
        }
    }

    private func header(_ s: InvoiceSummary, card: CreditCard) -> some View {
        HighlightBlock {
            HStack {
                Text("Fatura de \(DateText.monthNameLower(s.invoice.month))").font(.headline).foregroundStyle(Color.textPrimary)
                Spacer()
                Badge(text: s.status.label, tone: s.status.tone)
            }
            SplitAmount(value: s.total, style: .large).accessibilityIdentifier("wallet.cardInvoice.total")
            Text("Fecha em \(DateText.dayMonthShort(s.invoice.closingDate)) · vence em \(DateText.dayMonthShort(s.invoice.dueDate))")
                .font(.footnote).foregroundStyle(Color.textSecondary)
            if s.paidAmount > 0 {
                Text("Pago \(store.money(s.paidAmount)) · falta \(store.money(s.remaining))")
                    .font(.footnote).foregroundStyle(Color.textSecondary).monospacedDigit()
            }
            Button(s.remaining > 0 ? "Pagar fatura" : "Fatura paga") {
                payTarget = InvoiceTarget(cardId: card.id, month: s.invoice.month)
            }
            .buttonStyle(.primary)
            .disabled(s.remaining <= 0)
            .accessibilityIdentifier("wallet.cardInvoice.pay")
        }
    }

    private func purchases(_ s: InvoiceSummary) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader("Compras da fatura")
            ListGroup {
                if s.transactions.isEmpty {
                    EmptyState(symbol: "cart", title: "Nenhuma compra nesta fatura")
                } else {
                    ForEach(Array(s.transactions.enumerated()), id: \.element.id) { index, tx in
                        TransactionRow(transaction: tx, lookup: store.lookup, showsDate: true)
                        if index < s.transactions.count - 1 { RowSeparator(inset: 64) }
                    }
                }
            }
        }
    }
}

#Preview("Fatura") {
    NavigationStack { CardInvoiceView(cardId: PreviewData.demo.creditCards[0].id) }.previewing(PreviewData.demo)
}

#Preview("Fatura inexistente") {
    NavigationStack { CardInvoiceView(cardId: UUID()) }.previewing(PreviewData.empty)
}

#Preview("Fatura, escuro, texto grande") {
    let store = PreviewData.demo
    NavigationStack { CardInvoiceView(cardId: store.creditCards[1].id) }.previewing(store, dark: true).dynamicTypeSize(.accessibility2)
}
