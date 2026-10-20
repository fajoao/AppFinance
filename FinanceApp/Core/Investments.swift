import Foundation

// MARK: - Carteira de investimentos (manual)

struct AllocationSlice: Sendable, Equatable {
    var assetClass: AssetClass
    var value: Decimal
    /// 0...100, 2 casas; a soma das fatias é exatamente 100 (a última absorve o resto).
    var percent: Decimal
}

struct PortfolioTotals: Sendable, Equatable {
    var cost: Decimal
    var value: Decimal
    var gain: Decimal { value - cost }
    /// Rentabilidade simples = ganho / custo. nil sem custo.
    var returnPercent: Decimal?
}

enum InvestmentEngine {
    static func cost(_ i: Investment) -> Decimal { i.quantity * i.averagePrice }

    /// Valor atual = quantidade x cotação manual (ou o preço médio, se ainda não há cotação).
    static func marketValue(_ i: Investment) -> Decimal { i.quantity * (i.quote ?? i.averagePrice) }

    static func gain(_ i: Investment) -> Decimal { marketValue(i) - cost(i) }

    /// Rentabilidade simples (sem anualização), em %, 2 casas. nil quando o custo é zero.
    static func returnPercent(_ i: Investment) -> Decimal? {
        percent(gain(i), over: cost(i))
    }

    private static func percent(_ part: Decimal, over base: Decimal) -> Decimal? {
        base == 0 ? nil : (part * 100 / base).rounded(scale: 2)
    }

    /// Compra: novo preço médio ponderado (4 casas).
    static func buy(_ i: Investment, quantity: Decimal, price: Decimal) throws -> Investment {
        guard quantity > 0 else { throw FinanceError.invalidQuantity }
        guard price >= 0 else { throw FinanceError.invalidAmount }
        var r = i
        let total = i.quantity + quantity
        r.averagePrice = ((cost(i) + quantity * price) / total).rounded(scale: 4)
        r.quantity = total
        r.updatedAt = Date()
        return r
    }

    /// Venda: realiza lucro sobre o preço médio, que não muda.
    static func sell(_ i: Investment, quantity: Decimal, price: Decimal) throws -> Investment {
        guard quantity > 0 else { throw FinanceError.invalidQuantity }
        guard quantity <= i.quantity else { throw FinanceError.insufficientQuantity }
        guard price >= 0 else { throw FinanceError.invalidAmount }
        var r = i
        r.quantity -= quantity
        r.realizedProfit += quantity * (price - i.averagePrice)
        r.updatedAt = Date()
        return r
    }

    static func updateQuote(_ i: Investment, quote: Decimal, date: Date) throws -> Investment {
        guard quote >= 0 else { throw FinanceError.invalidAmount }
        var r = i
        r.quote = quote; r.quoteDate = date; r.updatedAt = Date()
        return r
    }

    static func totals(_ list: [Investment]) -> PortfolioTotals {
        let c = list.reduce(Decimal(0)) { $0 + cost($1) }
        let v = list.reduce(Decimal(0)) { $0 + marketValue($1) }
        return PortfolioTotals(cost: c, value: v, returnPercent: percent(v - c, over: c))
    }

    /// Alocação por classe, da maior para a menor (empate: ordem de `AssetClass`).
    static func allocation(_ list: [Investment]) -> [AllocationSlice] {
        var byClass: [AssetClass: Decimal] = [:]
        for i in list { byClass[i.assetClass, default: 0] += marketValue(i) }
        let order = AssetClass.allCases
        let sorted = byClass.filter { $0.value > 0 }.sorted {
            $0.value != $1.value ? $0.value > $1.value : order.firstIndex(of: $0.key)! < order.firstIndex(of: $1.key)!
        }
        let total = sorted.reduce(Decimal(0)) { $0 + $1.value }
        guard total > 0 else { return [] }
        let percents = Money.allocate(100, weights: sorted.map(\.value))
        return zip(sorted, percents).map { AllocationSlice(assetClass: $0.key, value: $0.value, percent: $1) }
    }
}

// MARK: - Patrimônio líquido

struct NetWorth: Sendable, Equatable {
    /// Soma dos saldos positivos das contas (não arquivadas).
    var accountsAssets: Decimal
    var investmentsValue: Decimal
    /// Saldos negativos de contas (cheque especial), em valor positivo.
    var overdraft: Decimal
    /// Saldo devedor das dívidas cadastradas.
    var debts: Decimal
    /// Faturas e parcelas ainda não pagas (limite usado dos cartões).
    var cardBalances: Decimal
    var assets: Decimal { accountsAssets + investmentsValue }
    var liabilities: Decimal { overdraft + debts + cardBalances }
    var netWorth: Decimal { assets - liabilities }
}

struct NetWorthPoint: Sendable, Equatable {
    var month: YearMonth
    /// nil = não há registro naquele mês.
    var netWorth: Decimal?
}

enum NetWorthEngine {
    static func compute(accounts: [Account], transactions: [Transaction], investments: [Investment],
                        debts: [Debt], creditCards: [CreditCard], asOf: Date? = nil) -> NetWorth {
        var positive: Decimal = 0, overdraft: Decimal = 0
        for a in accounts where !a.isArchived {
            let b = BalanceEngine.balance(of: a, transactions: transactions, asOf: asOf)
            if b >= 0 { positive += b } else { overdraft += -b }
        }
        let cards = creditCards.filter { !$0.isArchived }.reduce(Decimal(0)) {
            $0 + max(CreditCardEngine.usedLimit(card: $1, transactions: transactions), 0)
        }
        return NetWorth(accountsAssets: positive, investmentsValue: InvestmentEngine.totals(investments).value,
                        overdraft: overdraft, debts: debts.reduce(Decimal(0)) { $0 + max($1.balance, 0) }, cardBalances: cards)
    }

    static func snapshot(_ nw: NetWorth, month: YearMonth) -> NetWorthSnapshot {
        NetWorthSnapshot(month: month, assets: nw.assets, liabilities: nw.liabilities)
    }

    /// Um registro por mês: se já existe, atualiza valores e mantém o id.
    static func upsert(_ snapshot: NetWorthSnapshot, into list: [NetWorthSnapshot]) -> (list: [NetWorthSnapshot], saved: NetWorthSnapshot) {
        var result = list
        if let i = result.firstIndex(where: { $0.month == snapshot.month }) {
            result[i].assets = snapshot.assets
            result[i].liabilities = snapshot.liabilities
            result[i].updatedAt = snapshot.updatedAt
            return (result.sorted { $0.month < $1.month }, result[i])
        }
        result.append(snapshot)
        return (result.sorted { $0.month < $1.month }, snapshot)
    }

    /// Últimos `months` meses até `endingAt`, em ordem cronológica.
    static func evolution(_ list: [NetWorthSnapshot], months: Int, endingAt: YearMonth) -> [NetWorthPoint] {
        (0..<max(months, 1)).reversed().map { back in
            let m = endingAt.adding(months: -back)
            return NetWorthPoint(month: m, netWorth: list.first { $0.month == m }?.netWorth)
        }
    }

    /// Variação entre o primeiro e o último ponto com dado (nil com menos de 2).
    static func change(_ points: [NetWorthPoint]) -> Decimal? {
        let known = points.compactMap(\.netWorth)
        guard known.count >= 2 else { return nil }
        return known.last! - known.first!
    }
}
