import Foundation

// Vetores de teste:
// - Chaves de acesso (NFC-e) e linhas digitáveis de boleto/arrecadação marcadas "gerado" foram produzidas por uma implementação
//   independente (script Python) das regras de DV; não são documentos reais.
// - "00190.50095 40144.816069 06809.350314 3 37370000000100" é um exemplo público e muito citado de boleto do Banco do Brasil.

private let key1 = "35261011222333000181650010000123451876543210"    // SP, 10/2026, CNPJ 11.222.333/0001-81, mod 65, série 1, nº 12345 (gerado)
private let key2 = "33260912345678000195650020000007771111122221"    // RJ, 09/2026, CNPJ 12.345.678/0001-95 (gerado)
private let key3 = "53261098765432000198550010000000051000000017"    // DF, mod 55 (gerado)
private let today = D(2026, 10, 19)

private func nfceError(_ text: String) -> NFCeParseError? {
    do { _ = try NFCeParser.parse(text); return nil } catch let e as NFCeParseError { return e } catch { return nil }
}

func nfceTests() -> [TestCase] {
    [
        TestCase("chave de acesso: decompõe UF, mês, CNPJ, modelo, série e número") { t in
            let k = try NFCeParser.parseKey(key1)
            t.equal(k.uf, "SP"); t.equal(k.ufCode, 35); t.equal(k.emissionMonth, YearMonth(year: 2026, month: 10))
            t.equal(k.cnpj, "11222333000181"); t.check(k.cnpjIsValid); t.equal(k.formattedCNPJ, "11.222.333/0001-81")
            t.equal(k.model, 65); t.check(k.isNFCe); t.equal(k.series, 1); t.equal(k.number, 12345)
            t.equal(k.grouped, "3526 1011 2223 3300 0181 6500 1000 0123 4518 7654 3210")
            t.equal(try NFCeParser.parseKey(k.grouped).value, key1, "aceita a chave com espaços")
            t.equal(try NFCeParser.parseKey(key3).uf, "DF"); t.check(!(try NFCeParser.parseKey(key3)).isNFCe)
        },
        TestCase("chave: DV errado, tamanho errado e campos inválidos") { t in
            var bad = Array(key1); bad[43] = bad[43] == "0" ? "1" : "0"
            t.equal(nfceError(String(bad)), .invalidCheckDigit)
            t.equal(nfceError(String(key1.dropLast())), .invalidLength)
            var swapped = Array(key1); swapped[10] = "9"            // altera o CNPJ: DV da chave deixa de conferir
            t.equal(nfceError(String(swapped)), .invalidCheckDigit)
            // UF inexistente (99) com DV recalculado a mão não é possível; usa mês 13 com DV correto:
            let noDV = "3526" + "13" + String(key1.dropFirst(6).prefix(37))
            let dv = BrazilianDocument.mod11(BrazilianDocument.digits(noDV))
            t.equal(nfceError(noDV + String(dv)), .invalidFields)
        },
        TestCase("CNPJ: DV e formatação") { t in
            t.check(BrazilianDocument.isValidCNPJ("11.222.333/0001-81"))
            t.check(!BrazilianDocument.isValidCNPJ("11.222.333/0001-82"))
            t.check(!BrazilianDocument.isValidCNPJ("00000000000000"))
            t.check(!BrazilianDocument.isValidCNPJ("123"))
            t.equal(BrazilianDocument.formatCNPJ("11222333000181"), "11.222.333/0001-81")
        },
        TestCase("QR online: URL com p= (chave|2|tpAmb|idCSC|hash) não traz valor") { t in
            let url = "https://www.nfce.fazenda.sp.gov.br/qrcode?p=\(key1)|2|1|1|A1B2C3D4E5F6A1B2C3D4E5F6A1B2C3D4E5F6A1B2"
            let qr = try NFCeParser.parse(url)
            t.equal(qr.key.value, key1); t.equal(qr.qrVersion, 2); t.equal(qr.environment, .production)
            t.isNil(qr.totalAmount); t.isNil(qr.emissionDay); t.isNil(qr.emissionDate)
            t.equal(qr.host, "www.nfce.fazenda.sp.gov.br"); t.equal(qr.externalId, "nfce:" + key1)
        },
        TestCase("QR com | codificado como %7C, homologação e URL de outro estado") { t in
            let url = "http://nfce.sefaz.rj.gov.br/consulta?p=\(key2)%7C2%7C2%7C1%7CHASH"
            let qr = try NFCeParser.parse(url)
            t.equal(qr.key.uf, "RJ"); t.equal(qr.environment, .homologation)
        },
        TestCase("QR de contingência offline: dia e valor vNF vêm no QR") { t in
            let url = "https://www.nfce.fazenda.sp.gov.br/qrcode?p=\(key1)|2|1|15|152.90|ZGlnZXN0VmFsdWU=|1|HASH"
            let qr = try NFCeParser.parse(url)
            t.equal(qr.totalAmount, dec("152.90")); t.equal(qr.emissionDay, 15); t.equal(ymd(qr.emissionDate!), "2026-10-15")
            let zero = try NFCeParser.parse("https://x.gov.br/q?p=\(key1)|2|1|15|0.00|dg|1|H")
            t.isNil(zero.totalAmount, "valor zero não é valor")
        },
        TestCase("layout antigo (chNFe=), chave pura e p= solto") { t in
            t.equal(try NFCeParser.parse("https://www.fazenda.gov.br/consulta?chNFe=\(key1)&nVersao=100&tpAmb=1").key.value, key1)
            t.equal(try NFCeParser.parse(key2).key.uf, "RJ")
            t.equal(try NFCeParser.parse("  p=\(key1)|2|1|1|X ").key.value, key1)
        },
        TestCase("texto que não é NFC-e") { t in
            t.equal(nfceError("https://exemplo.com/promo"), .notAnNFCe)
            t.equal(nfceError("olá"), .notAnNFCe)
            t.equal(nfceError(""), .notAnNFCe)
            t.equal(nfceError("https://x.gov.br/q?p=123|2|1"), .invalidLength)
        },
        TestCase("NFCeLookupService é só um contrato: não existe implementação no Core") { t in
            // O protocolo compila e pode ser implementado por quem tiver um serviço próprio; aqui só um dublê de teste.
            struct Failing: NFCeLookupService {
                func lookup(_ qr: NFCeQRCode) async throws -> NFCeReceipt { throw NFCeLookupError.notConfigured }
            }
            let service: any NFCeLookupService = Failing()
            t.check(service is Failing)
            t.equal(NFCeLookupError.notConfigured, NFCeLookupError.notConfigured)
        },
    ]
}

