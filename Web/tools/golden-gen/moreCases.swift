import Foundation

func moreCases() {
    // ---- Investimentos ----
    func inv(_ n: Int, _ name: String, _ cls: AssetClass, qty: String, avg: String, quote: String? = nil) -> Investment {
        var i = Investment(name: name, assetClass: cls, quantity: dec(qty), averagePrice: dec(avg), quote: quote.map(dec)); i.id = uid(n); i.createdAt = stampDate; i.updatedAt = stampDate; return i
    }
    let invs = [inv(1, "PETR4", .stock, qty: "100", avg: "30.5", quote: "35.25"), inv(2, "CDB", .fixedIncome, qty: "1", avg: "10000", quote: "10450.33"),
                inv(3, "HGLG11", .reit, qty: "10", avg: "160.33"), inv(4, "BTC", .crypto, qty: "0.0123", avg: "250000", quote: "300000"),
                inv(5, "VALE3", .stock, qty: "33", avg: "61.123", quote: "58.9"), inv(6, "Zerado", .stock, qty: "0", avg: "0")]
    add("invest.totals", "totals", input: ["investments": ents(invs)], expected: {
        let t = InvestmentEngine.totals(invs)
        return ["cost": S(t.cost), "value": S(t.value), "gain": S(t.gain), "return": S(t.returnPercent),
                "positions": invs.map { ["cost": S(InvestmentEngine.cost($0)), "value": S(InvestmentEngine.marketValue($0)), "gain": S(InvestmentEngine.gain($0)), "return": S(InvestmentEngine.returnPercent($0))] as J },
                "allocation": InvestmentEngine.allocation(invs).map { ["class": $0.assetClass.rawValue, "value": S($0.value), "percent": S($0.percent)] as J }] as J
    }())
    add("invest.totals", "totals vazio", input: ["investments": [Any]()], expected: {
        let t = InvestmentEngine.totals([])
        return ["cost": S(t.cost), "value": S(t.value), "gain": S(t.gain), "return": S(t.returnPercent), "positions": [Any](), "allocation": [Any]()] as J
    }())
    for (q, p) in [("50", "40"), ("0.5", "100.123"), ("1", "0")] {
        let r = try! InvestmentEngine.buy(invs[0], quantity: dec(q), price: dec(p))
        add("invest.buy", "buy \(q)@\(p)", input: ["investment": ent(invs[0]), "quantity": q, "price": p], expected: ["quantity": S(r.quantity), "averagePrice": S(r.averagePrice)] as J)
    }
    for (q, p) in [("40", "50"), ("100", "10"), ("101", "10"), ("0", "10")] {
        var exp: J
        do { let r = try InvestmentEngine.sell(invs[0], quantity: dec(q), price: dec(p)); exp = ["ok": true, "quantity": S(r.quantity), "realized": S(r.realizedProfit), "averagePrice": S(r.averagePrice)] }
        catch let e as FinanceError { exp = ["ok": false, "error": e.description] } catch { fatalError() }
        add("invest.sell", "sell \(q)@\(p)", input: ["investment": ent(invs[0]), "quantity": q, "price": p], expected: exp)
    }

    // ---- Patrimônio ----
    let accs = [acct(1, "Corrente", initial: "-200"), acct(2, "Poupança", .savings, initial: "1500.75"), acct(3, "Arq", initial: "999", archived: true)]
    let cards = [card(1, "Roxo", limit: "5000", closing: 5, due: 15)]
    var dbts: [Debt] = []
    var db = Debt(name: "Empréstimo", balance: dec("2000"), monthlyInterestRate: dec("0.02"), minimumPayment: dec("100")); db.id = uid(1); dbts.append(db)
    var db0 = Debt(name: "Quitada", balance: dec("0"), monthlyInterestRate: dec("0.02"), minimumPayment: dec("100")); db0.id = uid(2); dbts.append(db0)
    let nwTx = [tx(1, .income, "300", d(2026, 10, 1), "x", account: 1), tx(2, .expense, "600", d(2026, 10, 3), "Cartão", card: 1), tx(3, .expense, "100", d(2026, 10, 3), "Cartão2", card: 1)]
    let nw = NetWorthEngine.compute(accounts: accs, transactions: nwTx, investments: invs, debts: dbts, creditCards: cards)
    add("networth.compute", "networth", input: ["accounts": ents(accs), "transactions": ents(nwTx), "investments": ents(invs), "debts": ents(dbts), "cards": ents(cards)],
        expected: ["accountsAssets": S(nw.accountsAssets), "investmentsValue": S(nw.investmentsValue), "overdraft": S(nw.overdraft), "debts": S(nw.debts), "cardBalances": S(nw.cardBalances),
                   "assets": S(nw.assets), "liabilities": S(nw.liabilities), "netWorth": S(nw.netWorth)] as J)
    func snap(_ n: Int, _ m: YearMonth, _ a: String, _ l: String) -> NetWorthSnapshot { var s = NetWorthSnapshot(month: m, assets: dec(a), liabilities: dec(l)); s.id = uid(n); s.createdAt = stampDate; s.updatedAt = stampDate; return s }
    let snaps = [snap(1, YearMonth(year: 2026, month: 6), "10000", "2000"), snap(2, YearMonth(year: 2026, month: 8), "12000", "1500"), snap(3, YearMonth(year: 2026, month: 10), "13000", "1000")]
    let pts = NetWorthEngine.evolution(snaps, months: 6, endingAt: YearMonth(year: 2026, month: 10))
    add("networth.evolution", "evolution", input: ["snapshots": ents(snaps), "months": 6, "endingAt": YMj(YearMonth(year: 2026, month: 10))],
        expected: ["points": pts.map { ["month": YMj($0.month), "netWorth": S($0.netWorth)] as J }, "change": S(NetWorthEngine.change(pts))] as J)

    // ---- Divisão e acerto ----
    let (ana, bia, caio, davi) = (uid(1), uid(2), uid(3), uid(4))
    func splitJ(_ s: ExpenseSplit) -> J { ["total": S(s.total), "mode": s.mode.rawValue, "shares": s.shares.map { ["member": $0.memberId.uuidString, "percent": S($0.percent), "amount": S($0.amount)] as J }] }
    var splits: [ExpenseSplit] = []
    let splitInputs: [(String, String, UUID, [UUID], SplitMode, [UUID: Decimal])] = [
        ("Mercado", "100.01", ana, [ana, bia, caio], .equal, [:]),
        ("Aluguel", "2000", bia, [ana, bia], .percentage, [ana: dec("60"), bia: dec("40")]),
        ("Viagem", "999.99", caio, [ana, bia, caio, davi], .equal, [:]),
        ("Pizza", "75.55", davi, [ana, davi], .percentage, [ana: dec("33.33"), davi: dec("66.67")]),
    ]
    for (title, total, payer, parts, mode, pcts) in splitInputs {
        let s = try! SplitEngine.make(title: title, total: dec(total), date: d(2026, 10, 10), paidBy: payer, participants: parts, mode: mode, percentages: pcts)
        splits.append(s)
        add("split.make", "split \(title)", input: ["title": title, "total": total, "paidBy": payer.uuidString, "participants": parts.map { $0.uuidString }, "mode": mode.rawValue,
                                                      "percentages": Dictionary(uniqueKeysWithValues: pcts.map { ($0.key.uuidString, S($0.value)) })], expected: ["ok": true, "split": splitJ(s)] as J)
    }
    for (name, parts, pcts) in [("pct não soma", [ana, bia], [ana: dec("50"), bia: dec("40")]), ("pct negativo", [ana, bia], [ana: dec("120"), bia: dec("-20")]), ("pct faltando", [ana, bia], [ana: dec("100")]), ("sem participantes", [UUID](), [UUID: Decimal]())] {
        let input: J = ["title": "x", "total": "10", "paidBy": ana.uuidString, "participants": parts.map { $0.uuidString }, "mode": "percentage",
                        "percentages": Dictionary(uniqueKeysWithValues: pcts.map { ($0.key.uuidString, S($0.value)) })]
        do { _ = try SplitEngine.make(title: "x", total: dec("10"), date: d(2026, 10, 10), paidBy: ana, participants: parts, mode: .percentage, percentages: pcts); fatalError() }
        catch let e as FinanceError { add("split.make", name, input: input, expected: ["ok": false, "error": e.description] as J) } catch { fatalError() }
    }
    var st = SplitSettlement(fromMemberId: caio, toMemberId: ana, amount: dec("20"), date: d(2026, 10, 15)); st.id = uid(900); st.createdAt = stampDate; st.updatedAt = stampDate
    let planCases: [(String, [ExpenseSplit], [SplitSettlement])] = [("sem acertos", splits, []), ("com acerto", splits, [st]), ("so primeira", [splits[0]], []), ("vazio", [], [])]
    for (name, sp, se) in planCases {
        let bal = SettlementEngine.balances(splits: sp, settlements: se)
        let plan = SettlementEngine.plan(splits: sp, settlements: se)
        add("settlement.plan", name, input: ["splits": ents(sp), "settlements": ents(se)],
            expected: ["balances": Dictionary(uniqueKeysWithValues: bal.map { ($0.key.uuidString, S($0.value)) }),
                       "plan": plan.map { ["from": $0.from.uuidString, "to": $0.to.uuidString, "amount": S($0.amount)] as J }] as J)
    }

    // ---- Família ----
    let house = uid(70)
    func mem(_ n: Int, _ name: String, _ role: MemberRole, limit: String? = nil) -> FamilyMember {
        var m = FamilyMember(householdId: house, name: name, role: role, monthlySpendingLimit: limit.map(dec)); m.id = uid(n); m.createdAt = stampDate; m.updatedAt = stampDate; return m
    }
    let members = [mem(1, "Ana", .admin), mem(2, "Bia", .member), mem(3, "Caio", .dependent, limit: "100")]
    for r in MemberRole.allCases {
        let perms: [(String, FamilyPermission)] = [("manageMembers", .manageMembers), ("manageAllowances", .manageAllowances), ("approveSpending", .approveSpending), ("splitExpenses", .splitExpenses), ("viewFamilyView", .viewFamilyView), ("addTransactions", .addTransactions), ("manageSharedData", .manageSharedData)]
        add("family.can", "can \(r.rawValue)", input: ["role": r.rawValue], expected: Dictionary(uniqueKeysWithValues: perms.map { ($0.0, FamilyEngine.can(r, $0.1)) }))
    }
    // visibilidade
    let vAcc = [acct(1, "Conjunta"), acct(2, "Privada Ana", vis: .personal, owner: 1), acct(3, "Privada Bia", vis: .personal, owner: 2), acct(4, "Caio", owner: 3)]
    let vCat = [cat(1, "Mercado"), cat(2, "Presentes", vis: .personal, owner: 1), cat(3, "Segredo Bia", vis: .personal, owner: 2)]
    let vTx = [tx(1, .expense, "10", d(2026, 10, 1), "a", account: 1, cat: 1), tx(2, .expense, "20", d(2026, 10, 2), "b", account: 2, cat: 1), tx(3, .expense, "30", d(2026, 10, 3), "c", account: 3),
               tx(4, .expense, "40", d(2026, 10, 4), "d", account: 1, cat: 2), tx(5, .expense, "50", d(2026, 10, 5), "e", account: 4), tx(6, .expense, "60", d(2026, 10, 6), "f", account: 1, cat: 3, member: 2),
               tx(7, .expense, "70", d(2026, 10, 7), "g", account: 1, cat: 1, member: 3), tx(8, .expense, "80", d(2026, 10, 8), "h", account: nil, cat: 1)]
    for (vname, viewer, scope, scopeJ) in [("família viewer Ana", uid(1) as UUID?, FamilyScope.family, ["kind": "family"] as J), ("família viewer Bia", uid(2), .family, ["kind": "family"]),
                                          ("individual Ana por Ana", uid(1), .member(uid(1)), ["kind": "member", "id": uid(1).uuidString]), ("individual Ana por Bia", uid(2), .member(uid(1)), ["kind": "member", "id": uid(1).uuidString]),
                                          ("individual Caio por Ana", uid(1), .member(uid(3)), ["kind": "member", "id": uid(3).uuidString]), ("família sem viewer", nil, .family, ["kind": "family"])] {
        let vis = FamilyEngine.visibleTransactions(vTx, accounts: vAcc, categories: vCat, viewer: viewer, scope: scope)
        add("family.visibility", vname, input: ["transactions": ents(vTx), "accounts": ents(vAcc), "categories": ents(vCat), "viewer": U(viewer), "scope": scopeJ],
            expected: ["transactions": vis.map { $0.id.uuidString }, "accounts": FamilyEngine.visibleAccounts(vAcc, viewer: viewer, scope: scope).map { $0.id.uuidString },
                       "categories": FamilyEngine.visibleCategories(vCat, viewer: viewer).map { $0.id.uuidString }] as J)
    }
    // aprovação
    let apTx = [tx(1, .expense, "60", d(2026, 10, 3), "gasto", account: 1, member: 3), tx(2, .expense, "999", d(2026, 9, 3), "mês passado", account: 1, member: 3), tx(3, .transfer, "999", d(2026, 10, 3), "t", account: 1, dest: 2, member: 3),
                tx(4, .transfer, "999", d(2026, 10, 3), "p", account: 1, card: 1, invoice: uid(5), member: 3)]
    for amount in ["39.99", "40", "40.01", "500"] {
        let dec_ = ApprovalEngine.evaluate(member: members[2], amount: dec(amount), date: d(2026, 10, 20), transactions: apTx)
        var exp: J
        switch dec_ { case .allowed: exp = ["kind": "allowed"]; case .needsApproval(let l, let s): exp = ["kind": "needsApproval", "limit": S(l), "spent": S(s)] }
        add("family.evaluate", "evaluate \(amount)", input: ["member": ent(members[2]), "amount": amount, "date": "2026-10-20", "transactions": ents(apTx)], expected: exp)
    }
    add("family.evaluate", "admin sempre permitido", input: ["member": ent(members[0]), "amount": "9999", "date": "2026-10-20", "transactions": ents(apTx)], expected: ["kind": "allowed"] as J)
    // mesada
    func allowance(_ day: Int, start: YearMonth, last: YearMonth?, active: Bool = true) -> Allowance {
        var a = Allowance(memberId: uid(3), amount: dec("50.5"), dayOfMonth: day, fromAccountId: uid(1), toAccountId: uid(4), startMonth: start, lastPaidMonth: last, isActive: active)
        a.id = uid(80); a.createdAt = stampDate; a.updatedAt = stampDate; return a
    }
    let aCases: [(String, Allowance, Date)] = [
        ("primeira vez antes do dia", allowance(10, start: YearMonth(year: 2026, month: 10), last: nil), d(2026, 10, 9)),
        ("primeira vez no dia", allowance(10, start: YearMonth(year: 2026, month: 10), last: nil), d(2026, 10, 10)),
        ("atrasada 3 meses", allowance(5, start: YearMonth(year: 2026, month: 7), last: YearMonth(year: 2026, month: 7)), d(2026, 10, 20)),
        ("recupera no máximo 12", allowance(31, start: YearMonth(year: 2024, month: 1), last: nil), d(2026, 10, 31)),
        ("dia 31 em fev", allowance(31, start: YearMonth(year: 2026, month: 1), last: nil), d(2026, 3, 1)),
        ("inativa", allowance(5, start: YearMonth(year: 2026, month: 1), last: nil, active: false), d(2026, 10, 20)),
        ("em dia", allowance(5, start: YearMonth(year: 2026, month: 1), last: YearMonth(year: 2026, month: 10)), d(2026, 10, 20)),
    ]
    for (name, a, asOf) in aCases {
        let r = AllowanceEngine.pay(a, asOf: asOf)
        add("family.allowance", name, input: ["allowance": ent(a), "asOf": iso(asOf)],
            expected: ["due": AllowanceEngine.dueMonths(a, asOf: asOf).map(YMj), "last": r.allowance.lastPaidMonth.map(YMj) as Any? ?? NSNull(),
                       "transactions": r.transactions.map { ["date": iso($0.date), "amount": S($0.amount), "title": $0.title] as J }] as J)
    }
}
