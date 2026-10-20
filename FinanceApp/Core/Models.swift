import Foundation

// Todos os modelos: Codable, Sendable, Identifiable (UUID), createdAt/updatedAt e ownerId opcional
// (preparados para CloudKit/multiusuário). Dinheiro sempre em Decimal.
// Convenção de valores: `Transaction.amount` é a magnitude (positiva) do lançamento; o sinal vem do tipo.
// Um valor negativo representa estorno (ex.: despesa de -50 = reembolso que reduz despesas).

protocol StoredEntity: Codable, Sendable, Identifiable, Equatable where ID == UUID {
    var id: UUID { get }
    var createdAt: Date { get }
    var updatedAt: Date { get set }
    var ownerId: UUID? { get }
    static var storage: WritableKeyPath<FinanceSnapshot, [Self]> { get }
}

enum AccountType: String, Codable, Sendable, CaseIterable {
    case checking, savings, wallet, investment
    var displayName: String {
        switch self {
        case .checking: return "Conta corrente"
        case .savings: return "Poupança"
        case .wallet: return "Carteira"
        case .investment: return "Investimentos"
        }
    }
}

enum CategoryKind: String, Codable, Sendable, CaseIterable { case income, expense }
enum TransactionType: String, Codable, Sendable, CaseIterable { case income, expense, transfer }
enum TransactionStatus: String, Codable, Sendable, CaseIterable { case pending, paid }
enum RecurrenceFrequency: String, Codable, Sendable, CaseIterable { case weekly, monthly, yearly }
enum MemberRole: String, Codable, Sendable, CaseIterable { case admin, member, dependent }

/// Visibilidade de contas e categorias no grupo familiar. `personal` (valor "private") só aparece para o dono.
enum Visibility: String, Codable, Sendable, CaseIterable {
    case shared
    case personal = "private"
    var displayName: String { self == .shared ? "Compartilhada" : "Privada" }
}

/// Tipo de despesa dedutível no Imposto de Renda (marcado na categoria).
enum TaxDeductionKind: String, Codable, Sendable, CaseIterable {
    case health, education
    var displayName: String { self == .health ? "Saúde" : "Educação" }
}

struct Account: StoredEntity {
    var id = UUID()
    var name: String
    var type: AccountType
    var initialBalance: Decimal = 0
    var currency: String = "BRL"
    var isArchived: Bool = false
    /// Dono da conta é `ownerId` (id do FamilyMember). Contas privadas só entram na visão individual do dono.
    var visibility: Visibility = .shared
    var ownerId: UUID? = nil
    var createdAt = Date()
    var updatedAt = Date()
    static var storage: WritableKeyPath<FinanceSnapshot, [Account]> { \.accounts }
}

extension Account {
    private enum CodingKeys: String, CodingKey {
        case id, name, type, initialBalance, currency, isArchived, visibility, ownerId, createdAt, updatedAt
    }
    /// Tolerante a dados da Fase 1 (sem `visibility`).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        type = try c.decode(AccountType.self, forKey: .type)
        initialBalance = try c.decode(Decimal.self, forKey: .initialBalance)
        currency = try c.decode(String.self, forKey: .currency)
        isArchived = try c.decode(Bool.self, forKey: .isArchived)
        visibility = try c.decodeIfPresent(Visibility.self, forKey: .visibility) ?? .shared
        ownerId = try c.decodeIfPresent(UUID.self, forKey: .ownerId)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }
}

struct Category: StoredEntity {
    var id = UUID()
    var name: String
    var kind: CategoryKind
    /// Se preenchido, é subcategoria da categoria `parentId`.
    var parentId: UUID? = nil
    var icon: String? = nil
    var colorHex: String? = nil
    var visibility: Visibility = .shared
    /// Marca a categoria como despesa dedutível no IR (saúde ou educação).
    var taxKind: TaxDeductionKind? = nil
    var ownerId: UUID? = nil
    var createdAt = Date()
    var updatedAt = Date()
    static var storage: WritableKeyPath<FinanceSnapshot, [Category]> { \.categories }
}

extension Category {
    private enum CodingKeys: String, CodingKey {
        case id, name, kind, parentId, icon, colorHex, visibility, taxKind, ownerId, createdAt, updatedAt
    }
    /// Tolerante a dados da Fase 1 (sem `visibility`/`taxKind`).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(CategoryKind.self, forKey: .kind)
        parentId = try c.decodeIfPresent(UUID.self, forKey: .parentId)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex)
        visibility = try c.decodeIfPresent(Visibility.self, forKey: .visibility) ?? .shared
        taxKind = try c.decodeIfPresent(TaxDeductionKind.self, forKey: .taxKind)
        ownerId = try c.decodeIfPresent(UUID.self, forKey: .ownerId)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }
}

