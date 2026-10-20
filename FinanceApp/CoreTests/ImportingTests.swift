import Foundation

func importingTests() -> [TestCase] {
    [
        TestCase("CSV: cabeçalho pt-BR com ';', valores 1.234,56 e datas dd/MM/yyyy") { t in
            let csv = "Data;Descrição;Valor\n01/03/2025;Supermercado Extra;-1.234,56\n05/03/2025;Salário;5.000,00\n"
            let r = CSVParser.parse(csv)
            t.equal(r.issues.count, 0); t.equal(r.candidates.count, 2)
            t.equal(ymd(r.candidates[0].date), "2025-03-01"); t.equal(r.candidates[0].title, "Supermercado Extra")
            t.equal(r.candidates[0].amount, dec("-1234.56")); t.equal(r.candidates[0].type, .expense)
            t.equal(r.candidates[1].amount, 5000); t.equal(r.candidates[1].type, .income)
        },
        TestCase("CSV: delimitador ',', aspas, vírgula dentro de campo, aspas escapadas e quebra de linha") { t in
            let csv = "date,description,amount\n2025-01-31,\"Padaria, Pão & Cia\",-12.50\n2025-02-01,\"Loja \"\"X\"\"\",\"-1,000.00\"\n2025-02-02,\"linha1\nlinha2\",3\n"
            let r = CSVParser.parse(csv)
            t.equal(r.candidates.count, 3)
            t.equal(r.candidates[0].title, "Padaria, Pão & Cia"); t.equal(r.candidates[0].amount, dec("-12.50"))
            t.equal(r.candidates[1].title, "Loja \"X\""); t.equal(r.candidates[1].amount, -1000)
            t.equal(r.candidates[2].title, "linha1\nlinha2")
        },
        TestCase("CSV: colunas fora de ordem, débito/crédito, id externo, CRLF e BOM") { t in
            let csv = "\u{FEFF}Identificador;Data;Histórico;Débito;Crédito\r\nA1;10/01/2025;PIX Maria;50,00;\r\nA2;11/01/2025;Depósito;;200,00\r\n"
            let r = CSVParser.parse(csv)
            t.equal(r.candidates.count, 2); t.equal(r.issues.count, 0)
            t.equal(r.candidates[0].amount, -50); t.equal(r.candidates[0].externalId, "A1"); t.equal(r.candidates[0].title, "PIX Maria")
            t.equal(r.candidates[1].amount, 200)
        },
        TestCase("CSV: sem cabeçalho assume data, descrição, valor") { t in
            let r = CSVParser.parse("01/02/2025;Café;-8,90\n02/02/2025;Troco;1,10")
            t.equal(r.candidates.count, 2); t.equal(r.candidates[0].amount, dec("-8.90"))
        },
        TestCase("CSV: linhas inválidas viram issues, sem abortar") { t in
            let csv = "data;descricao;valor\n31/02/2025;Ruim;10,00\n01/03/2025;Bom;10,00\n02/03/2025;SemValor;abc\n\n03/03/2025;Bom2;-1,00\n"
            let r = CSVParser.parse(csv)
            t.equal(r.candidates.count, 2)
            t.equal(r.issues.map(\.line), [2, 4])
        },
        TestCase("CSV: cabeçalho sem coluna de data ou valor e arquivo vazio") { t in
            t.equal(CSVParser.parse("nome;preco\nx;1").issues.count, 1)
            t.equal(CSVParser.parse("data;descricao\n01/01/2025;x").issues.count, 1)
            let e = CSVParser.parse("")
            t.equal(e.candidates.count, 0); t.equal(e.issues.count, 0)
        },
        TestCase("CSV: data bissexta 29/02 válida em 2024 e inválida em 2025; ano com 2 dígitos") { t in
            t.equal(ymd(DateParsing.parse("29/02/2024")!), "2024-02-29")
            t.isNil(DateParsing.parse("29/02/2025"))
            t.equal(ymd(DateParsing.parse("05/03/25")!), "2025-03-05")
            t.equal(ymd(DateParsing.parse("31-12-2024")!), "2024-12-31")
            t.equal(ymd(DateParsing.parse("2025.01.02")!), "2025-01-02")
            t.isNil(DateParsing.parse("13/13/2025")); t.isNil(DateParsing.parse("abc")); t.isNil(DateParsing.parse("1/2"))
        },
        TestCase("CSV: Latin-1 / Windows-1252") { t in
            let data = "data;descricao;valor\n01/01/2025;Açaí;-5,00\n".data(using: .windowsCP1252)!
            t.equal(CSVParser.parse(data: data).candidates.first?.title, "Açaí")
        },
        TestCase("OFX SGML (v1): transações, FITID, sinal, data com hora/fuso") { t in
            let ofx = """
            OFXHEADER:100
            DATA:OFXSGML
            <OFX><BANKMSGSRSV1><STMTTRNRS><STMTRS><BANKTRANLIST>
            <STMTTRN>
            <TRNTYPE>DEBIT
            <DTPOSTED>20250115120000[-3:BRT]
            <TRNAMT>-45.90
            <FITID>2025011501
            <MEMO>COMPRA MERCADO
            </STMTTRN>
            <STMTTRN>
            <TRNTYPE>CREDIT
            <DTPOSTED>20250131
            <TRNAMT>1500.00
            <FITID>2025013101
            <NAME>EMPRESA
            <MEMO>SALARIO
            </STMTTRN>
            </BANKTRANLIST></STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>
            """
            let r = OFXParser.parse(ofx)
            t.equal(r.issues.count, 0); t.equal(r.candidates.count, 2)
            t.equal(ymd(r.candidates[0].date), "2025-01-15"); t.equal(r.candidates[0].amount, dec("-45.90"))
            t.equal(r.candidates[0].externalId, "2025011501"); t.equal(r.candidates[0].title, "COMPRA MERCADO")
            t.equal(r.candidates[1].title, "EMPRESA - SALARIO"); t.equal(r.candidates[1].amount, 1500)
        },
        TestCase("OFX SGML sem </STMTTRN> e XML (v2), vírgula decimal e entidades") { t in
            let sgml = "<OFX><BANKTRANLIST><STMTTRN><DTPOSTED>20241231<TRNAMT>-10,50<FITID>1<NAME>A &amp; B<STMTTRN><DTPOSTED>20250101<TRNAMT>7.25<FITID>2<NAME>C</BANKTRANLIST></OFX>"
            let r = OFXParser.parse(sgml)
            t.equal(r.candidates.count, 2)
            t.equal(r.candidates[0].amount, dec("-10.50")); t.equal(r.candidates[0].title, "A & B")
            t.equal(ymd(r.candidates[1].date), "2025-01-01")
            let xml = "<?xml version=\"1.0\"?><OFX><STMTTRN><DTPOSTED>20240229000000</DTPOSTED><TRNAMT>-1.00</TRNAMT><FITID>X</FITID><NAME>Bissexto</NAME></STMTTRN></OFX>"
            let x = OFXParser.parse(xml)
            t.equal(ymd(x.candidates[0].date), "2024-02-29"); t.equal(x.candidates[0].title, "Bissexto")
        },
        TestCase("OFX: transação inválida vira issue; arquivo não-OFX") { t in
            let bad = "<OFX><STMTTRN><DTPOSTED>20250230<TRNAMT>1.00</STMTTRN><STMTTRN><DTPOSTED>20250101<TRNAMT>x</STMTTRN><STMTTRN><DTPOSTED>20250101<TRNAMT>1.00<NAME>ok</STMTTRN></OFX>"
            let r = OFXParser.parse(bad)
            t.equal(r.candidates.count, 1); t.equal(r.issues.count, 2)
            t.equal(OFXParser.parse("hello").issues.count, 1)
        },
        TestCase("duplicadas: por FITID") { t in
            let acc = UUID()
            var existing = tx(.expense, "10", D(2025, 1, 1), "Qualquer", account: acc); existing.externalId = "F1"
            let c = [CandidateTransaction(date: D(2025, 5, 5), title: "outro", amount: -999, externalId: "F1"),
                     CandidateTransaction(date: D(2025, 5, 5), title: "outro", amount: -999, externalId: "F2")]
            t.equal(DuplicateDetector.mark(c, existing: [existing], accountId: acc).map(\.isDuplicate), [true, false])
        },
        TestCase("duplicadas: data + valor + descrição normalizada (acentos, caixa, contida)") { t in
            let acc = UUID()
            let existing = [tx(.expense, "45.90", D(2025, 1, 15), "Padaria São José", account: acc), tx(.income, "100", D(2025, 1, 16), "Pix recebido", account: acc)]
            let c = [CandidateTransaction(date: D(2025, 1, 15), title: "PADARIA SAO JOSE", amount: dec("-45.90"), externalId: nil),
                     CandidateTransaction(date: D(2025, 1, 15), title: "Padaria São José", amount: dec("-45.91"), externalId: nil),  // valor diferente
                     CandidateTransaction(date: D(2025, 1, 14), title: "Padaria São José", amount: dec("-45.90"), externalId: nil),  // dia diferente
                     CandidateTransaction(date: D(2025, 1, 16), title: "PIX", amount: 100, externalId: nil),                        // contida
                     CandidateTransaction(date: D(2025, 1, 16), title: "Pix recebido", amount: -100, externalId: nil)]               // sinal diferente
            t.equal(DuplicateDetector.mark(c, existing: existing, accountId: acc).map(\.isDuplicate), [true, false, false, true, false])
        },
        TestCase("duplicadas: cada lançamento existente consome só uma candidata; outras contas ignoradas") { t in
            let acc = UUID()
            let existing = [tx(.expense, "5", D(2025, 1, 1), "Café", account: acc)]
            let two = [CandidateTransaction(date: D(2025, 1, 1), title: "Café", amount: -5, externalId: nil),
                       CandidateTransaction(date: D(2025, 1, 1), title: "Café", amount: -5, externalId: nil)]
            t.equal(DuplicateDetector.mark(two, existing: existing, accountId: acc).map(\.isDuplicate), [true, false])
            t.equal(DuplicateDetector.mark(two, existing: existing, accountId: UUID()).map(\.isDuplicate), [false, false])
            t.equal(DuplicateDetector.mark(two, existing: existing).map(\.isDuplicate), [true, false])
        },
        TestCase("candidata -> Transaction com tipo e magnitude corretos") { t in
            let acc = UUID(), cat = UUID()
            let e = CandidateTransaction(date: D(2025, 1, 1), title: "x", amount: dec("-12.34"), externalId: "Z").toTransaction(accountId: acc, categoryId: cat)
            t.equal(e.type, .expense); t.equal(e.amount, dec("12.34")); t.equal(e.accountId, acc); t.equal(e.categoryId, cat); t.equal(e.externalId, "Z")
            let i = CandidateTransaction(date: D(2025, 1, 1), title: "x", amount: 7, externalId: nil).toTransaction(accountId: acc)
            t.equal(i.type, .income); t.equal(i.amount, 7)
        },
    ]
}

