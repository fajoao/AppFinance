import Foundation

func candJ(_ c: CandidateTransaction) -> J { ["date": iso(c.date), "title": c.title, "amount": S(c.amount), "externalId": c.externalId as Any? ?? NSNull(), "isDuplicate": c.isDuplicate] }
func resJ(_ r: ImportResult) -> J { ["candidates": r.candidates.map(candJ), "issues": r.issues.map { ["line": $0.line, "message": $0.message] as J }] }

func ioCases() {
    // ---- CSV ----
    let csvs: [(String, String)] = [
        ("cabeçalho pt ;", "Data;Descrição;Valor\n05/10/2026;Mercado Extra;-123,45\n06/10/2026;Salário;5.000,00\n"),
        ("cabeçalho débito/crédito", "Data;Histórico;Débito;Crédito\n01/10/2026;Padaria;12,50;\n02/10/2026;Pix recebido;;300,00\n"),
        ("sem cabeçalho", "05/10/2026;Café;-8,90\n06/10/2026;Estorno;8,90\n"),
        ("vírgula e aspas", "date,description,amount\n2026-10-05,\"Loja, filial 2\",-99.90\n2026-10-06,\"Com \"\"aspas\"\"\",10.00\n"),
        ("tab com id", "Data\tDescricao\tValor\tIdentificador\n05/10/2026\tUber\t-23,10\tABC123\n"),
        ("linhas inválidas", "Data;Descrição;Valor\n32/10/2026;Ruim;10\n05/10/2026;Sem valor;abc\n06/10/2026;Ok;1,00\n"),
        ("sem coluna data", "Foo;Bar\n1;2\n"),
        ("sem coluna valor", "Data;Descrição\n05/10/2026;x\n"),
        ("crlf e bom", "\u{FEFF}Data;Descrição;Valor\r\n05/10/2026;Linha;-1,00\r\n\r\n06/10/2026;Outra;2,00\r\n"),
        ("vazio", ""),
        ("quebra dentro de aspas", "Data;Descrição;Valor\n05/10/2026;\"Linha 1\nLinha 2\";-5,00\n"),
        ("data yy", "Data;Descrição;Valor\n05/10/26;Curto;-5,00\n"),
    ]
    for (name, text) in csvs { add("import.csv", name, input: ["text": text], expected: resJ(CSVParser.parse(text))) }

    // ---- OFX ----
    let ofxSGML = """
    OFXHEADER:100
    DATA:OFXSGML
    VERSION:102

    <OFX>
    <BANKMSGSRSV1><STMTTRNRS><STMTRS>
    <BANKTRANLIST>
    <STMTTRN>
    <TRNTYPE>DEBIT
    <DTPOSTED>20261005120000[-3:BRT]
    <TRNAMT>-123.45
    <FITID>2026100501
    <NAME>MERCADO EXTRA
    <MEMO>COMPRA DEBITO
    </STMTTRN>
    <STMTTRN>
    <TRNTYPE>CREDIT
    <DTPOSTED>20261006
    <TRNAMT>5000.00
    <FITID>2026100602
    <NAME>SALARIO
    </STMTTRN>
    <STMTTRN>
    <TRNTYPE>DEBIT
    <DTPOSTED>20261007
    <TRNAMT>-1.234,56
    <FITID>2026100703
    <MEMO>LOJA &amp; CIA
    </STMTTRN>
    <STMTTRN>
    <DTPOSTED>2026100
    <TRNAMT>-10.00
    <FITID>bad
    </STMTTRN>
    <STMTTRN>
    <DTPOSTED>20261008
    <TRNAMT>xx
    <FITID>bad2
    </STMTTRN>
    </BANKTRANLIST>
    </STMTRS></STMTTRNRS></BANKMSGSRSV1>
    </OFX>
    """
    let ofxXML = "<?xml version=\"1.0\"?><OFX><BANKTRANLIST><STMTTRN><DTPOSTED>20261101</DTPOSTED><TRNAMT>-50,00</TRNAMT><FITID>X1</FITID><NAME>Padaria</NAME><MEMO>Padaria</MEMO></STMTTRN></BANKTRANLIST></OFX>"
    for (name, text) in [("sgml", ofxSGML), ("xml", ofxXML), ("não é ofx", "hello"), ("vazio", "")] {
        add("import.ofx", name, input: ["text": text], expected: resJ(OFXParser.parse(text)))
    }

    // ---- Duplicatas ----
    let existing = [tx(1, .expense, "123.45", d(2026, 10, 5), "Mercado Extra compra", account: 1, ext: "2026100501"), tx(2, .income, "5000", d(2026, 10, 6), "Salário", account: 1),
                    tx(3, .expense, "10", d(2026, 10, 8), "Café", account: 1), tx(4, .expense, "10", d(2026, 10, 9), "Café", account: 1), tx(5, .transfer, "300", d(2026, 10, 10), "Entre contas", account: 1, dest: 2),
                    tx(6, .expense, "77", d(2026, 10, 11), "Outra conta", account: 2)]
    let cands = [CandidateTransaction(date: d(2026, 10, 5), title: "MERCADO EXTRA", amount: dec("-123.45"), externalId: "2026100501"),
                 CandidateTransaction(date: d(2026, 10, 6), title: "SALARIO", amount: dec("5000"), externalId: nil),
                 CandidateTransaction(date: d(2026, 10, 8), title: "café", amount: dec("-10"), externalId: nil),
                 CandidateTransaction(date: d(2026, 10, 8), title: "Café", amount: dec("-10"), externalId: nil),
                 CandidateTransaction(date: d(2026, 10, 9), title: "Cafe", amount: dec("10"), externalId: nil),
                 CandidateTransaction(date: d(2026, 10, 10), title: "Entre contas", amount: dec("-300"), externalId: nil),
                 CandidateTransaction(date: d(2026, 10, 11), title: "Outra conta", amount: dec("-77"), externalId: nil)]
    func candIn(_ c: CandidateTransaction) -> J { ["date": iso(c.date), "title": c.title, "amount": S(c.amount), "externalId": c.externalId as Any? ?? NSNull()] }
    for acc in [uid(1) as UUID?, uid(2), nil] {
        let marked = DuplicateDetector.mark(cands, existing: existing, accountId: acc)
        add("import.duplicates", "duplicatas conta \(acc.map { String($0.uuidString.suffix(1)) } ?? "nil")", input: ["candidates": cands.map(candIn), "existing": ents(existing), "accountId": U(acc)], expected: marked.map { $0.isDuplicate })
    }

    // ---- Exportação CSV ----
    let eAcc = [acct(1, "Corrente"), acct(2, "Poupança")]
    let eCat = [cat(1, "Mercado"), cat(2, "Salário", .income)]
    var t1 = Tag(name: "casa"); t1.id = uid(1); t1.createdAt = stampDate; t1.updatedAt = stampDate
    var t2 = Tag(name: "urgente;sim"); t2.id = uid(2); t2.createdAt = stampDate; t2.updatedAt = stampDate
    var e1 = tx(1, .expense, "123.45", d(2026, 10, 5), "=SOMA(A1)", account: 1, cat: 1); e1.tagIds = [uid(1), uid(2)]; e1.note = "linha 1\nlinha 2"
    let e2 = tx(2, .income, "5000", d(2026, 10, 1), "Salário \"bruto\"", account: 1, cat: 2)
    let e3 = tx(3, .transfer, "300", d(2026, 10, 3), "Transf; ok", status: .pending, account: 1, dest: 2)
    let e4 = tx(4, .expense, "-10", d(2026, 10, 4), "@estorno", account: 2)
    let e5 = tx(5, .expense, "1234567.8", d(2026, 10, 4), "+55 11", account: nil)
    let exTx = [e1, e2, e3, e4, e5]
    for (name, delim, comma) in [("padrão", ";", true), ("ponto decimal", ",", false), ("tab", "\t", true)] {
        var opt = CSVExportOptions(); opt.delimiter = Character(delim); opt.decimalComma = comma
        add("export.csv", "export \(name)", input: ["transactions": ents(exTx), "accounts": ents(eAcc), "categories": ents(eCat), "tags": ents([t1, t2]), "delimiter": delim, "decimalComma": comma],
            expected: CSVExporter.export(transactions: exTx, accounts: eAcc, categories: eCat, tags: [t1, t2], options: opt))
    }

    // ---- Sugestão de categoria ----
    let hist = [tx(1, .expense, "30", d(2026, 9, 1), "Padaria Pão Quente", cat: 3), tx(2, .expense, "35", d(2026, 9, 8), "Padaria Pão Quente", cat: 3), tx(3, .expense, "90", d(2026, 9, 9), "Mercado Extra Centro", cat: 4),
                tx(4, .expense, "80", d(2026, 9, 12), "Mercado Pão de Açúcar", cat: 4), tx(5, .expense, "25", d(2026, 9, 13), "Uber trip", cat: 5), tx(6, .income, "100", d(2026, 9, 14), "Uber reembolso", cat: 6),
                tx(7, .expense, "60", d(2026, 9, 15), "Cinema Centro", cat: 7), tx(8, .transfer, "10", d(2026, 9, 16), "Transferência", account: 1, dest: 2)]
    let kw: [UUID: [String]] = [uid(8): ["farmácia", "drogaria"]]
    var sug = CategorySuggester(history: hist, keywords: kw)
    _ = sug.suggest(for: "x")
    sug = CategorySuggester(history: hist, keywords: kw)
    let queries: [(String, TransactionType)] = [("Padaria Pão Quente", .expense), ("padaria PAO quente", .expense), ("Mercado Centro", .expense), ("Uber", .expense), ("Uber", .income), ("Drogaria São Paulo", .expense),
                                                ("Cinema", .expense), ("Loja desconhecida", .expense), ("", .expense), ("pix pagamento", .expense), ("Extra", .expense), ("Centro", .expense)]
    add("import.suggest", "suggest", input: ["history": ents(hist), "keywords": Dictionary(uniqueKeysWithValues: kw.map { ($0.key.uuidString, $0.value) }), "queries": queries.map { ["title": $0.0, "type": $0.1.rawValue] as J }],
        expected: queries.map { U(sug.suggest(for: $0.0, type: $0.1)) })

    // ---- Relatórios / IR ----
    let cats = [cat(1, "Moradia"), cat(2, "Aluguel", parent: 1), cat(3, "Mercado"), cat(4, "Saúde", tax: .health), cat(5, "Consulta", parent: 4), cat(6, "Escola", tax: .education), cat(7, "Salário", .income), cat(8, "Freela", .income)]
    var rt: [Transaction] = [
        tx(1, .income, "5000", d(2026, 3, 5), "Salário", account: 1, cat: 7, member: 1), tx(2, .income, "1200.55", d(2026, 4, 5), "Freela", account: 1, cat: 8, member: 1),
        tx(3, .expense, "1500", d(2026, 3, 6), "Aluguel", account: 1, cat: 2, member: 1), tx(4, .expense, "300.75", d(2026, 3, 7), "Mercado", account: 2, cat: 3, member: 2),
        tx(5, .expense, "250", d(2026, 4, 8), "Consulta", account: 1, cat: 5, member: 1), tx(6, .expense, "400", d(2026, 4, 9), "Escola Caio", account: 1, cat: 6, member: 3),
        tx(7, .expense, "3500", d(2026, 5, 9), "Escola Caio 2", account: 1, cat: 6, member: 3), tx(8, .expense, "800", d(2026, 5, 10), "Escola Ana", account: 1, cat: 6, member: 1),
        tx(9, .expense, "99", d(2026, 5, 11), "Pendente", status: .pending, account: 1, cat: 4), tx(10, .transfer, "1000", d(2026, 5, 12), "Transf", account: 1, dest: 2),
        tx(11, .transfer, "500", d(2026, 5, 13), "Fatura", account: 1, card: 1, invoice: uid(3)), tx(12, .expense, "45", d(2026, 5, 14), "Sem cat", account: nil, card: 1),
        tx(13, .expense, "10", d(2025, 12, 31), "Ano passado", account: 1, cat: 3), tx(14, .income, "100", d(2026, 5, 15), "Sem membro", account: 1, cat: 7),
    ]
    rt[13].memberId = nil
    func groupJ(_ g: GroupTotal) -> J { ["id": U(g.id), "income": S(g.income), "expense": S(g.expense), "count": g.count, "percent": S(g.percentOfExpense)] }
    let filters: [(String, ReportFilter, J)] = [
        ("tudo 2026", ReportFilter(from: d(2026, 1, 1), to: d(2026, 12, 31)), ["from": "2026-01-01", "to": "2026-12-31"]),
        ("só pagos", ReportFilter(from: d(2026, 1, 1), to: d(2026, 12, 31), onlyPaid: true), ["from": "2026-01-01", "to": "2026-12-31", "onlyPaid": true]),
        ("categoria pai", ReportFilter(from: d(2026, 1, 1), to: d(2026, 12, 31), categoryIds: [uid(4)]), ["from": "2026-01-01", "to": "2026-12-31", "categoryIds": [uid(4).uuidString]]),
        ("membro 3", ReportFilter(from: d(2026, 1, 1), to: d(2026, 12, 31), memberIds: [uid(3)]), ["from": "2026-01-01", "to": "2026-12-31", "memberIds": [uid(3).uuidString]]),
        ("conta 2", ReportFilter(from: d(2026, 1, 1), to: d(2026, 12, 31), accountIds: [uid(2)]), ["from": "2026-01-01", "to": "2026-12-31", "accountIds": [uid(2).uuidString]]),
        ("abril", ReportFilter(from: d(2026, 4, 1), to: d(2026, 4, 30)), ["from": "2026-04-01", "to": "2026-04-30"]),
        ("vazio", ReportFilter(from: d(2030, 1, 1), to: d(2030, 12, 31)), ["from": "2030-01-01", "to": "2030-12-31"]),
    ]
    for (name, f, fj) in filters {
        let r = ReportEngine.run(f, transactions: rt, categories: cats)
        let names = ReportNames(categories: Dictionary(uniqueKeysWithValues: cats.map { ($0.id, $0.name) }), members: [uid(1): "Ana", uid(2): "Bia", uid(3): "Caio"], accounts: [uid(1): "Corrente", uid(2): "Poupança"])
        let doc = ReportDocumentBuilder.build(r, title: "Relatório", names: names, generatedOn: d(2026, 10, 20))
        add("report.run", name, input: ["filter": fj, "transactions": ents(rt), "categories": ents(cats),
                                         "names": ["categories": Dictionary(uniqueKeysWithValues: names.categories.map { ($0.key.uuidString, $0.value) }), "members": Dictionary(uniqueKeysWithValues: names.members.map { ($0.key.uuidString, $0.value) }),
                                                   "accounts": Dictionary(uniqueKeysWithValues: names.accounts.map { ($0.key.uuidString, $0.value) })], "generatedOn": "2026-10-20"],
            expected: ["income": S(r.income), "expense": S(r.expense), "net": S(r.net), "count": r.count, "byCategory": r.byCategory.map(groupJ), "byMember": r.byMember.map(groupJ), "byAccount": r.byAccount.map(groupJ),
                       "byMonth": r.byMonth.map { ["month": YMj($0.month), "income": S($0.income), "expense": S($0.expense)] as J }, "transactionIds": r.transactions.map { $0.id.uuidString },
                       "csv": doc.csv(), "subtitle": doc.subtitle, "generatedOn": doc.generatedOn] as J)
    }
    for (name, member, onlyPaid) in [("família", nil as UUID?, true), ("Caio", uid(3), true), ("Ana", uid(1), true), ("família todos", nil, false)] {
        let s = TaxEngine.summary(year: 2026, transactions: rt, categories: cats, memberId: member, onlyPaid: onlyPaid)
        let names = ReportNames(categories: Dictionary(uniqueKeysWithValues: cats.map { ($0.id, $0.name) }))
        let doc = TaxEngine.document(s, names: names, memberName: member == nil ? nil : name, generatedOn: d(2026, 10, 20))
        add("tax.summary", "IR \(name) paid=\(onlyPaid)", input: ["year": 2026, "transactions": ents(rt), "categories": ents(cats), "memberId": U(member), "onlyPaid": onlyPaid,
                                                              "categoryNames": Dictionary(uniqueKeysWithValues: names.categories.map { ($0.key.uuidString, $0.value) }), "memberName": member == nil ? NSNull() : name as Any],
            expected: ["totalIncome": S(s.totalIncome), "incomeLines": s.incomeLines.map { ["categoryId": U($0.categoryId), "total": S($0.total)] as J },
                       "deductionLines": s.deductionLines.map { ["kind": $0.kind.rawValue, "categoryId": U($0.categoryId), "total": S($0.total), "count": $0.count] as J },
                       "health": S(s.healthTotal), "education": S(s.educationTotal), "educationDeductible": S(s.educationDeductible), "educationExcess": S(s.educationExcess),
                       "totalDeductible": S(s.totalDeductible), "csv": doc.csv(), "subtitle": doc.subtitle] as J)
    }
}