struct Tag: StoredEntity {
    var id = UUID()
    var name: String
    var ownerId: UUID? = nil
    var createdAt = Date()
    var updatedAt = Date()
    static var storage: WritableKeyPath<FinanceSnapshot, [Tag]> { \.tags }
}

struct RecurrenceRule: Codable, Sendable, Equatable {
    var frequency: RecurrenceFrequency
    /// A cada N períodos (1 = todo mês/semana/ano).
    var interval: Int = 1
    /// Fim (inclusivo) opcional.
    var endDate: Date? = nil
    /// Máximo de ocorrências (contando a primeira) opcional.
    var maxOccurrences: Int? = nil
}

struct InstallmentInfo: Codable, Sendable, Equatable {
    var number: Int      // x
    var total: Int       // y
    var groupId: UUID    // une todas as parcelas da mesma compra
    var label: String { "\(number)/\(total)" }
}

struct Transaction: StoredEntity {
    var id = UUID()
    var type: TransactionType
    /// Magnitude. Receita soma, despesa subtrai; negativo = estorno.
    var amount: Decimal
    var date: Date
    var title: String
    var status: TransactionStatus = .paid
    /// Conta de origem (despesa/receita: a conta afetada). Nil para compras de cartão.
    var accountId: UUID? = nil
    /// Conta de destino (transferências entre contas).
    var destinationAccountId: UUID? = nil
    var categoryId: UUID? = nil
    var tagIds: [UUID] = []
    /// Cartão da compra (compra de cartão: `creditCardId != nil && invoiceId == nil`).
    var creditCardId: UUID? = nil
    /// Preenchido no lançamento de pagamento de fatura (transferência sem destino, ligada a um cartão).
    var invoiceId: UUID? = nil
    var installment: InstallmentInfo? = nil
    /// Regra de recorrência (no lançamento "modelo").
    var recurrence: RecurrenceRule? = nil
    /// Lançamento modelo que originou esta ocorrência.
    var recurrenceParentId: UUID? = nil
    var attachmentPath: String? = nil
    var note: String? = nil
    /// Identificador externo (FITID do OFX) para evitar importação duplicada.
    var externalId: String? = nil
    /// Membro da família responsável.
    var memberId: UUID? = nil
    var ownerId: UUID? = nil
    var createdAt = Date()
    var updatedAt = Date()
    static var storage: WritableKeyPath<FinanceSnapshot, [Transaction]> { \.transactions }

    var isCardPurchase: Bool { creditCardId != nil && invoiceId == nil }
    var isInvoicePayment: Bool { invoiceId != nil }
    /// Efeito no resultado do período: receita +, despesa -; transferências não entram.
    var signedAmount: Decimal {
        switch type {
        case .income: return amount
        case .expense: return -amount
        case .transfer: return 0
        }
    }
}

struct CreditCard: StoredEntity {
    var id = UUID()
    var name: String
    var limit: Decimal
    /// Dia de fechamento (1...31; em meses curtos usa o último dia).
    var closingDay: Int
    var dueDay: Int
    /// Conta usada para pagar a fatura.
    var paymentAccountId: UUID? = nil
    var isArchived: Bool = false
    var ownerId: UUID? = nil
    var createdAt = Date()
    var updatedAt = Date()
    static var storage: WritableKeyPath<FinanceSnapshot, [CreditCard]> { \.creditCards }
}

enum InvoiceStatus: String, Codable, Sendable { case open, closed, paid, overdue }

/// Fatura persistida (criada quando há pagamento). `month` = mês do FECHAMENTO.
struct Invoice: StoredEntity {
    var id = UUID()
    var cardId: UUID
    var month: YearMonth
    var closingDate: Date
    var dueDate: Date
    var paidAmount: Decimal = 0
    var paidAt: Date? = nil
    var paymentAccountId: UUID? = nil
    var ownerId: UUID? = nil
    var createdAt = Date()
    var updatedAt = Date()
    static var storage: WritableKeyPath<FinanceSnapshot, [Invoice]> { \.invoices }
}

struct Budget: StoredEntity {
    var id = UUID()
    var categoryId: UUID
    var month: YearMonth
    var limit: Decimal
    var ownerId: UUID? = nil
    var createdAt = Date()
    var updatedAt = Date()
    static var storage: WritableKeyPath<FinanceSnapshot, [Budget]> { \.budgets }
}

struct Goal: StoredEntity {
    var id = UUID()
    var name: String
    var targetAmount: Decimal
    var currentAmount: Decimal = 0
    var deadline: Date? = nil
    /// Meta de um membro da família (ex.: filho). nil = meta da casa/pessoal.
    var memberId: UUID? = nil
    var ownerId: UUID? = nil
    var createdAt = Date()
    var updatedAt = Date()
    static var storage: WritableKeyPath<FinanceSnapshot, [Goal]> { \.goals }
}

