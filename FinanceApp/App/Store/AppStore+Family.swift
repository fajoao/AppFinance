import Foundation

// Família (local): grupo, perfis, privacidade, divisão de despesas, mesada e aprovações.
// As regras estão no Core (FamilyEngine, SplitEngine, SettlementEngine, AllowanceEngine, ApprovalEngine).

enum SubmitOutcome: Equatable, Sendable {
    case saved([BudgetAlertEvent])
    case awaitingApproval(ApprovalRequest)
}

extension AppStore {
    // MARK: Estado derivado

    var household: Household? { households.first }
    var hasHousehold: Bool { household != nil }

    /// Perfil ativo (quem está usando o app agora). nil quando não há grupo familiar.
    var activeMember: FamilyMember? {
        guard hasHousehold else { return nil }
        return members.first { $0.id == preferences.activeMemberId } ?? members.first { $0.role == .admin } ?? members.first
    }

    /// Id usado para atribuir lançamentos e checar privacidade.
    var viewerId: UUID? { activeMember?.id }

    var canViewFamily: Bool { activeMember.map { FamilyEngine.can($0.role, .viewFamilyView) } ?? true }

    /// Visão efetiva. Dependentes só enxergam a própria visão individual.
    var viewScope: FamilyScope {
        guard let me = activeMember else { return .family }
        if !canViewFamily { return .member(me.id) }
        return preferences.viewScope == .family ? .family : .member(me.id)
    }

    var isFamilyView: Bool { viewScope == .family && hasHousehold }

    /// Contas somadas nos totais (respeita família × individual e privacidade).
    var scopedAccounts: [Account] {
        guard hasHousehold else { return accounts }
        return FamilyEngine.visibleAccounts(accounts, viewer: viewerId, scope: viewScope)
    }

    /// Contas que o perfil ativo pode escolher ao lançar (compartilhadas + as próprias).
    var usableAccounts: [Account] {
        guard hasHousehold, let me = viewerId else { return accounts }
        return FamilyEngine.visibleAccounts(accounts, viewer: me, scope: .member(me))
    }

    var selectableCategories: [Category] {
        guard hasHousehold else { return categories }
        return FamilyEngine.visibleCategories(categories, viewer: viewerId)
    }

    var scopedTransactions: [Transaction] {
        guard hasHousehold else { return transactions }
        return FamilyEngine.visibleTransactions(transactions, accounts: accounts, categories: categories, viewer: viewerId, scope: viewScope)
    }

    func memberSpent(_ member: FamilyMember, month: YearMonth? = nil) -> Decimal {
        ApprovalEngine.spent(memberId: member.id, month: month ?? currentMonth, transactions: transactions)
    }

    var pendingApprovals: [ApprovalRequest] { ApprovalEngine.pending(approvals) }

    var dependents: [FamilyMember] { members.filter { $0.role == .dependent } }

    // MARK: Grupo e membros

