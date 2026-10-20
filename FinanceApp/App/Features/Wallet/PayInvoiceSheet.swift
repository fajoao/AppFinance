import SwiftUI

/// wallet.payInvoice: total, mínimo (15%) ou outro valor, conta de origem e aviso de saldo.
struct PayInvoiceSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let cardId: UUID
    let month: YearMonth
    @State private var model = PayInvoiceModel(remaining: 0)
    @State private var loaded = false

    private var summary: InvoiceSummary? { store.invoiceSummary(cardId: cardId, month: month) }

    private var selectedBalance: Decimal? {
        model.accountId.flatMap { id in store.accounts.first { $0.id == id }.map(store.balance(of:)) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let summary {
                    VStack(alignment: .leading, spacing: Space.xl) {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text("Fatura de \(DateText.monthNameLower(month))").font(.subheadline).foregroundStyle(Color.textSecondary)
                            SplitAmount(value: summary.remaining, style: .large).accessibilityIdentifier("wallet.payInvoice.total")
                            Text("Vence em \(DateText.dayMonthShort(summary.invoice.dueDate))").font(.footnote).foregroundStyle(Color.textSecondary)
                        }
                        options
                        accounts
                        if model.leavesRevolvingBalance {
                            Label("Pagar menos que o total joga o restante no rotativo, com juros altos.", systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote).foregroundStyle(Color.warning)
                                .accessibilityIdentifier("wallet.payInvoice.revolvingWarning")
                        }
                        if model.isInsufficient(accountBalance: selectedBalance) {
                            Label("Saldo insuficiente na conta escolhida. O pagamento deixará a conta negativa.", systemImage: "exclamationmark.circle.fill")
                                .font(.footnote).foregroundStyle(Color.danger)
                                .accessibilityIdentifier("wallet.payInvoice.insufficient")
                        }
                        Button("Pagar \(model.amount.map { MoneyDisplay.text($0) } ?? "R$\u{00A0}0,00")") { pay() }
                            .buttonStyle(.primary)
                            .disabled(!model.canPay(accountBalance: selectedBalance))
                            .accessibilityIdentifier("wallet.payInvoice.confirm")
                    }
                    .padding(Space.screenMargin)
                } else {
                    EmptyState(symbol: "creditcard", title: "Fatura não encontrada")
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .dismissesKeyboardOnTap()
            .background(Color.canvas)
            .navigationTitle("Pagar fatura")
            .inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
        }
        .onAppear {
            guard !loaded, let summary else { return }
            loaded = true
            let card = store.creditCards.first { $0.id == cardId }
            model = PayInvoiceModel(remaining: summary.remaining,
                                    accountId: card?.paymentAccountId ?? store.activeAccounts.first?.id)
        }
        .toastHost()
        .accessibilityIdentifier("wallet.payInvoice")
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader("Quanto pagar")
            ListGroup {
                optionRow("Valor total", MoneyDisplay.text(model.remaining), .full, id: "full")
                RowSeparator()
                optionRow("Pagamento mínimo (15%)", MoneyDisplay.text(model.minimum), .minimum, id: "minimum")
                RowSeparator()
                optionRow("Outro valor", nil, .custom, id: "custom")
            }
            if model.option == .custom {
                LabeledField(label: "Valor", text: $model.customText, prompt: "0,00", error: model.amountError,
                             isDecimal: true, identifier: "wallet.payInvoice.custom.amount")
            }
        }
    }

    private func optionRow(_ title: String, _ value: String?, _ option: PayInvoiceModel.Option, id: String) -> some View {
        Button { model.option = option } label: {
            ListRow(title: title, subtitle: value) {
                Image(systemName: model.option == option ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(model.option == option ? Color.brandPrimary : Color.textTertiary).accessibilityHidden(true)
            } trailing: { EmptyView() }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(model.option == option ? .isSelected : [])
        .accessibilityIdentifier("wallet.payInvoice.option.\(id)")
    }

    private var accounts: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader("Pagar com")
            ListGroup {
                SeparatedRows(items: store.activeAccounts) { a in
                    Button { model.accountId = a.id } label: {
                        ListRow(title: a.name, subtitle: "Saldo \(store.money(store.balance(of: a)))") { EmptyView() } trailing: {
                            if model.accountId == a.id { Image(systemName: "checkmark").foregroundStyle(Color.brandPrimary).accessibilityHidden(true) }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(model.accountId == a.id ? .isSelected : [])
                    .accessibilityIdentifier("wallet.payInvoice.account.\(a.name)")
                }
            }
        }
    }

    private func pay() {
        guard let accountId = model.accountId, let amount = model.amount else { return }
        let isFull = amount == model.remaining
        if store.attempt({ try store.payInvoice(cardId: cardId, month: month, amount: isFull ? nil : amount, from: accountId) }) {
            Haptics.success()
            store.show(isFull ? "Fatura paga." : "Pagamento registrado.")
            dismiss()
        }
    }
}

#Preview("Pagar fatura") {
    let store = PreviewData.demo
    let card = store.creditCards[0]
    PayInvoiceSheet(cardId: card.id, month: store.cardOverview(card).current.invoice.month).previewing(store)
}

#Preview("Pagar fatura, escuro, texto grande") {
    let store = PreviewData.demo
    let card = store.creditCards[1]
    PayInvoiceSheet(cardId: card.id, month: store.cardOverview(card).current.invoice.month)
        .previewing(store, dark: true).dynamicTypeSize(.accessibility2)
}

#Preview("Pagar fatura inexistente") {
    PayInvoiceSheet(cardId: UUID(), month: YearMonth(year: 2026, month: 10)).previewing(PreviewData.empty)
}