struct Debt: StoredEntity {
    var id = UUID()
    var name: String
    /// Saldo devedor atual.
    var balance: Decimal
    /// Juros mensais em fração (0.02 = 2% a.m.). Use `dec("0.02")`.
    var monthlyInterestRate: Decimal
    var minimumPayment: Decimal
    var dueDay: Int? = nil
    var ownerId: UUID? = nil
    var createdAt = Date()
    var updatedAt = Date()
    static var storage: WritableKeyPath<FinanceSnapshot, [Debt]> { \.debts }
}

struct Household: StoredEntity {
    var id = UUID()
    var name: String
    var ownerId: UUID? = nil
    var createdAt = Date()
    var updatedAt = Date()
    static var storage: WritableKeyPath<FinanceSnapshot, [Household]> { \.households }
}

struct FamilyMember: StoredEntity {
    var id = UUID()
    var householdId: UUID
    var name: String
    var role: MemberRole = .member
    var email: String? = nil
    /// Dependentes: limite mensal de gastos. Acima dele, o lançamento vira pedido de aprovação.
    var monthlySpendingLimit: Decimal? = nil
    var ownerId: UUID? = nil
    var createdAt = Date()
    var updatedAt = Date()
    static var storage: WritableKeyPath<FinanceSnapshot, [FamilyMember]> { \.familyMembers }
}

/// Foto completa dos dados (usada pelo JSONFileStore e para backup/restauração).
/// A decodificação é tolerante: arquivos de versões anteriores (sem as coleções novas) continuam válidos.
struct FinanceSnapshot: Codable, Sendable, Equatable {
    var version: Int = 2
    var accounts: [Account] = []
    var categories: [Category] = []
    var tags: [Tag] = []
    var transactions: [Transaction] = []
    var creditCards: [CreditCard] = []
    var invoices: [Invoice] = []
    var budgets: [Budget] = []
    var goals: [Goal] = []
    var debts: [Debt] = []
    var households: [Household] = []
    var familyMembers: [FamilyMember] = []
    var goalContributions: [GoalContribution] = []
    var investments: [Investment] = []
    var netWorthSnapshots: [NetWorthSnapshot] = []
    var expenseSplits: [ExpenseSplit] = []
    var splitSettlements: [SplitSettlement] = []
    var allowances: [Allowance] = []
    var approvalRequests: [ApprovalRequest] = []
    var tombstones: [Tombstone] = []

    init() {}

    private enum CodingKeys: String, CodingKey {
        case version, accounts, categories, tags, transactions, creditCards, invoices, budgets, goals, debts, households,
             familyMembers, goalContributions, investments, netWorthSnapshots, expenseSplits, splitSettlements,
             allowances, approvalRequests, tombstones
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        accounts = try c.decodeIfPresent([Account].self, forKey: .accounts) ?? []
        categories = try c.decodeIfPresent([Category].self, forKey: .categories) ?? []
        tags = try c.decodeIfPresent([Tag].self, forKey: .tags) ?? []
        transactions = try c.decodeIfPresent([Transaction].self, forKey: .transactions) ?? []
        creditCards = try c.decodeIfPresent([CreditCard].self, forKey: .creditCards) ?? []
        invoices = try c.decodeIfPresent([Invoice].self, forKey: .invoices) ?? []
        budgets = try c.decodeIfPresent([Budget].self, forKey: .budgets) ?? []
        goals = try c.decodeIfPresent([Goal].self, forKey: .goals) ?? []
        debts = try c.decodeIfPresent([Debt].self, forKey: .debts) ?? []
        households = try c.decodeIfPresent([Household].self, forKey: .households) ?? []
        familyMembers = try c.decodeIfPresent([FamilyMember].self, forKey: .familyMembers) ?? []
        goalContributions = try c.decodeIfPresent([GoalContribution].self, forKey: .goalContributions) ?? []
        investments = try c.decodeIfPresent([Investment].self, forKey: .investments) ?? []
        netWorthSnapshots = try c.decodeIfPresent([NetWorthSnapshot].self, forKey: .netWorthSnapshots) ?? []
        expenseSplits = try c.decodeIfPresent([ExpenseSplit].self, forKey: .expenseSplits) ?? []
        splitSettlements = try c.decodeIfPresent([SplitSettlement].self, forKey: .splitSettlements) ?? []
        allowances = try c.decodeIfPresent([Allowance].self, forKey: .allowances) ?? []
        approvalRequests = try c.decodeIfPresent([ApprovalRequest].self, forKey: .approvalRequests) ?? []
        tombstones = try c.decodeIfPresent([Tombstone].self, forKey: .tombstones) ?? []
    }
}