func boletoTests() -> [TestCase] {
    [
        TestCase("boleto bancário (gerado): valor, vencimento, banco e formatação") { t in
            let b = BoletoParser.parse(digits: "23791.23454 67890.123457 67890.123457 1 16260000015075", today: today)!
            t.check(b.isValid); t.equal(b.kind, .bank); t.equal(b.bankCode, "237")
            t.equal(b.amount, dec("150.75")); t.equal(ymd(b.dueDate!), "2026-11-10")
            t.equal(b.formatted, "23791.23454 67890.123457 67890.123457 1 16260000015075")
            t.equal(b.barcode, "23791162600000150751234567890123456789012345")
            // o mesmo boleto lido como código de barras (44 dígitos)
            let bar = BoletoParser.parse(digits: b.barcode, today: today)!
            t.check(bar.isValid); t.equal(bar.amount, dec("150.75")); t.equal(ymd(bar.dueDate!), "2026-11-10")
        },
        TestCase("boleto real público do Banco do Brasil: valor R$ 1,00 e vencimento resolvido pela janela do fator") { t in
            let line = "00190.50095 40144.816069 06809.350314 3 37370000000100"
            let b = BoletoParser.parse(digits: line, today: D(2007, 12, 15))!
            t.check(b.isValid, b.invalidReason ?? ""); t.equal(b.bankCode, "001"); t.equal(b.amount, 1)
            t.equal(ymd(b.dueDate!), "2007-12-31")
            // hoje (2026) o mesmo fator cairia em 2032 (ciclo de 9000 dias): é a ambiguidade inerente do formato
            t.equal(ymd(BoletoParser.parse(digits: line, today: today)!.dueDate!), "2032-08-21")
        },
        TestCase("fator de vencimento reinicia em 1000 em 22/02/2025") { t in
            t.equal(ymd(BoletoParser.dueDate(factor: 1000, today: D(2025, 3, 1))!), "2025-02-22")
            t.equal(ymd(BoletoParser.dueDate(factor: 9999, today: D(2025, 2, 1))!), "2025-02-21")
            t.isNil(BoletoParser.dueDate(factor: 0, today: today), "fator 0000 = sem vencimento")
            let c = BoletoParser.parse(digits: "34191090080012345678290123456783110000000250000", today: D(2025, 3, 1))!
            t.check(c.isValid); t.equal(c.amount, dec("2500.00")); t.equal(ymd(c.dueDate!), "2025-02-22")
        },
        TestCase("boleto sem valor e sem vencimento (valor livre)") { t in
            let b = BoletoParser.parse(digits: "00190000090000000000000000000018300000000000000", today: today)!
            t.check(b.isValid); t.isNil(b.amount); t.isNil(b.dueDate)
        },
        TestCase("dígito verificador errado em cada bloco e no geral") { t in
            let good = "23791234546789012345767890123457116260000015075"
            func mutate(_ i: Int) -> BoletoInfo {
                var a = Array(good); a[i] = a[i] == "9" ? "8" : Character(String((a[i].wholeNumberValue! + 1) % 10)); return BoletoParser.parse(digits: String(a), today: today)!
            }
            t.check(!mutate(9).isValid); t.check(mutate(9).invalidReason!.contains("1º"))      // DV1
            t.check(!mutate(20).isValid); t.check(mutate(20).invalidReason!.contains("2º"))    // DV2
            t.check(!mutate(31).isValid); t.check(mutate(31).invalidReason!.contains("3º"))    // DV3
            t.check(!mutate(32).isValid); t.check(mutate(32).invalidReason!.contains("geral")) // DV geral
            t.check(!mutate(40).isValid, "alterar o valor invalida o DV geral")
        },
        TestCase("arrecadação/convênio (gerado): 48 dígitos, valor real em módulo 10") { t in
            let b = BoletoParser.parse(digits: "826100000015 894000123451 678901234560 789012345672", today: today)!
            t.check(b.isValid, b.invalidReason ?? ""); t.equal(b.kind, .utility); t.equal(b.amount, dec("189.40")); t.isNil(b.dueDate)
            t.equal(b.barcode, "82610000001894000123456789012345678901234567")
            t.equal(b.formatted, "826100000015 894000123451 678901234560 789012345672")
            let bar = BoletoParser.parse(digits: b.barcode, today: today)!
            t.check(bar.isValid); t.equal(bar.amount, dec("189.40"))
            let broken = BoletoParser.parse(digits: "826100000015 894000123451 678901234561 789012345672", today: today)!
            t.check(!broken.isValid); t.check(broken.invalidReason!.contains("3º"))
        },
        TestCase("arrecadação com valor de referência (módulo 11) não vira valor em reais") { t in
            let b = BoletoParser.parse(digits: "828700000012894000123454678901234561789012345675", today: today)!
            t.check(b.isValid, b.invalidReason ?? ""); t.isNil(b.amount)
        },
        TestCase("tamanhos e caracteres inesperados") { t in
            t.isNil(BoletoParser.parse(digits: "123456", today: today))
            t.isNil(BoletoParser.parse(digits: "2379A.23454 67890.123457 67890.123457 1 16260000015075", today: today))
            t.equal(BoletoParser.candidates(in: "Código: 23791.23454 67890.123457 67890.123457 1 16260000015075 Vencimento 10/11/2026"),
                    ["23791234546789012345767890123457116260000015075"])
            t.equal(BoletoParser.candidates(in: "Agência 1234 conta 99999-9").count, 0)
        },
    ]
}