func exportSuggestTests() -> [TestCase] {
    [
        TestCase("exportação CSV: cabeçalho, ordenação por data, sinais e vírgula decimal") { t in
            let acc = Account(name: "Nubank", type: .checking)
            let cat = Category(name: "Mercado", kind: .expense)
            let tag = Tag(name: "casa"), tag2 = Tag(name: "fixo")
            var a = tx(.expense, "1234.56", D(2025, 3, 2), "Supermercado", account: acc.id, category: cat.id); a.tagIds = [tag.id, tag2.id]
            let b = tx(.income, "10", D(2025, 3, 1), "Venda", status: .pending, account: acc.id)
            let c = tx(.transfer, "5", D(2025, 3, 3), "Transf", account: acc.id)
            let out = CSVExporter.export(transactions: [a, b, c], accounts: [acc], categories: [cat], tags: [tag, tag2])
            let lines = out.split(separator: "\n").map(String.init)
            t.equal(lines[0], "data;descricao;tipo;valor;status;conta;categoria;tags;observacao")
            t.equal(lines[1], "01/03/2025;Venda;receita;10,00;pendente;Nubank;;;")
            t.equal(lines[2], "02/03/2025;Supermercado;despesa;-1234,56;pago;Nubank;Mercado;casa|fixo;")
            t.equal(lines[3], "03/03/2025;Transf;transferencia;-5,00;pago;Nubank;;;")
            t.check(out.hasSuffix("\n"))
        },
        TestCase("exportação CSV: escape de delimitador, aspas, quebra de linha e fórmulas; ponto decimal") { t in
            var x = tx(.expense, "1.5", D(2025, 1, 1), "A;B \"q\"\nlinha")
            x.note = "=SOMA(A1)"
            let out = CSVExporter.export(transactions: [x], options: CSVExportOptions(delimiter: ";", decimalComma: false))
            t.check(out.contains("\"A;B \"\"q\"\"\nlinha\""), out)
            t.check(out.contains("-1.50"), out)
            t.check(out.contains("'=SOMA(A1)"), out)
        },
        TestCase("exportação -> importação preserva data, valor e descrição") { t in
            let acc = Account(name: "C", type: .checking)
            let src = [tx(.expense, "100.01", D(2024, 2, 29), "Compra; especial", account: acc.id), tx(.income, "2500", D(2024, 12, 31), "Salário", account: acc.id)]
            let csv = CSVExporter.export(transactions: src, accounts: [acc])
            let r = CSVParser.parse(csv)
            t.equal(r.issues.count, 0); t.equal(r.candidates.count, 2)
            t.equal(r.candidates.map(\.amount), [dec("-100.01"), 2500])
            t.equal(ymds(r.candidates.map(\.date)), ["2024-02-29", "2024-12-31"])
            t.equal(r.candidates[0].title, "Compra; especial")
        },
        TestCase("exportação vazia tem só cabeçalho") { t in
            t.equal(CSVExporter.export(transactions: []), "data;descricao;tipo;valor;status;conta;categoria;tags;observacao\n")
        },
        TestCase("sugestão: descrição idêntica no histórico") { t in
            let food = UUID(), fuel = UUID()
            let s = CategorySuggester(history: [tx(.expense, "10", D(2025, 1, 1), "Posto Shell", category: fuel), tx(.expense, "20", D(2025, 1, 2), "Padaria Pão Quente", category: food)])
            t.equal(s.suggest(for: "posto shell"), fuel)
            t.equal(s.suggest(for: "  PADARIA PÃO QUENTE "), food)
        },
        TestCase("sugestão: palavras em comum, maioria vence, números/stopwords ignorados") { t in
            let food = UUID(), fuel = UUID()
            let hist = [tx(.expense, "1", D(2025, 1, 1), "Posto Ipiranga 123", category: fuel), tx(.expense, "1", D(2025, 1, 2), "Posto Shell Centro", category: fuel),
                        tx(.expense, "1", D(2025, 1, 3), "Restaurante Centro", category: food), tx(.expense, "1", D(2025, 1, 4), "Restaurante Sabor", category: food),
                        tx(.expense, "1", D(2025, 1, 5), "Restaurante do Zé", category: food)]
            let s = CategorySuggester(history: hist)
            t.equal(s.suggest(for: "Posto BR 999"), fuel)
            t.equal(s.suggest(for: "Restaurante Novo"), food)
            t.equal(s.suggest(for: "Pix para Posto"), fuel)
            t.isNil(s.suggest(for: "Coisa desconhecida"))
            t.isNil(s.suggest(for: ""))
            t.isNil(s.suggest(for: "123 de da"))
        },
        TestCase("sugestão: palavras-chave manuais têm prioridade; separação por tipo; aprender novos") { t in
            let uber = UUID(), salary = UUID(), travel = UUID()
            var s = CategorySuggester(history: [tx(.income, "1", D(2025, 1, 1), "Pagamento Uber", category: salary)], keywords: [uber: ["uber", "99pop"]])
            t.equal(s.suggest(for: "UBER *TRIP"), uber)
            t.equal(s.suggest(for: "Corrida 99Pop"), uber)
            let s2 = CategorySuggester(history: [tx(.income, "1", D(2025, 1, 1), "Consultoria Acme", category: salary)])
            t.equal(s2.suggest(for: "Consultoria nova", type: .income), salary)
            t.isNil(s2.suggest(for: "Consultoria nova", type: .expense))
            s.learn(tx(.expense, "1", D(2025, 1, 1), "Hotel Bahia", category: travel))
            t.equal(s.suggest(for: "Hotel Rio"), travel)
        },
        TestCase("sugestão: transferências e lançamentos sem categoria não ensinam") { t in
            var s = CategorySuggester()
            s.learn(tx(.expense, "1", D(2025, 1, 1), "Mercado Sol"))
            s.learn(tx(.transfer, "1", D(2025, 1, 1), "Mercado Lua", category: UUID()))
            t.isNil(s.suggest(for: "Mercado Sol")); t.isNil(s.suggest(for: "Mercado Lua"))
        },
    ]
}
