import Foundation

// MARK: - Papéis e permissões

enum FamilyPermission: Sendable, CaseIterable {
    case manageMembers, manageAllowances, approveSpending, splitExpenses, viewFamilyView, addTransactions, manageSharedData
}

/// Visão dos dados: consolidada da família (só o compartilhado) ou individual de um membro.
enum FamilyScope: Equatable, Sendable { case family, member(UUID) }

enum FamilyEngine {
    static func can(_ role: MemberRole, _ permission: FamilyPermission) -> Bool {
        switch role {
        case .admin: return true
        case .member:
            switch permission {
            case .manageMembers, .manageAllowances: return false
            default: return true
            }
        case .dependent:
            return permission == .addTransactions
        }
    }

    private static func requireName(_ raw: String) throws -> String {
        let n = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { throw FinanceError.invalidState("Informe um nome.") }
        return n
    }

    // MARK: Membros

    static func createHousehold(name: String, adminName: String, email: String?) -> (Household, FamilyMember) {
        let house = Household(name: name.trimmingCharacters(in: .whitespacesAndNewlines))
        let admin = FamilyMember(householdId: house.id, name: adminName.trimmingCharacters(in: .whitespacesAndNewlines),
                                 role: .admin, email: email)
        return (house, admin)
    }

    static func addMember(to household: Household, name: String, role: MemberRole, email: String? = nil, by actor: FamilyMember) throws -> FamilyMember {
        guard actor.householdId == household.id, can(actor.role, .manageMembers) else { throw FinanceError.permissionDenied }
        return FamilyMember(householdId: household.id, name: try requireName(name), role: role, email: email)
    }

    static func setSpendingLimit(_ member: FamilyMember, limit: Decimal?, by actor: FamilyMember) throws -> FamilyMember {
        guard actor.householdId == member.householdId, can(actor.role, .manageMembers) else { throw FinanceError.permissionDenied }
        guard member.role == .dependent else { throw FinanceError.invalidState("Só dependentes têm limite de gastos.") }
        if let limit, limit < 0 { throw FinanceError.invalidAmount }
        var m = member
        m.monthlySpendingLimit = limit
        m.updatedAt = Date()
        return m
    }

    private static func adminCount(_ members: [FamilyMember], excluding id: UUID? = nil) -> Int {
        members.filter { $0.role == .admin && $0.id != id }.count
    }

    static func changeRole(_ member: FamilyMember, to role: MemberRole, members: [FamilyMember], by actor: FamilyMember) throws -> FamilyMember {
        guard actor.householdId == member.householdId, can(actor.role, .manageMembers) else { throw FinanceError.permissionDenied }
        if member.role == .admin, role != .admin, adminCount(members, excluding: member.id) == 0 { throw FinanceError.lastAdmin }
        var m = member
        m.role = role
        if role != .dependent { m.monthlySpendingLimit = nil }
        m.updatedAt = Date()
        return m
    }

    /// Lança erro se a remoção não é permitida (sem permissão ou último admin).
    static func validateRemoval(of member: FamilyMember, members: [FamilyMember], by actor: FamilyMember) throws {
        guard actor.householdId == member.householdId, can(actor.role, .manageMembers) else { throw FinanceError.permissionDenied }
        if member.role == .admin, adminCount(members, excluding: member.id) == 0 { throw FinanceError.lastAdmin }
    }

    // MARK: Privacidade e visões

    /// Contas visíveis. Família: apenas compartilhadas. Individual: as compartilhadas mais as privadas do próprio
    /// membro, estas só quando o espectador é o próprio membro (nem admin vê conta privada de outra pessoa).
    static func visibleAccounts(_ accounts: [Account], viewer: UUID?, scope: FamilyScope) -> [Account] {
        switch scope {
        case .family:
            return accounts.filter { $0.visibility == .shared }
        case .member(let m):
            return accounts.filter { $0.visibility == .shared || ($0.ownerId == m && viewer == m) }
        }
    }

    /// Categorias compartilhadas, mais as privadas do próprio espectador.
    static func visibleCategories(_ categories: [Category], viewer: UUID?) -> [Category] {
        categories.filter { $0.visibility == .shared || ($0.ownerId != nil && $0.ownerId == viewer) }
    }

    static func visibleTransactions(_ transactions: [Transaction], accounts: [Account], categories: [Category],
                                    viewer: UUID?, scope: FamilyScope) -> [Transaction] {
        let accountById = Dictionary(accounts.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let categoryById = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return transactions.filter { tx in
            let account = tx.accountId.flatMap { accountById[$0] }
            let category = tx.categoryId.flatMap { categoryById[$0] }
            // privado de outra pessoa nunca aparece (nem para admin)
            if let a = account, a.visibility == .personal, a.ownerId != viewer { return false }
            if let c = category, c.visibility == .personal, c.ownerId != viewer { return false }
            switch scope {
            case .family:
                return account?.visibility != .personal && category?.visibility != .personal
            case .member(let m):
                // lançamento sem atribuição pertence ao dono da conta
                return tx.memberId == m || (tx.memberId == nil && account?.ownerId == m)
            }
        }
    }

    static func attribute(_ tx: Transaction, to memberId: UUID?) -> Transaction {
        var t = tx
        t.memberId = memberId
        return t
    }
}

// MARK: - Aprovação de gastos de dependentes

enum SpendingDecision: Equatable, Sendable {
    case allowed
    case needsApproval(limit: Decimal, spent: Decimal)
}

enum ApprovalEngine {
    /// Despesas do membro no mês (compras de cartão incluídas; pagamentos de fatura e transferências não).
    static func spent(memberId: UUID, month: YearMonth, transactions: [Transaction]) -> Decimal {
        transactions.reduce(0) { acc, tx in
            guard tx.memberId == memberId, tx.type == .expense, !tx.isInvoicePayment, month.contains(tx.date) else { return acc }
            return acc + tx.amount
        }
    }

