import Foundation

// MARK: - Divisão de despesas entre membros

enum SplitEngine {
    /// Cria a divisão. `.equal` reparte em centavos exatos (a última parte absorve o resto);
    /// `.percentage` exige percentuais não negativos para todos os participantes somando 100.
    static func make(title: String, total: Decimal, date: Date, paidBy: UUID, participants: [UUID],
                     mode: SplitMode, percentages: [UUID: Decimal] = [:], transactionId: UUID? = nil) throws -> ExpenseSplit {
        guard total > 0 else { throw FinanceError.invalidAmount }
        var seen = Set<UUID>()
        let members = participants.filter { seen.insert($0).inserted }
        guard !members.isEmpty else { throw FinanceError.noParticipants }

        let shares: [SplitShare]
        switch mode {
        case .equal:
            let parts = Money.split(total, into: members.count)
            shares = zip(members, parts).map { SplitShare(memberId: $0, percent: nil, amount: $1) }
        case .percentage:
            let weights = members.map { percentages[$0] ?? -1 }
            guard weights.allSatisfy({ $0 >= 0 }), weights.reduce(0, +) == 100 else { throw FinanceError.invalidPercentages }
            let parts = Money.allocate(total, weights: weights)
            shares = (0..<members.count).map { SplitShare(memberId: members[$0], percent: weights[$0], amount: parts[$0]) }
        }
        return ExpenseSplit(title: title, total: total.rounded(scale: 2), date: date, paidBy: paidBy, mode: mode,
                            shares: shares, transactionId: transactionId)
    }
}

/// Uma transferência sugerida para quitar a conta: `from` paga `amount` a `to`.
struct SettlementTransfer: Sendable, Equatable {
    var from: UUID
    var to: UUID
    var amount: Decimal
}

enum SettlementEngine {
    /// Saldo líquido por membro: positivo = tem a receber; negativo = deve.
    static func balances(splits: [ExpenseSplit], settlements: [SplitSettlement]) -> [UUID: Decimal] {
        var result: [UUID: Decimal] = [:]
        for s in splits {
            result[s.paidBy, default: 0] += s.total
            for share in s.shares { result[share.memberId, default: 0] -= share.amount }
        }
        for p in settlements {
            result[p.fromMemberId, default: 0] += p.amount
            result[p.toMemberId, default: 0] -= p.amount
        }
        return result.filter { $0.value != 0 }
    }

    /// Transferências que zeram os saldos. Casa sempre o maior devedor com o maior credor; cada transferência
    /// quita pelo menos uma das pontas, então o total é de no máximo (pessoas com saldo - 1). O mínimo absoluto
    /// é um problema NP-difícil (partição de subconjuntos); esta heurística é a usada na prática.
    static func transfers(from balances: [UUID: Decimal]) -> [SettlementTransfer] {
        func order(_ a: (key: UUID, value: Decimal), _ b: (key: UUID, value: Decimal)) -> Bool {
            a.value != b.value ? a.value > b.value : a.key.uuidString < b.key.uuidString
        }
        var creditors = balances.filter { $0.value > 0 }.sorted(by: order).map { ($0.key, $0.value) }
        var debtors = balances.filter { $0.value < 0 }.sorted { !order($0, $1) }.map { ($0.key, -$0.value) }
        var result: [SettlementTransfer] = []
        while let c = creditors.first, let d = debtors.first {
            let amount = min(c.1, d.1)
            result.append(SettlementTransfer(from: d.0, to: c.0, amount: amount))
            creditors[0].1 -= amount; debtors[0].1 -= amount
            if creditors[0].1 == 0 { creditors.removeFirst() }
            if debtors[0].1 == 0 { debtors.removeFirst() }
            // reordena: o maior saldo restante passa a ser o primeiro
            creditors.sort { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.uuidString < $1.0.uuidString }
            debtors.sort { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0.uuidString < $1.0.uuidString }
        }
        return result
    }

    static func plan(splits: [ExpenseSplit], settlements: [SplitSettlement]) -> [SettlementTransfer] {
        transfers(from: balances(splits: splits, settlements: settlements))
    }

    /// Registra que a transferência foi paga.
    static func settle(_ transfer: SettlementTransfer, on date: Date) -> SplitSettlement {
        SplitSettlement(fromMemberId: transfer.from, toMemberId: transfer.to, amount: transfer.amount, date: date)
    }
}
