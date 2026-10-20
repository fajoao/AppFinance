import SwiftUI

/// wallet.cards: um bloco por cartão com fatura atual, limite e ações.
struct CardsView: View {
    @Environment(AppStore.self) private var store
    @State private var payTarget: InvoiceTarget?
    @State private var showsNewCard = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                if store.activeCards.isEmpty {
                    EmptyState(symbol: "creditcard", title: "Nenhum cartão",
                               message: "Cadastre um cartão com limite, fechamento e vencimento para acompanhar a fatura.",
                               actionTitle: "Novo cartão", actionIdentifier: "wallet.cards.add.empty") { showsNewCard = true }
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                } else {
                    ForEach(Array(store.cardOverviews.enumerated()), id: \.element.id) { index, overview in
                        CardBlock(overview: overview, index: index) {
                            payTarget = InvoiceTarget(cardId: overview.card.id, month: overview.current.invoice.month)
                        }
                    }
                    Button { showsNewCard = true } label: { Label("Novo cartão", systemImage: "plus") }
                        .buttonStyle(.secondary).accessibilityIdentifier("wallet.cards.add")
                }
            }
            .padding(.horizontal, Space.screenMargin)
            .padding(.vertical, Space.lg)
        }
        .refreshableStore()
        .sheet(item: $payTarget) { t in
            PayInvoiceSheet(cardId: t.cardId, month: t.month).presentationDetents([.large]).presentationCornerRadius(Radius.sheet)
        }
        .sheet(isPresented: $showsNewCard) {
            CardEditSheet().presentationDetents([.large]).presentationCornerRadius(Radius.sheet)
        }
        .accessibilityIdentifier("wallet.cards")
    }
}

struct CardBlock: View {
    @Environment(AppStore.self) private var store
    let overview: CardOverview
    let index: Int
    let onPay: () -> Void

    var body: some View {
        let s = overview.current
        let status = s.status
        let usedPct = overview.card.limit > 0 ? Int((overview.usedFraction * 100).rounded()) : 0
        HighlightBlock {
            HStack(alignment: .firstTextBaseline) {
                Text(overview.card.name).font(.headline).foregroundStyle(Color.textPrimary).lineLimit(2)
                Spacer(minLength: Space.sm)
                Badge(text: status.label, tone: status.tone)
            }
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Fatura atual").font(.footnote).foregroundStyle(Color.textSecondary)
                SplitAmount(value: s.remaining > 0 || s.total == 0 ? s.remaining : s.total, style: .large)
                Text("Fecha em \(DateText.dayMonthShort(s.invoice.closingDate)) · vence em \(DateText.dayMonthShort(s.invoice.dueDate))")
                    .font(.footnote).foregroundStyle(Color.textSecondary)
            }
            VStack(alignment: .leading, spacing: Space.xs) {
                ProgressBar(fraction: overview.usedFraction, tone: usedPct >= 100 ? .danger : (usedPct >= 80 ? .warning : .brand), marker: 0.8)
                HStack {
                    Text("Disponível \(store.money(overview.available))").lineLimit(1)
                    Spacer(minLength: Space.sm)
                    Text("Limite \(store.money(overview.card.limit))").lineLimit(1)
                }
                .font(.footnote).foregroundStyle(Color.textSecondary).monospacedDigit()
                if overview.futureCharges > 0 {
                    Text("Parcelas futuras: \(store.money(overview.futureCharges))")
                        .font(.footnote).foregroundStyle(Color.textSecondary).monospacedDigit()
                }
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: Space.sm) {
                NavigationLink(value: CardRoute(cardId: overview.card.id)) {
                    Text("Ver fatura").font(.headline).foregroundStyle(Color.brandPrimary)
                        .frame(maxWidth: .infinity, minHeight: Space.minTouchTarget)
                        .background(Color.brandSoft, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("wallet.cards.invoice.\(index)")
                Button(s.remaining > 0 ? "Pagar fatura" : "Fatura paga", action: onPay)
                    .buttonStyle(.primary)
                    .disabled(s.remaining <= 0)
                    .accessibilityIdentifier("wallet.cards.pay.\(index)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("wallet.cards.block.\(overview.card.name)")
    }
}

struct CardEditSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var limitText = ""
    @State private var closing = 5
    @State private var due = 12
    @State private var accountId: UUID?
    @State private var showErrors = false

    private var limit: Decimal? { Money.parse(limitText, style: .comma) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    LabeledField(label: "Nome do cartão", text: $name, prompt: "Ex.: Nubank Mastercard",
                                 error: showErrors && name.trimmingCharacters(in: .whitespaces).isEmpty ? "Dê um nome para o cartão." : nil,
                                 identifier: "wallet.cards.new.name")
                    LabeledField(label: "Limite", text: $limitText, prompt: "0,00",
                                 error: showErrors && (limit ?? 0) <= 0 ? "Informe um limite maior que zero." : nil,
                                 isDecimal: true, identifier: "wallet.cards.new.limit")
                    Stepper(value: $closing, in: 1...31) { Text("Fecha todo dia \(closing)").monospacedDigit() }
                        .accessibilityIdentifier("wallet.cards.new.closing")
                    Stepper(value: $due, in: 1...31) { Text("Vence todo dia \(due)").monospacedDigit() }
                        .accessibilityIdentifier("wallet.cards.new.due")
                    VStack(alignment: .leading, spacing: Space.sm) {
                        SectionHeader("Conta para pagar a fatura")
                        FlowLayout {
                            ForEach(store.activeAccounts) { a in
                                Chip(title: a.name, isSelected: accountId == a.id) { accountId = a.id }
                                    .accessibilityIdentifier("wallet.cards.new.account.\(a.name)")
                            }
                        }
                    }
                    Button("Criar cartão") {
                        guard let limit, limit > 0, !name.trimmingCharacters(in: .whitespaces).isEmpty else { showErrors = true; return }
                        if store.attempt({ try store.addCard(name: name, limit: limit, closingDay: closing, dueDay: due, paymentAccountId: accountId) }) {
                            store.show("Cartão criado."); dismiss()
                        }
                    }
                    .buttonStyle(.primary).accessibilityIdentifier("wallet.cards.new.save")
                }
                .padding(Space.screenMargin)
            }
            .scrollDismissesKeyboard(.interactively)
            .dismissesKeyboardOnTap()
            .background(Color.canvas)
            .navigationTitle("Novo cartão")
            .inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
        }
        .onAppear { accountId = accountId ?? store.activeAccounts.first?.id }
        .toastHost()
        .accessibilityIdentifier("wallet.cards.new")
    }
}

#Preview("Cartões") {
    NavigationStack { CardsView() }.previewing(PreviewData.demo)
}

#Preview("Cartões vazio") {
    NavigationStack { CardsView() }.previewing(PreviewData.empty)
}

#Preview("Cartões, escuro, texto grande") {
    NavigationStack { CardsView() }.previewing(PreviewData.demo, dark: true).dynamicTypeSize(.accessibility2)
}

#Preview("Novo cartão") {
    CardEditSheet().previewing(PreviewData.demo)
}
