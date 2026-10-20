import Foundation
import Observation

enum MainTab: Hashable { case home, transactions, new, plan, wallet }
enum PlanSection: Hashable, CaseIterable { case budget, bills, goals, more }
enum WalletSection: Hashable, CaseIterable { case accounts, cards, investments }

/// Destinos empurrados a partir de Planejar > Mais (também usados por `-startScreen`).
enum MoreDestination: Hashable {
    case debts, debtSimulator, cashFlow, reports, tax, netWorth, family, categories, insights
}

/// Estado de navegação compartilhado (abas, sub-telas e sheet de novo lançamento). Só UI, sem regra financeira.
@MainActor @Observable
final class Router {
    var tab: MainTab = .home
    var planSection: PlanSection = .budget
    var walletSection: WalletSection = .accounts
    var planPath: [MoreDestination] = []
    var showsNewTransaction = false
    var newTransactionType: TransactionType = .expense
    /// Data inicial do novo lançamento (nil = hoje).
    var newTransactionDate: Date?
    /// Abre a leitura de QR/comprovante assim que o novo lançamento aparece (`-startScreen scan`).
    var opensScanner = false
    var showsOpenFinance = false

    func presentNew(type: TransactionType = .expense, date: Date? = nil) {
        newTransactionType = type
        newTransactionDate = date
        showsNewTransaction = true
    }

    func showInsights() { show(plan: .more); planPath = [.insights] }

    func show(plan section: PlanSection) { planSection = section; tab = .plan }
    func show(wallet section: WalletSection) { walletSection = section; tab = .wallet }

    /// Aplica `-startScreen` (somente para capturas e testes).
    func apply(_ options: LaunchOptions) {
        switch options.startScreen {
        case "home": tab = .home
        case "transactions": tab = .transactions
        case "new": presentNew()
        case "plan.budget": show(plan: .budget)
        case "plan.bills": show(plan: .bills)
        case "plan.goals": show(plan: .goals)
        case "wallet.accounts": show(wallet: .accounts)
        case "wallet.cards": show(wallet: .cards)
        case "wallet.investments": show(wallet: .investments)
        case "plan.more": show(plan: .more)
        case "plan.debts": show(plan: .more); planPath = [.debts]
        case "plan.debts.simulator": show(plan: .more); planPath = [.debts, .debtSimulator]
        case "plan.cashflow": show(plan: .more); planPath = [.cashFlow]
        case "reports": show(plan: .more); planPath = [.reports]
        case "tax": show(plan: .more); planPath = [.tax]
        case "wallet.networth": show(plan: .more); planPath = [.netWorth]
        case "family": show(plan: .more); planPath = [.family]
        case "insights": showInsights()
        case "scan": opensScanner = true; presentNew()
        case "settings.openfinance": showsOpenFinance = true
        case "settings.categories": show(plan: .more); planPath = [.categories]
        default: break
        }
    }
}