    func createHousehold(name: String, adminName: String) throws {
        guard !hasHousehold else { throw StoreError.householdExists }
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, !adminName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw StoreError.emptyName }
        let (house, admin) = FamilyEngine.createHousehold(name: n, adminName: adminName, email: nil)
        try repository.save(house)
        try repository.save(admin)
        // contas e categorias já existentes passam a pertencer ao administrador (continuam compartilhadas)
        let owned = accounts.filter { $0.ownerId == nil }.map { a -> Account in var c = a; c.ownerId = admin.id; c.updatedAt = Date(); return c }
        try repository.saveAll(owned)
        updatePreferences { $0.activeMemberId = admin.id; $0.viewScope = .family }
        reload()
    }

    @discardableResult
    func addMember(name: String, role: MemberRole, monthlyLimit: Decimal? = nil) throws -> FamilyMember {
        guard let house = household else { throw StoreError.noHousehold }
        guard let me = activeMember else { throw FinanceError.permissionDenied }
        var m = try FamilyEngine.addMember(to: house, name: name, role: role, by: me)
        if role == .dependent, let monthlyLimit { m = try FamilyEngine.setSpendingLimit(m, limit: monthlyLimit, by: me) }
        try repository.save(m)
        reload()
        return m
    }

    func changeRole(memberId: UUID, to role: MemberRole) throws {
        guard let me = activeMember, let m = members.first(where: { $0.id == memberId }) else { throw StoreError.notFound }
        try repository.save(try FamilyEngine.changeRole(m, to: role, members: members, by: me))
        reload()
    }

    func setSpendingLimit(memberId: UUID, limit: Decimal?) throws {
        guard let me = activeMember, let m = members.first(where: { $0.id == memberId }) else { throw StoreError.notFound }
        try repository.save(try FamilyEngine.setSpendingLimit(m, limit: limit, by: me))
        reload()
    }

    func removeMember(id: UUID) throws {
        guard let me = activeMember, let m = members.first(where: { $0.id == id }) else { throw StoreError.notFound }
        try FamilyEngine.validateRemoval(of: m, members: members, by: me)
        try repository.deleteTracked(FamilyMember.self, id: id)
        if preferences.activeMemberId == id { updatePreferences { $0.activeMemberId = me.id == id ? nil : me.id } }
        reload()
    }

    func setActiveMember(_ id: UUID) {
        guard members.contains(where: { $0.id == id }) else { return }
        updatePreferences { $0.activeMemberId = id }
        reload()
    }

    func setViewScope(_ scope: ViewScopePreference) {
        updatePreferences { $0.viewScope = scope }
        reload()
    }

    // MARK: Privacidade

    func setAccountVisibility(id: UUID, _ visibility: Visibility) throws {
        guard var a = accounts.first(where: { $0.id == id }) else { throw StoreError.notFound }
        if a.ownerId != nil, a.ownerId != viewerId, hasHousehold { throw FinanceError.permissionDenied }
        a.visibility = visibility
        if a.ownerId == nil { a.ownerId = viewerId }
        try repository.save(touching: a)
        reload()
    }

    @discardableResult
    func addCategory(name: String, kind: CategoryKind, visibility: Visibility = .shared, taxKind: TaxDeductionKind? = nil) throws -> Category {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { throw StoreError.emptyName }
        let c = Category(name: n, kind: kind, icon: "tag", colorHex: "catOutros", visibility: visibility,
                         taxKind: kind == .expense ? taxKind : nil, ownerId: viewerId)
        try repository.save(c)
        reload()
        return c
    }

    /// Marca (ou desmarca) a categoria como dedutível no IR.
    func setTaxKind(categoryId: UUID, _ kind: TaxDeductionKind?) throws {
        guard var c = categories.first(where: { $0.id == categoryId }) else { throw StoreError.notFound }
        guard c.kind == .expense else { return }
        c.taxKind = kind
        try repository.save(touching: c)
        reload()
    }

    func setCategoryVisibility(categoryId: UUID, _ visibility: Visibility) throws {
        guard var c = categories.first(where: { $0.id == categoryId }) else { throw StoreError.notFound }
        if c.ownerId != nil, c.ownerId != viewerId, hasHousehold { throw FinanceError.permissionDenied }
        c.visibility = visibility
        if c.ownerId == nil { c.ownerId = viewerId }
        try repository.save(touching: c)
        reload()
    }

    // MARK: Lançar com atribuição e aprovação

    /// Salva o lançamento. Gasto de dependente acima do limite mensal vira pedido de aprovação (não altera saldos).
    func submit(_ draft: TransactionDraft) throws -> SubmitOutcome {
        if hasHousehold, let me = activeMember, draft.type == .expense, !draft.isEditing,
           case .needsApproval = ApprovalEngine.evaluate(member: me, amount: draft.amount, date: draft.date, transactions: transactions) {
            if let e = draft.validate() { throw e }
            var accountId: UUID?
            if case .account(let id)? = draft.source { accountId = id }
            let req = ApprovalEngine.request(member: me, title: draft.effectiveTitle, amount: draft.amount, date: draft.date,
                                             accountId: accountId, categoryId: draft.categoryId)
            try repository.save(req)
            reload()
            return .awaitingApproval(req)
        }
        return .saved(try save(draft))
    }

    func approve(requestId: UUID) throws {
        guard let me = activeMember, let r = approvals.first(where: { $0.id == requestId }) else { throw StoreError.notFound }
        let result = try ApprovalEngine.approve(r, by: me)
        try repository.save(result.transaction)
        try repository.save(result.request)
        reload()
    }

    func reject(requestId: UUID) throws {
        guard let me = activeMember, let r = approvals.first(where: { $0.id == requestId }) else { throw StoreError.notFound }
        try repository.save(try ApprovalEngine.reject(r, by: me))
        reload()
    }

    // MARK: Edição e exclusão de lançamentos

    func draft(editing id: UUID) throws -> TransactionDraft {
        guard let tx = transactions.first(where: { $0.id == id }) else { throw StoreError.notFound }
        if tx.isInvoicePayment { throw StoreError.cannotEditInvoicePayment }
        return TransactionDraft(editing: tx)
    }

    func update(_ draft: TransactionDraft) throws {
        guard let id = draft.editingId, let original = transactions.first(where: { $0.id == id }) else { throw StoreError.notFound }
        if original.isInvoicePayment { throw StoreError.cannotEditInvoicePayment }
        let updated = try draft.updatedTransaction(from: original, today: today)
        try repository.save(updated)
        if original.attachmentPath != updated.attachmentPath { removeAttachmentIfOrphan(original.attachmentPath, excluding: [id]) }
        reload()
        evaluateBudgetAlerts()
        Task { await rescheduleReminders() }
    }

    /// Exclui uma parcela, ela e as seguintes, ou todas.
    func deleteInstallments(of id: UUID, scope: InstallmentScope) throws {
        guard let tx = transactions.first(where: { $0.id == id }) else { throw StoreError.notFound }
        let ids = InstallmentEngine.idsToDelete(tx, scope: scope, in: transactions)
        let paths = transactions.filter { ids.contains($0.id) }.compactMap(\.attachmentPath)
        for i in ids { try repository.deleteTracked(Transaction.self, id: i) }
        for p in Set(paths) { removeAttachmentIfOrphan(p, excluding: Set(ids)) }
        reload()
        Task { await rescheduleReminders() }
    }

    func installmentCount(of id: UUID) -> Int {
        guard let tx = transactions.first(where: { $0.id == id }) else { return 0 }
        return InstallmentEngine.groupMembers(of: tx, in: transactions).count
    }

    // MARK: Comprovantes

    func attachImage(_ data: Data, fileExtension: String = "jpg") throws -> String {
        try attachments.save(data, fileExtension: fileExtension)
    }

    func attachmentData(_ path: String?) -> Data? { path.flatMap { attachments.load($0) } }

    func removeAttachmentIfOrphan(_ path: String?, excluding ids: Set<UUID> = []) {
        guard let path else { return }
        // lê do repositório: o array em memória ainda pode conter a transação recém-excluída
        let all = (try? repository.all(Transaction.self)) ?? transactions
        if !all.contains(where: { $0.attachmentPath == path && !ids.contains($0.id) }) { attachments.remove(path) }
    }

    // MARK: Divisão de despesas

    @discardableResult
    func addSplit(_ draft: SplitDraft) throws -> ExpenseSplit {
        guard hasHousehold else { throw StoreError.noHousehold }
        var split = try draft.build(members: members)
        if draft.createsTransaction, let account = draft.accountId {
            var t = Transaction(type: .expense, amount: split.total, date: draft.date, title: split.title,
                                status: FinanceCalendar.isBeforeDay(today, draft.date) ? .pending : .paid, accountId: account)
            t.memberId = split.paidBy
            try repository.save(t)
            split.transactionId = t.id
        }
        try repository.save(split)
        reload()
        return split
    }

    func deleteSplit(id: UUID) throws {
        try repository.deleteTracked(ExpenseSplit.self, id: id)
        reload()
    }

    var splitBalances: [UUID: Decimal] { SettlementEngine.balances(splits: splits, settlements: settlements) }
    var settlementPlan: [SettlementTransfer] { SettlementEngine.plan(splits: splits, settlements: settlements) }

    func settle(_ transfer: SettlementTransfer) throws {
        try repository.save(SettlementEngine.settle(transfer, on: today))
        reload()
    }

    // MARK: Mesada

    func addAllowance(_ draft: AllowanceDraft) throws {
        guard let me = activeMember, let id = draft.memberId, let kid = members.first(where: { $0.id == id }),
              let amount = draft.amount, let day = Int(draft.dayText), let from = draft.fromAccountId, let to = draft.toAccountId
        else { throw StoreError.notFound }
        let a = try AllowanceEngine.make(for: kid, amount: amount, dayOfMonth: day, from: from, to: to,
                                         startMonth: currentMonth, by: me)
        try repository.save(a)
        reload()
        _ = try payAllowancesDue()
    }

    func removeAllowance(id: UUID) throws {
        try repository.deleteTracked(Allowance.self, id: id)
        reload()
    }

    /// Paga as mesadas cujo dia já chegou (idempotente). Chamado ao abrir o app. Retorna quantas transferências gerou.
    @discardableResult
    func payAllowancesDue() throws -> Int {
        var count = 0
        for a in allowances {
            let result = AllowanceEngine.pay(a, asOf: today)
            guard !result.transactions.isEmpty else { continue }
            try repository.saveAll(result.transactions)
            try repository.save(result.allowance)
            count += result.transactions.count
        }
        if count > 0 { reload() }
        return count
    }

    // MARK: Metas de filhos

    func goals(for memberId: UUID?) -> [Goal] { GoalEngine.goals(for: memberId, in: goals) }
}