private let cupomSuper = """
SUPERMERCADO BOM PREÇO LTDA
CNPJ: 11.222.333/0001-81
Rua das Flores, 123 - Centro
DOCUMENTO AUXILIAR DA NOTA FISCAL DE CONSUMIDOR ELETRÔNICA
ITEM CÓDIGO DESCRIÇÃO QTD UN VL UNIT VL TOTAL
001 7891000100103 LEITE INTEGRAL 1L 6 UN 5,49 32,94
002 7891910000197 ARROZ 5KG 1 UN 28,90 28,90
Qtd. total de itens 7
Subtotal R$ 61,84
Desconto R$ 1,84
VALOR TOTAL R$ 60,00
Dinheiro 100,00
Troco 40,00
Tributos Totais Incidentes (Lei Federal 12.741/2012) R$ 14,12
Emissão: 18/10/2026 14:32:10
"""

private let cupomRestaurante = """
RESTAURANTE SABOR & ARTE
CNPJ 12.345.678/0001-95
CUPOM FISCAL
Data: 05/10/26
Mesa 12
TOTAL
R$ 1.123,45
"""

private let pixEnviado = """
Comprovante de transferência
Pix enviado
Valor
R$ 150,00
Data
18 OUT 2026 - 14:32:10
Para
Maria da Silva
CPF •••.123.456-••
Instituição
Banco Inter
ID da transação
E00360305202610181732abc123XYZ45
"""

