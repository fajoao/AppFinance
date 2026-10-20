import Foundation

// Entidades da Fase 2 (v1): histórico de aportes, investimentos, patrimônio, divisão de despesas,
// mesada, aprovações e tombstones de sincronização. Mesmas convenções de Models.swift.

/// Aporte (ou retirada, valor negativo) em uma meta.
struct GoalContribution: StoredEntity {
    var id = UUID()
    var goalId: UUID
    /// Positivo = guardou; negativo = retirou.
    var amount: Decimal
    var date: Date
    /// Conta de onde saiu o dinheiro (nil quando o aporte foi apenas registrado).
    var accountId: UUID? = nil
    /// Lançamento de saída gerado no aporte (para desfazer os dois juntos).
    var transactionId: UUID? = nil
    var note: String? = nil
    var ownerId: UUID? = nil
    var createdAt = Date()
    var updatedAt = Date()
    static var storage: WritableKeyPath<FinanceSnapshot, [GoalContribution]> { \.goalContributions }
}

enum AssetClass: String, Codable, Sendable, CaseIterable {
    case fixedIncome, stock, reit, crypto
    var displayName: String {
        switch self {
        case .fixedIncome: return "Renda fixa"
        case .stock: return "Ações"
        case .reit: return "FIIs"
        case .crypto: return "Cripto"
        }
    }
}

/// Posição em um ativo, cadastrada à mão. Renda fixa usa quantidade 1, preço médio = valor aplicado e
/// cotação = valor atual. `quote` nil = ainda sem cotação (usa o preço médio).
struct Investment: StoredEntity {
    var id = UUID()
    var name: String
    var ticker: String? = nil
    var assetClass: AssetClass
    var quantity: Decimal
    var averagePrice: Decimal
    var quote: Decimal? = nil
    var quoteDate: Date? = nil
    /// Ganho já realizado em vendas parciais.
    var realizedProfit: Decimal = 0
    var memberId: UUID? = nil
    var ownerId: UUID? = nil
    var createdAt = Date()
    var updatedAt = Date()
    static var storage: WritableKeyPath<FinanceSnapshot, [Investment]> { \.investments }
}

/// Patrimônio de um mês (um registro por mês; o mais recente do mês substitui o anterior).
struct NetWorthSnapshot: StoredEntity {
    var id = UUID()
    var month: YearMonth
    var assets: Decimal
    var liabilities: Decimal
    var ownerId: UUID? = nil
    var createdAt = Date()
    var updatedAt = Date()
    var netWorth: Decimal { assets - liabilities }
    static var storage: WritableKeyPath<FinanceSnapshot, [NetWorthSnapshot]> { \.netWorthSnapshots }
}

enum SplitMode: String, Codable, Sendable, CaseIterable {
    case equal, percentage
    var displayName: String { self == .equal ? "Igual" : "Percentual" }
}

struct SplitShare: Codable, Sendable, Equatable {
    var memberId: UUID
    /// Percentual (0...100) quando o modo é `.percentage`.
    var percent: Decimal?
    var amount: Decimal
}

/// Despesa dividida entre membros. `paidBy` adiantou o valor; cada `share` é quanto cada um deve arcar.
struct ExpenseSplit: StoredEntity {
    var id = UUID()
    var title: String
    var total: Decimal
    var date: Date
    var paidBy: UUID
    var mode: SplitMode
    var shares: [SplitShare]
    /// Lançamento de despesa associado (opcional).
    var transactionId: UUID? = nil
    var ownerId: UUID? = nil
    var createdAt = Date()
    var updatedAt = Date()
    static var storage: WritableKeyPath<FinanceSnapshot, [ExpenseSplit]> { \.expenseSplits }
}

/// Acerto de contas já feito: `from` pagou `amount` a `to`.
struct SplitSettlement: StoredEntity {
    var id = UUID()
    var fromMemberId: UUID
    var toMemberId: UUID
    var amount: Decimal
    var date: Date
    var ownerId: UUID? = nil
    var createdAt = Date()
    var updatedAt = Date()
    static var storage: WritableKeyPath<FinanceSnapshot, [SplitSettlement]> { \.splitSettlements }
}

/// Mesada mensal: transferência da conta do responsável para a conta do dependente.
struct Allowance: StoredEntity {
    var id = UUID()
    var memberId: UUID
    var amount: Decimal
    /// Dia do mês (1...31; em meses curtos usa o último dia).
    var dayOfMonth: Int
    var fromAccountId: UUID
    var toAccountId: UUID
    /// Primeiro mês de vigência.
    var startMonth: YearMonth
    /// Último mês já pago (garante que não pague duas vezes).
    var lastPaidMonth: YearMonth? = nil
    var isActive: Bool = true
    var ownerId: UUID? = nil
    var createdAt = Date()
    var updatedAt = Date()
    static var storage: WritableKeyPath<FinanceSnapshot, [Allowance]> { \.allowances }
}

enum ApprovalStatus: String, Codable, Sendable, CaseIterable {
    case pending, approved, rejected
    var displayName: String {
        switch self {
        case .pending: return "Pendente"
        case .approved: return "Aprovado"
        case .rejected: return "Recusado"
        }
    }
}

/// Gasto de dependente que passou do limite e aguarda decisão de um responsável.
struct ApprovalRequest: StoredEntity {
    var id = UUID()
    var memberId: UUID
    var title: String
    var amount: Decimal
    var date: Date
    var accountId: UUID? = nil
    var categoryId: UUID? = nil
    var status: ApprovalStatus = .pending
    var decidedBy: UUID? = nil
    var decidedAt: Date? = nil
    /// Preenchido quando aprovado (lançamento criado).
    var transactionId: UUID? = nil
    var ownerId: UUID? = nil
    var createdAt = Date()
    var updatedAt = Date()
    static var storage: WritableKeyPath<FinanceSnapshot, [ApprovalRequest]> { \.approvalRequests }
}

/// Marca de exclusão para a sincronização (sem ela, um registro apagado "ressuscitaria" no merge).
struct Tombstone: StoredEntity {
    var id = UUID()
    /// Nome do tipo apagado (ex.: "Transaction").
    var entityType: String
    var entityId: UUID
    var deletedAt: Date
    var ownerId: UUID? = nil
    var createdAt = Date()
    var updatedAt = Date()
    static var storage: WritableKeyPath<FinanceSnapshot, [Tombstone]> { \.tombstones }
}
