import SwiftUI

// Tokens "Cédula" (Design/tokens.json). As cores vêm do Asset Catalog (Assets.xcassets/Colors),
// gerado por scripts/gen-colorsets.py, com valores para claro e escuro.

extension Color {
    // Fundos
    static let canvas = Color("canvas")
    static let surface = Color("surface")
    static let surfaceRaised = Color("surfaceRaised")
    static let sunken = Color("sunken")
    // Texto
    static let textPrimary = Color("textPrimary")
    static let textSecondary = Color("textSecondary")
    static let textTertiary = Color("textTertiary")
    static let textOnBrand = Color("textOnBrand")
    static let textOnDanger = Color("textOnDanger")
    // Linhas
    static let separator = Color("separator")
    static let border = Color("border")
    // Marca
    static let brandPrimary = Color("brandPrimary")
    static let brandSoft = Color("brandSoft")
    static let focus = Color("focus")
    // Semânticas
    static let income = Color("income")
    static let incomeSoft = Color("incomeSoft")
    static let expense = Color("expense")
    static let transfer = Color("transfer")
    static let warning = Color("warning")
    static let warningFill = Color("warningFill")
    static let warningSoft = Color("warningSoft")
    static let danger = Color("danger")
    static let dangerSoft = Color("dangerSoft")
    static let neutral = Color("neutral")

    /// Cor de categoria pelo nome do token (`catMoradia`...). "income" para categorias de receita.
    static func category(_ token: String) -> Color { Color(token) }
}

/// Espaçamento (base 4pt).
enum Space {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 24
    static let xxxl: CGFloat = 32
    static let huge: CGFloat = 48
    static let screenMargin: CGFloat = 20
    static let rowMinHeight: CGFloat = 52
    static let minTouchTarget: CGFloat = 44
}

/// Raios (quanto maior o contêiner, maior o raio).
enum Radius {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 14
    static let lg: CGFloat = 20
    static let sheet: CGFloat = 28
    static let full: CGFloat = 999
}

/// Duração das animações; respeitar Reduzir Movimento nas Views.
enum Motion {
    static let fast: Double = 0.15
    static let standard: Double = 0.25
    static let sheet: Double = 0.35
}

// MARK: - Tom semântico

extension BillStatus.Tone {
    var text: Color {
        switch self {
        case .ok: return .income
        case .danger: return .danger
        case .warning: return .warning
        case .brand: return .brandPrimary
        case .neutral: return .textSecondary
        }
    }
    var soft: Color {
        switch self {
        case .ok: return .incomeSoft
        case .danger: return .dangerSoft
        case .warning: return .warningSoft
        case .brand: return .brandSoft
        case .neutral: return .sunken
        }
    }
    /// Cor de preenchimento (pontos e barras).
    var fill: Color {
        switch self {
        case .ok: return .income
        case .danger: return .danger
        case .warning: return .warningFill
        case .brand: return .brandPrimary
        case .neutral: return .neutral
        }
    }
}

extension AmountRole {
    var color: Color {
        switch self {
        case .income: return .income
        case .expense, .positive: return .textPrimary
        case .transfer: return .transfer
        case .negative: return .danger
        case .zero: return .textSecondary
        }
    }
}

extension BudgetAlert {
    var tone: BillStatus.Tone {
        switch self {
        case .none: return .brand
        case .warning: return .warning
        case .exceeded: return .danger
        }
    }
}

extension InvoiceStatus {
    var label: String {
        switch self {
        case .open: return "Aberta"
        case .closed: return "Fechada"
        case .paid: return "Paga"
        case .overdue: return "Atrasada"
        }
    }
    var tone: BillStatus.Tone {
        switch self {
        case .open: return .brand
        case .closed: return .warning
        case .paid: return .ok
        case .overdue: return .danger
        }
    }
}

extension AccountType {
    var symbol: String {
        switch self {
        case .checking: return "building.columns"
        case .savings: return "banknote"
        case .wallet: return "wallet.pass"
        case .investment: return "chart.line.uptrend.xyaxis"
        }
    }
}
