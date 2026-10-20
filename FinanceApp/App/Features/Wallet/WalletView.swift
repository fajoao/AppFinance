import SwiftUI

struct CardRoute: Hashable { let cardId: UUID }

/// Aba Carteira: alterna Contas e Cartões; a fatura abre por push.
struct WalletView: View {
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        VStack(spacing: 0) {
            SegmentedTabs(options: [(WalletSection.accounts, "Contas"), (.cards, "Cartões"), (.investments, "Investimentos")],
                          selection: $router.walletSection, identifier: "wallet.segment")
                .padding(.horizontal, Space.screenMargin)
                .padding(.vertical, Space.sm)
            switch router.walletSection {
            case .accounts: AccountsView()
            case .cards: CardsView()
            case .investments: InvestmentsView()
            }
        }
        .background(Color.canvas)
        .toolbar { ToolbarItem(placement: .trailingBar) { RefreshButton() } }
        .navigationTitle("Carteira")
        .inlineNavigationTitle()
        .navigationDestination(for: CardRoute.self) { CardInvoiceView(cardId: $0.cardId) }
    }
}

// MARK: - Contas

/// wallet.accounts: patrimônio total e contas agrupadas por tipo com subtotal.
struct AccountsView: View {
    @Environment(AppStore.self) private var store
    @State private var showsNewAccount = false
    @State private var reconciling: Account?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Patrimônio total").font(.subheadline).foregroundStyle(Color.textSecondary)
                    SplitAmount(value: store.totalWealth, style: .large).accessibilityIdentifier("wallet.accounts.total")
                }
                if store.activeAccounts.isEmpty {
                    EmptyState(symbol: "building.columns", title: "Nenhuma conta",
                               message: "Adicione sua conta corrente, poupança ou carteira.",
                               actionTitle: "Nova conta", actionIdentifier: "wallet.accounts.add.empty") { showsNewAccount = true }
                        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
                }
                ForEach(store.accountGroups) { group in
                    VStack(alignment: .leading, spacing: Space.sm) {
                        SectionHeader(title: group.type.displayName) {
                            Text(store.money(group.subtotal)).font(.footnote.weight(.semibold)).foregroundStyle(Color.textSecondary).monospacedDigit()
                        }
                        ListGroup {
                            ForEach(Array(group.accounts.enumerated()), id: \.element.id) { index, account in
                                Button { reconciling = account } label: {
                                    ListRow(title: account.name, subtitle: "Toque para conciliar") {
                                        Image(systemName: account.type.symbol).foregroundStyle(Color.brandPrimary).frame(width: 28)
                                            .accessibilityHidden(true)
                                    } trailing: { AmountText(balance: store.balance(of: account)) }
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("wallet.accounts.row.\(account.name)")
                                if index < group.accounts.count - 1 { RowSeparator(inset: 56) }
                            }
                        }
                    }
                    .accessibilityIdentifier("wallet.accounts.group.\(group.type.rawValue)")
                }
                if !store.activeAccounts.isEmpty {
                    Button { showsNewAccount = true } label: { Label("Nova conta", systemImage: "plus") }
                        .buttonStyle(.secondary).accessibilityIdentifier("wallet.accounts.add")
                }
            }
            .padding(.horizontal, Space.screenMargin)
            .padding(.vertical, Space.lg)
        }
        .refreshableStore()
        .sheet(isPresented: $showsNewAccount) {
            AccountEditSheet().presentationDetents([.medium, .large]).presentationCornerRadius(Radius.sheet)
        }
        .sheet(item: $reconciling) { account in
            ReconcileSheet(accountId: account.id).presentationDetents([.medium, .large]).presentationCornerRadius(Radius.sheet)
        }
        .accessibilityIdentifier("wallet.accounts")
    }
}