private let pixRecebido = """
Pix recebido
Valor: R$ 2.350,00
Data da transação: 12/10/2026
Origem
Nome: João Pereira de Souza
Instituição: Itaú Unibanco
"""

private let boletoTexto = """
Banco do Brasil
Local de pagamento: Pagável em qualquer banco
Beneficiário: ESCOLA APRENDER LTDA
Vencimento 31/12/2007
Linha digitável: 00190.50095 40144.816069 06809.350314 3 37370000000100
Valor do documento 1,00
"""

func receiptTextTests() -> [TestCase] {
    [
        TestCase("dinheiro em texto: formatos brasileiros") { t in
            t.equal(ReceiptTextExtractor.moneyValues(in: "VALOR TOTAL R$ 1.234,56"), [dec("1234.56")])
            t.equal(ReceiptTextExtractor.moneyValues(in: "5,49 32,94"), [dec("5.49"), dec("32.94")])
            t.equal(ReceiptTextExtractor.moneyValues(in: "Qtd 7"), [])
            t.equal(ReceiptTextExtractor.moneyValues(in: "R$12,5"), [], "um dígito após a vírgula não é centavo")
            t.equal(ReceiptTextExtractor.moneyValues(in: "1,234"), [], "três dígitos após a vírgula não é dinheiro")
        },
        TestCase("datas em texto: numéricas, 2 dígitos, por extenso e inválidas") { t in
            t.equal(ymds(ReceiptTextExtractor.dates(in: "Emissão: 18/10/2026 14:32:10")), ["2026-10-18"])
            t.equal(ymds(ReceiptTextExtractor.dates(in: "05/10/26")), ["2026-10-05"])
            t.equal(ymds(ReceiptTextExtractor.dates(in: "18/10/2026-14:32")), ["2026-10-18"])
            t.equal(ymds(ReceiptTextExtractor.dates(in: "18 OUT 2026 - 14:32:10")), ["2026-10-18"])
            t.equal(ymds(ReceiptTextExtractor.dates(in: "Pago em 3 de março de 2026")), ["2026-03-03"])
            t.equal(ymds(ReceiptTextExtractor.dates(in: "31/02/2026")), [])
            t.equal(ymds(ReceiptTextExtractor.dates(in: "12.741/2012")), [])
        },
        TestCase("cupom de supermercado: total ignora subtotal, troco e tributos; data, CNPJ e nome") { t in
            let r = ReceiptTextExtractor.extract(from: cupomSuper, today: today)
            t.equal(r.kind, .cupom); t.equal(r.amount, dec("60.00")); t.equal(ymd(r.date!), "2026-10-18")
            t.equal(r.merchant, "Supermercado Bom Preço Ltda"); t.equal(r.cnpj, "11222333000181")
            t.equal(r.suggestedType, .expense); t.check(r.warnings.isEmpty, "\(r.warnings)")
            let p = r.prefill
            t.equal(p.amount, dec("60.00")); t.equal(p.title, "Supermercado Bom Preço Ltda"); t.equal(p.note, "CNPJ 11.222.333/0001-81")
        },
        TestCase("cupom: TOTAL sozinho com o valor na linha seguinte, data com ano de 2 dígitos, milhar") { t in
            let r = ReceiptTextExtractor.extract(from: cupomRestaurante, today: today)
            t.equal(r.amount, dec("1123.45")); t.equal(ymd(r.date!), "2026-10-05")
            t.equal(r.merchant, "Restaurante Sabor & Arte"); t.equal(r.cnpj, "12345678000195")
        },
        TestCase("cupom sem rótulo de total: usa o maior valor e avisa") { t in
            let r = ReceiptTextExtractor.extract(from: "Padaria Pão Quente\n18/10/2026\nPão francês 4,50\nCafé 7,00", today: today)
            t.equal(r.amount, dec("7.00")); t.check(r.warnings.contains { $0.contains("maior valor") })
            t.equal(r.merchant, "Padaria Pão Quente")
        },
        TestCase("data no futuro gera aviso") { t in
            let r = ReceiptTextExtractor.extract(from: "LOJA X\nTOTAL R$ 10,00\nEmissão 25/12/2026", today: today)
            t.check(r.warnings.contains { $0.contains("futuro") })
        },
        TestCase("PIX enviado: valor, data por extenso, favorecido e ID da transação") { t in
            let r = ReceiptTextExtractor.extract(from: pixEnviado, today: today)
            t.equal(r.kind, .pix); t.equal(r.suggestedType, .expense); t.equal(r.amount, 150)
            t.equal(ymd(r.date!), "2026-10-18"); t.equal(r.merchant, "Maria da Silva")
            t.equal(r.externalId, "pix:E00360305202610181732abc123XYZ45")
            t.equal(r.prefill.externalId, "pix:E00360305202610181732abc123XYZ45")
        },
        TestCase("PIX recebido vira receita e usa a origem") { t in
            let r = ReceiptTextExtractor.extract(from: pixRecebido, today: today)
            t.equal(r.kind, .pix); t.equal(r.suggestedType, .income); t.equal(r.amount, dec("2350.00"))
            t.equal(ymd(r.date!), "2026-10-12"); t.equal(r.merchant, "João Pereira de Souza")
            t.equal(r.prefill.type, .income)
        },
        TestCase("PIX: tarifa e saldo não viram o valor") { t in
            let r = ReceiptTextExtractor.extract(from: "Pix enviado\nSaldo após a operação R$ 9.999,00\nValor R$ 42,00\nTarifa R$ 0,00\nPara: Padaria Central", today: today)
            t.equal(r.amount, 42); t.equal(r.merchant, "Padaria Central")
        },
        TestCase("boleto no texto: valor e vencimento vêm da linha digitável validada; beneficiário do rótulo") { t in
            let r = ReceiptTextExtractor.extract(from: boletoTexto, today: D(2007, 12, 15))
            t.equal(r.kind, .boleto); t.check(r.boleto!.isValid); t.equal(r.amount, 1)
            t.equal(ymd(r.dueDate!), "2007-12-31"); t.equal(r.merchant, "Escola Aprender Ltda")
            let p = r.prefill
            t.equal(ymd(p.date!), "2007-12-31", "boleto pré-preenche com o vencimento"); t.equal(p.title, "Escola Aprender Ltda")
            t.equal(p.note, "Linha digitável: 00190.50095 40144.816069 06809.350314 3 37370000000100")
        },
        TestCase("boleto com linha digitável inválida: não confia nos dígitos e avisa") { t in
            let broken = boletoTexto.replacingOccurrences(of: "40144.816069", with: "40144.816068")
            let r = ReceiptTextExtractor.extract(from: broken, today: D(2007, 12, 15))
            t.equal(r.kind, .boleto); t.check(!r.boleto!.isValid); t.equal(ymd(r.dueDate!), "2007-12-31", "vencimento do texto impresso")
            t.check(r.warnings.contains { $0.contains("não confere") })
            t.equal(r.amount, 1, "valor do texto impresso, com aviso")
            t.check(r.warnings.contains { $0.contains("texto impresso") })
        },
        TestCase("boleto de conta de consumo (arrecadação)") { t in
            let text = "CONCESSIONÁRIA DE ÁGUA\nBeneficiário: Companhia de Saneamento\nVencimento: 25/10/2026\n826100000015 894000123451 678901234560 789012345672"
            let r = ReceiptTextExtractor.extract(from: text, today: today)
            t.equal(r.kind, .boleto); t.equal(r.amount, dec("189.40")); t.equal(ymd(r.dueDate!), "2026-10-25")
            t.equal(r.merchant, "Companhia de Saneamento")
        },
        TestCase("boleto sem linha digitável: dados só do texto, com aviso") { t in
            let r = ReceiptTextExtractor.extract(from: "BOLETO\nBeneficiário: Condomínio Sol\nVencimento 10/11/2026\nValor do documento R$ 820,00", today: today)
            t.equal(r.kind, .boleto); t.equal(r.amount, 820); t.equal(ymd(r.dueDate!), "2026-11-10"); t.isNil(r.boleto)
            t.check(r.warnings.contains { $0.contains("linha digitável") })
        },
        TestCase("texto sem nada útil") { t in
            let r = ReceiptTextExtractor.extract(from: "xx\n??", today: today)
            t.check(!r.hasUsefulData)
            t.equal(ScanInterpreter.interpret("xx ??", today: today), .failure("Não encontrei valor, data ou estabelecimento no texto."))
        },
    ]
}