func syncCases() {
    func acc(_ n: Int, _ name: String, at: Double) -> Account { var a = acct(n, name); a.updatedAt = Date(timeIntervalSinceReferenceDate: at); return a }
    func t(_ n: Int, _ title: String, at: Double) -> Transaction { var x = tx(n, .expense, "10", d(2026, 10, 1), title, account: 1); x.updatedAt = Date(timeIntervalSinceReferenceDate: at); return x }
    func tomb(_ type: String, _ id: Int, at: Double) -> Tombstone {
        var x = Tombstone(entityType: type, entityId: uid(id), deletedAt: Date(timeIntervalSinceReferenceDate: at)); x.id = uid(1000 + id); x.updatedAt = x.deletedAt; x.createdAt = x.deletedAt; return x
    }
    var local = FinanceSnapshot(); var remote = FinanceSnapshot()
    local.accounts = [acc(1, "Local novo", at: 900), acc(2, "Só local", at: 100), acc(3, "Remoto mais novo", at: 100)]
    remote.accounts = [acc(1, "Remoto velho", at: 800), acc(3, "Remoto vence", at: 500), acc(4, "Só remoto", at: 50)]
    local.transactions = [t(1, "L1", at: 100), t(2, "L2 editada depois da exclusão", at: 700), t(3, "L3 será excluída", at: 100)]
    remote.transactions = [t(1, "R1 mais novo", at: 200), t(4, "R4 novo", at: 300), t(5, "R5 excluída no remoto", at: 100)]
    remote.tombstones = [tomb("Transaction", 3, at: 600), tomb("Transaction", 5, at: 400), tomb("Transaction", 2, at: 600)]
    local.tombstones = [tomb("Transaction", 7, at: 50)]
    let m = SyncEngine.merge(local: local, remote: remote)
    func snapJ(_ s: FinanceSnapshot) -> J {
        ["accounts": s.accounts.map { ["id": $0.id.uuidString, "name": $0.name] as J }, "transactions": s.transactions.map { ["id": $0.id.uuidString, "title": $0.title] as J },
         "tombstones": s.tombstones.map { ["entityType": $0.entityType, "entityId": $0.entityId.uuidString] as J }]
    }
    add("sync.merge", "merge básico", input: ["local": ent(local), "remote": ent(remote)],
        expected: ["snapshot": snapJ(m.snapshot), "applied": m.report.applied, "keptLocal": m.report.keptLocal, "deleted": m.report.deleted] as J)
    let ch = SyncEngine.changes(in: local, since: Date(timeIntervalSinceReferenceDate: 150))
    add("sync.changes", "changes since", input: ["snapshot": ent(local), "since": 150.0], expected: ["accounts": ch.accounts.map { $0.id.uuidString }, "transactions": ch.transactions.map { $0.id.uuidString }, "tombstones": ch.tombstones.map { $0.entityId.uuidString }] as J)
}