    static func evaluate(member: FamilyMember, amount: Decimal, date: Date, transactions: [Transaction]) -> SpendingDecision {
        guard member.role == .dependent, let limit = member.monthlySpendingLimit else { return .allowed }
        let spent = spent(memberId: member.id, month: YearMonth(date), transactions: transactions)
        return spent + amount > limit ? .needsApproval(limit: limit, spent: spent) : .allowed
    }

    static func request(member: FamilyMember, title: String, amount: Decimal, date: Date, accountId: UUID?, categoryId: UUID?) -> ApprovalRequest {
        ApprovalRequest(memberId: member.id, title: title, amount: amount, date: date, accountId: accountId, categoryId: categoryId)
    }

    private static func ensureDecidable(_ request: ApprovalRequest, by approver: FamilyMember) throws {
        guard can(approver) else { throw FinanceError.permissionDenied }
        guard request.status == .pending else { throw FinanceError.invalidState("Este pedido já foi decidido.") }
    }

    private static func can(_ approver: FamilyMember) -> Bool { FamilyEngine.can(approver.role, .approveSpending) }

    static func approve(_ request: ApprovalRequest, by approver: FamilyMember, now: Date = Date()) throws -> (request: ApprovalRequest, transaction: Transaction) {
        try ensureDecidable(request, by: approver)
        var tx = Transaction(type: .expense, amount: request.amount, date: request.date, title: request.title,
                             status: .paid, accountId: request.accountId, categoryId: request.categoryId)
        tx.memberId = request.memberId
        var r = request
        r.status = .approved; r.decidedBy = approver.id; r.decidedAt = now; r.transactionId = tx.id; r.updatedAt = now
        return (r, tx)
    }

    static func reject(_ request: ApprovalRequest, by approver: FamilyMember, now: Date = Date()) throws -> ApprovalRequest {
        try ensureDecidable(request, by: approver)
        var r = request
        r.status = .rejected; r.decidedBy = approver.id; r.decidedAt = now; r.updatedAt = now
        return r
    }

    static func pending(_ requests: [ApprovalRequest]) -> [ApprovalRequest] { requests.filter { $0.status == .pending } }
}

// MARK: - Mesada

enum AllowanceEngine {
    static let maxCatchUpMonths = 12

    static func make(for member: FamilyMember, amount: Decimal, dayOfMonth: Int, from: UUID, to: UUID,
                     startMonth: YearMonth, by actor: FamilyMember) throws -> Allowance {
        guard actor.householdId == member.householdId, FamilyEngine.can(actor.role, .manageAllowances) else { throw FinanceError.permissionDenied }
        guard member.role == .dependent else { throw FinanceError.invalidState("A mesada é para dependentes.") }
        guard amount > 0 else { throw FinanceError.invalidAmount }
        guard (1...31).contains(dayOfMonth) else { throw FinanceError.invalidDay }
        guard from != to else { throw FinanceError.sameAccount }
        return Allowance(memberId: member.id, amount: amount, dayOfMonth: dayOfMonth, fromAccountId: from, toAccountId: to, startMonth: startMonth)
    }

    /// Meses cujo dia de pagamento já chegou e ainda não foram pagos (no máximo os 12 mais recentes).
    static func dueMonths(_ a: Allowance, asOf: Date) -> [YearMonth] {
        guard a.isActive else { return [] }
        var month = a.lastPaidMonth.map { $0.next } ?? a.startMonth
        if month < a.startMonth { month = a.startMonth }
        var result: [YearMonth] = []
        while !FinanceCalendar.isBeforeDay(asOf, month.date(day: a.dayOfMonth)) {
            result.append(month)
            month = month.next
            if result.count > 1200 { break }
        }
        return Array(result.suffix(maxCatchUpMonths))
    }

    /// Gera as transferências devidas e avança `lastPaidMonth`.
    static func pay(_ a: Allowance, asOf: Date) -> (allowance: Allowance, transactions: [Transaction]) {
        let months = dueMonths(a, asOf: asOf)
        guard let last = months.last else { return (a, []) }
        let txs = months.map { m -> Transaction in
            var t = Transaction(type: .transfer, amount: a.amount, date: m.date(day: a.dayOfMonth), title: "Mesada \(m.label)",
                                status: .paid, accountId: a.fromAccountId, destinationAccountId: a.toAccountId)
            t.memberId = a.memberId
            return t
        }
        var updated = a
        updated.lastPaidMonth = last
        updated.updatedAt = Date()
        return (updated, txs)
    }
}