struct AccountEditSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var type: AccountType = .checking
    @State private var balanceText = ""
    @State private var showErrors = false

    private var balance: Decimal? { balanceText.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : Money.parse(balanceText, style: .comma) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    LabeledField(label: "Nome da conta", text: $name, prompt: "Ex.: Itaú",
                                 error: showErrors && name.trimmingCharacters(in: .whitespaces).isEmpty ? "Dê um nome para a conta." : nil,
                                 identifier: "wallet.accounts.new.name")
                    FlowLayout {
                        ForEach(AccountType.allCases, id: \.self) { t in
                            Chip(title: t.displayName, systemImage: t.symbol, isSelected: type == t) { type = t }
                                .accessibilityIdentifier("wallet.accounts.new.type.\(t.rawValue)")
                        }
                    }
                    LabeledField(label: "Saldo de hoje", text: $balanceText, prompt: "0,00",
                                 error: balance == nil ? "Valor inválido. Exemplo: 1.250,00" : nil,
                                 isDecimal: true, identifier: "wallet.accounts.new.balance")
                    Button("Criar conta") {
                        guard let balance, !name.trimmingCharacters(in: .whitespaces).isEmpty else { showErrors = true; return }
                        if store.attempt({ try store.addAccount(name: name, type: type, balance: balance) }) { dismiss() }
                    }
                    .buttonStyle(.primary).accessibilityIdentifier("wallet.accounts.new.save")
                }
                .padding(Space.screenMargin)
            }
            .scrollDismissesKeyboard(.interactively)
            .dismissesKeyboardOnTap()
            .background(Color.canvas)
            .navigationTitle("Nova conta")
            .inlineNavigationTitle()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
        }
        .toastHost()
        .accessibilityIdentifier("wallet.accounts.new")
    }
}

/// Conciliação: compara o saldo do app com o do extrato e cria o lançamento de ajuste.
struct ReconcileSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let accountId: UUID
    @State private var statementText = ""

    var body: some View {
        NavigationStack {
            if let account = store.accounts.first(where: { $0.id == accountId }) {
                let statement = Money.parse(statementText, style: .comma)
                let diff = statement.map { store.reconciliationDifference(account: account, statementBalance: $0) }
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.xl) {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text("Saldo no app").font(.subheadline).foregroundStyle(Color.textSecondary)
                            SplitAmount(value: store.balance(of: account), style: .large)
                        }
                        LabeledField(label: "Saldo no extrato do banco", text: $statementText, prompt: "0,00", isDecimal: true,
                                     identifier: "wallet.reconcile.statement")
                        if let diff {
                            if diff == 0 {
                                Label("Tudo certo: o saldo confere com o extrato.", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(Color.income).accessibilityIdentifier("wallet.reconcile.ok")
                            } else {
                                Text(diff > 0 ? "Faltam \(store.money(diff)) em entradas no app." : "Há \(store.money(-diff)) a mais de entradas no app.")
                                    .font(.subheadline).foregroundStyle(Color.warning)
                                Button("Criar ajuste de \(store.money(diff, sign: .natural))") {
                                    if let statement, store.attempt({ try store.reconcile(account: account, statementBalance: statement) }) {
                                        store.show("Conta conciliada."); dismiss()
                                    }
                                }
                                .buttonStyle(.primary).accessibilityIdentifier("wallet.reconcile.adjust")
                            }
                        }
                    }
                    .padding(Space.screenMargin)
                }
                .scrollDismissesKeyboard(.interactively)
            .dismissesKeyboardOnTap()
                .background(Color.canvas)
                .navigationTitle("Conciliar \(account.name)")
                .inlineNavigationTitle()
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } } }
            } else {
                EmptyState(symbol: "questionmark.circle", title: "Conta não encontrada")
            }
        }
        .toastHost()
        .accessibilityIdentifier("wallet.reconcile")
    }
}

// MARK: - Previews

#Preview("Contas") {
    NavigationStack { AccountsView() }.previewing(PreviewData.demo)
}

#Preview("Contas, valores grandes e negativos") {
    NavigationStack { AccountsView() }.previewing(PreviewData.extremes)
}

#Preview("Contas vazio") {
    NavigationStack { AccountsView() }.previewing(PreviewData.fresh)
}

#Preview("Contas, escuro, texto grande") {
    NavigationStack { AccountsView() }.previewing(PreviewData.demo, dark: true).dynamicTypeSize(.accessibility2)
}

#Preview("Nova conta") {
    AccountEditSheet().previewing(PreviewData.demo)
}

#Preview("Conciliar") {
    let store = PreviewData.demo
    ReconcileSheet(accountId: store.accounts[0].id).previewing(store)
}
