import SwiftUI
import AppKit

// Renderização offscreen (ImageRenderer) das telas no macOS, SOMENTE para conferir layout sem Xcode.
// Não é o iOS: ScrollView/List são substituídos por pilhas (Shims.swift) e Toggle/Picker/DatePicker não são desenhados.

// Pasta de saída recebida pelo script (primeiro argumento).
let outdir = (CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "build/macos-preview") + "/"

@MainActor func render<V: View>(_ view: V, _ name: String, dark: Bool = false, size: CGSize = CGSize(width: 390, height: 844)) {
    Harness.dark = dark
    let content = view
        .frame(width: size.width, height: size.height)
        .environment(\.colorScheme, dark ? .dark : .light)
        .background(Color.canvas)
    let r = ImageRenderer(content: content)
    r.scale = 2
    guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { print("FALHOU \(name)"); return }
    try? png.write(to: URL(fileURLWithPath: outdir + name + ".png"))
    print("ok \(name)")
}

MainActor.assumeIsolated {
    _ = NSApplication.shared
    let demo = PreviewData.demo
    let router = Router()
    @MainActor func env<V: View>(_ v: V, _ store: AppStore) -> some View { v.environment(store).environment(router).environment(\.valuesHidden, store.preferences.hideValues) }
    render(env(HomeView(), demo), "home")
    render(env(HomeView(), demo), "home-dark", dark: true)
    render(env(TransactionsView(), demo), "transactions")
    render(env(NewTransactionView(), demo), "new")
    render(env(BudgetView(), demo), "budget")
    render(env(BillsView(), demo), "bills")
    render(env(GoalsView(), demo), "goals")
    render(env(AccountsView(), demo), "accounts")
    render(env(CardsView(), demo), "cards")
    render(env(OnboardingFlow(), PreviewData.fresh), "onboarding")
    render(env(SettingsView(), demo), "settings")
    render(env(LockView(), demo), "lock")
    render(env(PayInvoiceSheet(cardId: demo.creditCards[0].id, month: demo.cardOverview(demo.creditCards[0]).current.invoice.month), demo), "payinvoice")
    render(env(CardInvoiceView(cardId: demo.creditCards[0].id), demo), "invoice")
    var hiddenPrefs = PreviewData.demo
    hiddenPrefs.updatePreferences { $0.hideValues = true }
    render(env(HomeView(), hiddenPrefs), "home-hidden")
    render(env(AccountsView(), PreviewData.extremes), "accounts-extremes")
    render(env(NewTransactionView(type: .transfer), demo), "new-transfer", dark: true)
    render(env(FiltersSheet(filter: .constant(TransactionFilter())), demo), "filters")
    render(env(CardInvoiceView(cardId: demo.creditCards[1].id), demo), "invoice2", dark: true)
    render(env(ReconcileSheet(accountId: demo.accounts[0].id), demo), "reconcile")

    // Fase 2
    let family = PreviewData.family
    render(env(MoreHubView(), demo), "more")
    render(env(DebtsView(), demo), "debts")
    render(env(DebtSimulatorView(), demo), "debt-simulator")
    render(env(DebtSimulatorView(), demo), "debt-simulator-dark", dark: true)
    render(env(CashFlowView(), demo), "cashflow")
    render(env(ReportsView(), demo), "reports")
    render(env(TaxView(), demo), "tax")
    render(env(CategoriesView(), demo), "categories")
    render(env(InvestmentsView(), demo), "investments")
    render(env(InvestmentsView(), demo), "investments-dark", dark: true)
    render(env(NetWorthView(), demo), "networth")
    render(env(FamilyView(), family), "family")
    render(env(FamilyView(), family), "family-dark", dark: true)
    render(env(SettlementView(), family), "settlement")
    render(env(AllowanceView(), family), "allowance")
    render(env(ApprovalsView(), family), "approvals")
    render(env(SplitExpenseSheet(), family), "split")
    render(env(GoalHistorySheet(goalId: demo.goals[0].id), demo), "goal-history")
    render(env(GoalEditSheet(goalId: demo.goals[0].id), demo), "goal-edit")
    render(env(NewTransactionView(editing: demo.transactions.first { $0.type == .expense && !$0.isInvoicePayment }?.id), demo), "edit-transaction")
    render(env(PinSettingsView(), demo), "pin-settings")
    render(env(SyncSettingsView(), demo), "sync-settings")
    render(env(DebtFormSheet(debtId: nil), demo), "debt-form")
}