func scanInterpreterTests() -> [TestCase] {
    [
        TestCase("QR de NFC-e online: sem valor, mas com externalId, nota e título") { t in
            let out = ScanInterpreter.interpret("https://www.nfce.fazenda.sp.gov.br/qrcode?p=\(key1)|2|1|1|HASH", today: today)
            guard case .nfce(let qr) = out else { t.fail("esperava nfce, obtido \(out)"); return }
            t.equal(qr.key.uf, "SP")
            let p = out.prefill!
            t.isNil(p.amount); t.equal(p.externalId, "nfce:" + key1); t.equal(p.title, "Compra (NFC-e SP)")
            t.check(p.note!.contains("11.222.333/0001-81")); t.check(p.note!.contains(key1))
        },
        TestCase("QR de contingência: valor e data pré-preenchidos") { t in
            let out = ScanInterpreter.interpret("https://x.sefaz.gov.br/q?p=\(key1)|2|1|15|152.90|dg|1|H", today: today)
            t.equal(out.prefill?.amount, dec("152.90")); t.equal(ymd(out.prefill!.date!), "2026-10-15")
        },
        TestCase("QR com DV inválido e QR que não é nota") { t in
            var bad = Array(key1); bad[43] = "9"
            t.equal(ScanInterpreter.interpret("https://x.gov.br/q?p=\(String(bad))|2|1|1|H", today: today),
                    .failure(NFCeParseError.invalidCheckDigit.message))
            t.equal(ScanInterpreter.interpret("https://exemplo.com/promo", today: today),
                    .failure("Este QR Code é um link que não parece ser de uma nota fiscal."))
            t.equal(ScanInterpreter.interpret("   ", today: today), .failure("Nada foi lido. Tente de novo com mais luz e o documento reto."))
        },
        TestCase("código de barras de boleto de 44 dígitos cai no extrator de boleto") { t in
            let out = ScanInterpreter.interpret("23791162600000150751234567890123456789012345", today: today)
            guard case .receipt(let r) = out else { t.fail("esperava receipt, obtido \(out)"); return }
            t.equal(r.kind, .boleto); t.equal(r.amount, dec("150.75"))
        },
        TestCase("texto de cupom entra pelo extrator") { t in
            let out = ScanInterpreter.interpret(cupomSuper, today: today)
            t.equal(out.prefill?.amount, dec("60.00"))
        },
    ]
}
