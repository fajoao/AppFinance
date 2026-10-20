import Foundation

// Extração de valor, data e estabelecimento a partir de TEXTO já reconhecido (OCR) de cupom fiscal, comprovante de
// PIX/transferência e boleto. O reconhecimento em si (Vision) fica em `App/Services/ReceiptTextRecognizer.swift`;
// aqui só há regras de texto, testáveis sem câmera. São heurísticas: o resultado é sempre uma SUGESTÃO que a pessoa
// confere no "Novo lançamento" antes de salvar.

enum ReceiptKind: String, Sendable, Equatable {
    case cupom, pix, boleto, unknown

    var displayName: String {
        switch self {
        case .cupom: return "Cupom fiscal"
        case .pix: return "Comprovante de PIX ou transferência"
        case .boleto: return "Boleto"
        case .unknown: return "Comprovante"
        }
    }
}

/// Dados para pré-preencher o "Novo lançamento" (vêm do QR da NFC-e ou do OCR).
struct ReceiptPrefill: Sendable, Equatable {
    var type: TransactionType = .expense
    var amount: Decimal?
    var date: Date?
    var title: String?
    var note: String?
    /// Evita lançar o mesmo documento duas vezes (`Transaction.externalId`).
    var externalId: String?
}

struct ReceiptExtraction: Sendable, Equatable {
    var kind: ReceiptKind = .unknown
    var amount: Decimal?
    /// Data do comprovante (compra/transferência).
    var date: Date?
    /// Vencimento (boleto).
    var dueDate: Date?
    var merchant: String?
    var cnpj: String?
    var externalId: String?
    var suggestedType: TransactionType = .expense
    var boleto: BoletoInfo?
    var warnings: [String] = []

    var hasUsefulData: Bool { amount != nil || date != nil || dueDate != nil || merchant != nil }

    var prefill: ReceiptPrefill {
        var p = ReceiptPrefill(type: suggestedType, amount: amount, date: kind == .boleto ? (dueDate ?? date) : date,
                               title: merchant, note: nil, externalId: externalId)
        if kind == .boleto {
            if p.title == nil { p.title = "Boleto" }
            if let b = boleto { p.note = "Linha digitável: " + b.formatted }
        } else if let cnpj {
            p.note = "CNPJ " + BrazilianDocument.formatCNPJ(cnpj)
        }
        return p
    }
}

enum ReceiptTextExtractor {
    // MARK: Entrada principal

    static func extract(from text: String, today: Date) -> ReceiptExtraction {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let norm = lines.map(TextDecoding.normalize)
        let all = norm.joined(separator: "\n")
        var out = ReceiptExtraction()

        if let boleto = BoletoParser.find(in: text, today: today) {
            extractBoleto(boleto, lines: lines, norm: norm, today: today, into: &out)
            return out
        }
        let looksLikeBoleto = all.contains("beneficiario") || all.contains("cedente") || all.contains("linha digitavel") || all.contains("boleto")
        if looksLikeBoleto && all.contains("vencimento") {
            extractBoletoWithoutCode(lines: lines, norm: norm, today: today, into: &out)
            return out
        }
        if all.contains("pix") || all.contains("transferencia") || all.contains("ted ") || all.contains("comprovante de pagamento") {
            extractPix(lines: lines, norm: norm, all: all, today: today, into: &out)
            return out
        }
        extractCupom(lines: lines, norm: norm, all: all, today: today, into: &out)
        return out
    }

    // MARK: Valores

    /// Valores monetários no formato brasileiro ("1.234,56", "52,90") encontrados na linha, na ordem em que aparecem.
    static func moneyValues(in line: String) -> [Decimal] {
        let chars = Array(line)
        var values: [Decimal] = []
        var i = 0
        while i < chars.count {
            if chars[i] == ",", i + 2 < chars.count,
               chars[i + 1].isASCII, chars[i + 1].isNumber, chars[i + 2].isASCII, chars[i + 2].isNumber,
               !(i + 3 < chars.count && chars[i + 3].isASCII && chars[i + 3].isNumber) {
                var start = i
                while start > 0, (chars[start - 1].isASCII && chars[start - 1].isNumber) || chars[start - 1] == "." { start -= 1 }
                var integer = String(chars[start..<i])
                while integer.hasPrefix(".") { integer.removeFirst() }
                if !integer.isEmpty, integer.last != ".", let v = Money.parse(integer + "," + String(chars[(i + 1)...(i + 2)]), style: .comma) {
                    values.append(v)
                }
                i += 3
            } else {
                i += 1
            }
        }
        return values
    }

    private static let totalLabels = ["valor total", "total a pagar", "valor a pagar", "total geral", "total da compra", "total do cupom",
                                      "total da nota", "total pago", "total r$", "valor da compra", "valor cobrado", "valor do documento"]
    private static let totalExclusions = ["subtotal", "sub-total", "sub total", "itens", "qtd", "troco", "tribut", "imposto", "lei 12", "aprox",
                                          "desconto", "acrescimo", "dinheiro", "cartao", "recebido", "desc."]

    /// Valor total do cupom: prioriza rótulos de total; ignora subtotal, troco, tributos. Cai no maior valor do texto.
    static func totalAmount(lines: [String], norm: [String]) -> (value: Decimal?, fromFallback: Bool) {
        func value(at i: Int) -> Decimal? {
            if let v = moneyValues(in: lines[i]).last { return v }
            if i + 1 < lines.count, let v = moneyValues(in: lines[i + 1]).first, !totalExclusions.contains(where: { norm[i + 1].contains($0) }) { return v }
            return nil
        }
        for label in totalLabels {
            for i in lines.indices where norm[i].contains(label) && !totalExclusions.contains(where: { norm[i].contains($0) }) {
                if let v = value(at: i), v > 0 { return (v, false) }
            }
        }
        for i in lines.indices {
            let tokens = norm[i].split(whereSeparator: { $0 == " " || $0 == ":" }).map(String.init)
            if tokens.first == "total", !totalExclusions.contains(where: { norm[i].contains($0) }), let v = value(at: i), v > 0 { return (v, false) }
        }
        let all = lines.flatMap { moneyValues(in: $0) }
        if let m = all.max(), m > 0 { return (m, true) }
        return (nil, false)
    }

    // MARK: Datas

    private static let monthWords = ["jan", "fev", "mar", "abr", "mai", "jun", "jul", "ago", "set", "out", "nov", "dez"]

    /// Datas `dd/mm/aaaa`, `dd/mm/aa`, `dd-mm-aaaa`, `dd.mm.aaaa` e `18 OUT 2026` / `18 de outubro de 2026`, na ordem do texto.
    static func dates(in line: String) -> [Date] {
        var found: [Date] = []
        let chars = Array(line)
        func isDigit(_ k: Int) -> Bool { k >= 0 && k < chars.count && chars[k].isASCII && chars[k].isNumber }
        func isSep(_ k: Int) -> Bool { k < chars.count && (chars[k] == "/" || chars[k] == "-" || chars[k] == ".") }
        var i = 0
        while i < chars.count {
            guard isDigit(i), !isDigit(i - 1) else { i += 1; continue }
            var matched = false
            for len in [10, 8] where i + len <= chars.count && !isDigit(i + len) {
                let shape: [Int] = len == 10 ? [0, 1, 3, 4, 6, 7, 8, 9] : [0, 1, 3, 4, 6, 7]
                guard shape.allSatisfy({ isDigit(i + $0) }), isSep(i + 2), isSep(i + 5) else { continue }
                if let d = DateParsing.parse(String(chars[i..<(i + len)])) { found.append(d); i += len; matched = true; break }
            }
            if !matched { i += 1 }
        }
        // Datas por extenso: "18 OUT 2026", "18 de outubro de 2026"
        let words = line.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "-" || $0 == "." }).map { TextDecoding.normalize(String($0)) }
        var k = 0
        while k < words.count {
            if let day = Int(words[k]), (1...31).contains(day), words[k].count <= 2 {
                var j = k + 1
                if j < words.count, words[j] == "de" { j += 1 }
                if j < words.count, let m = monthWords.firstIndex(where: { words[j].hasPrefix($0) }), words[j].count >= 3 {
                    j += 1
                    if j < words.count, words[j] == "de" { j += 1 }
                    if j < words.count, words[j].count == 4, let year = Int(words[j]), (2000...2100).contains(year),
                       day <= YearMonth(year: year, month: m + 1).daysInMonth {
                        found.append(FinanceCalendar.date(year, m + 1, day)); k = j
                    }
                }
            }
            k += 1
        }
        return found
    }

    private static func pickDate(lines: [String], norm: [String], preferred: [String], avoiding: [String], today: Date,
                                 warnings: inout [String]) -> Date? {
        func firstDate(where predicate: (Int) -> Bool) -> Date? {
            for i in lines.indices where predicate(i) {
                if let d = dates(in: lines[i]).first { return d }
            }
            return nil
        }
        let chosen = firstDate { i in preferred.contains { norm[i].contains($0) } && !avoiding.contains { norm[i].contains($0) } }
            ?? firstDate { i in !avoiding.contains { norm[i].contains($0) } }
        if let chosen, FinanceCalendar.daysBetween(today, chosen) > 1 { warnings.append("A data lida está no futuro; confira.") }
        return chosen
    }

    // MARK: Rótulos (estabelecimento, favorecido...)

    private static let labelNoise = ["instituicao", "banco", "agencia", "conta", "cpf", "cnpj", "chave", "tipo", "ispb", "documento", "valor", "data"]

    /// Texto que acompanha um rótulo: na mesma linha após ":" ou, se o rótulo está sozinho, na linha seguinte.
    static func value(afterLabels labels: [String], lines: [String], norm: [String]) -> String? {
        for i in lines.indices {
            let n = norm[i]
            for label in labels where n == label || n.hasPrefix(label + ":") || n.hasPrefix(label + " ") {
                if let colon = lines[i].firstIndex(of: ":") {
                    let after = lines[i][lines[i].index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    if isPlausibleName(after) { return after }
                }
                if n == label || n == label + ":" {
                    var j = i + 1
                    while j < lines.count, j <= i + 2 {
                        var candidate = lines[j]
                        if norm[j].hasPrefix("nome"), let colon = candidate.firstIndex(of: ":") {
                            candidate = String(candidate[candidate.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                        } else if norm[j].hasPrefix("nome ") {
                            candidate = String(candidate.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                        }
                        if isPlausibleName(candidate), !labelNoise.contains(where: { TextDecoding.normalize(candidate).hasPrefix($0) }) { return candidate }
                        j += 1
                    }
                }
            }
        }
        return nil
    }

    private static func isPlausibleName(_ s: String) -> Bool {
        let letters = s.filter { $0.isLetter }.count
        let digits = s.filter { $0.isNumber }.count
        return letters >= 3 && letters > digits && s.count <= 80
    }

    /// "SUPERMERCADO BOM PREÇO LTDA" -> "Supermercado Bom Preço Ltda". Só mexe em textos todos em maiúsculas.
    static func tidyName(_ s: String) -> String {
        let t = s.trimmingCharacters(in: CharacterSet(charactersIn: " -*:.,"))
        guard t == t.uppercased(), t != t.lowercased() else { return t }
        return t.split(separator: " ").map { w in
            let lower = w.lowercased()
            return ["de", "da", "do", "das", "dos", "e"].contains(lower) ? lower : lower.prefix(1).uppercased() + lower.dropFirst()
        }.joined(separator: " ")
    }

    // MARK: CNPJ

    static func cnpj(in text: String) -> String? {
        var run = ""
        var candidates: [String] = []
        func flush() {
            let d = run.filter { $0.isASCII && $0.isNumber }
            if d.count == 14 { candidates.append(d) }
            run = ""
        }
        for ch in text {
            if ch.isASCII && ch.isNumber { run.append(ch) }
            else if (ch == "." || ch == "/" || ch == "-") && !run.isEmpty { run.append(ch) }
            else { flush() }
        }
        flush()
        return candidates.first { BrazilianDocument.isValidCNPJ($0) }
    }

    // MARK: Cupom fiscal

    private static let headerSkips = ["cnpj", "cpf", "cupom", "nota fiscal", "danfe", "documento auxiliar", "extrato", "via ", "endereco", "rua ", "av.",
                                      "avenida", "insc", "ie:", "im:", "tel", "fone", "www", "nfc", "sat ", "consumidor", "nao fiscal", "pedido", "mesa",
                                      "comanda", "operador", "caixa", "bem-vindo", "obrigado", "http"]

    private static func extractCupom(lines: [String], norm: [String], all: String, today: Date, into out: inout ReceiptExtraction) {
        out.kind = all.contains("cupom") || all.contains("nfc-e") || all.contains("nfce") || all.contains("danfe") || all.contains("cnpj") || all.contains("total")
            ? .cupom : .unknown
        let total = totalAmount(lines: lines, norm: norm)
        out.amount = total.value
        if total.fromFallback { out.warnings.append("Não achei o rótulo \"Total\"; usei o maior valor do texto. Confira.") }
        out.cnpj = cnpj(in: lines.joined(separator: "\n"))
        out.date = pickDate(lines: lines, norm: norm, preferred: ["emiss", "data", "hora"], avoiding: ["vencimento", "validade", "valido"],
                            today: today, warnings: &out.warnings)
        if let labelled = value(afterLabels: ["razao social", "estabelecimento", "empresa", "loja", "nome fantasia"], lines: lines, norm: norm) {
            out.merchant = tidyName(labelled)
        } else {
            for i in lines.indices.prefix(8) {
                let n = norm[i]
                let letters = lines[i].filter { $0.isLetter }.count
                guard letters >= 4, letters * 2 >= lines[i].count, !headerSkips.contains(where: { n.contains($0) }),
                      dates(in: lines[i]).isEmpty, moneyValues(in: lines[i]).isEmpty else { continue }
                out.merchant = tidyName(lines[i]); break
            }
        }
    }

    // MARK: PIX / transferência

    private static func extractPix(lines: [String], norm: [String], all: String, today: Date, into out: inout ReceiptExtraction) {
        out.kind = .pix
        let received = ["pix recebido", "voce recebeu", "recebido de", "transferencia recebida", "recebeu um pix", "pix recebida", "credito de pix"]
            .contains { all.contains($0) }
        out.suggestedType = received ? .income : .expense

        // Valor: linha com o rótulo "valor" (sem tarifa/saldo/limite); senão o primeiro valor monetário.
        let valueLabels = ["valor", "valor pago", "valor da transferencia", "valor do pix", "valor transferido", "valor enviado", "valor recebido"]
        let exclusions = ["tarifa", "saldo", "limite", "desconto", "juros", "multa", "iof"]
        for i in lines.indices where valueLabels.contains(where: { norm[i].hasPrefix($0) }) && !exclusions.contains(where: { norm[i].contains($0) }) {
            if let v = moneyValues(in: lines[i]).first ?? (i + 1 < lines.count ? moneyValues(in: lines[i + 1]).first : nil), v > 0 { out.amount = v; break }
        }
        if out.amount == nil {
            let total = totalAmount(lines: lines, norm: norm)
            out.amount = total.value
            if total.fromFallback { out.warnings.append("Usei o maior valor do texto. Confira.") }
        }
        out.date = pickDate(lines: lines, norm: norm, preferred: ["data", "realizad", "efetivad", "pago em", "hora"], avoiding: ["agendad", "vencimento"],
                            today: today, warnings: &out.warnings)

        let toLabels = ["para", "destino", "destinatario", "favorecido", "recebedor", "quem recebeu", "nome do recebedor", "nome do favorecido", "beneficiario", "pago para"]
        let fromLabels = ["de", "origem", "pagador", "quem pagou", "remetente", "nome do pagador", "recebido de", "enviado por"]
        let counterpart = value(afterLabels: received ? fromLabels : toLabels, lines: lines, norm: norm)
            ?? value(afterLabels: received ? toLabels : fromLabels, lines: lines, norm: norm)
        out.merchant = counterpart.map(tidyName)
        out.cnpj = cnpj(in: lines.joined(separator: "\n"))

        // ID da transação (E2E): 32 caracteres alfanuméricos começando por E ou D.
        for line in lines {
            for token in line.split(whereSeparator: { $0 == " " || $0 == ":" }) where token.count == 32 && (token.first == "E" || token.first == "D")
                && token.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) {
                out.externalId = "pix:" + token; break
            }
            if out.externalId != nil { break }
        }
    }

    // MARK: Boleto

    private static func extractBoleto(_ b: BoletoInfo, lines: [String], norm: [String], today: Date, into out: inout ReceiptExtraction) {
        out.kind = .boleto
        out.boleto = b
        if b.isValid {
            out.amount = b.amount
            out.dueDate = b.dueDate
            if b.amount == nil {
                out.warnings.append(b.kind == .bank ? "Boleto sem valor definido (valor livre). Digite o valor." : "O valor deste boleto não está em reais. Digite o valor.")
            }
        } else {
            out.warnings.append((b.invalidReason ?? "Linha digitável inválida.") + " Confira os números; nada foi preenchido a partir dela.")
        }
        // Linha inválida: o valor só vem do texto impresso (rotulado), nunca dos dígitos.
        if !b.isValid {
            for i in lines.indices where totalLabels.contains(where: { norm[i].contains($0) }) {
                if let v = moneyValues(in: lines[i]).last { out.amount = v; out.warnings.append("Valor lido do texto impresso, não da linha digitável."); break }
            }
        }
        if out.dueDate == nil {
            var ignored: [String] = []
            out.dueDate = pickDate(lines: lines, norm: norm, preferred: ["vencimento"], avoiding: [], today: .distantPast, warnings: &ignored)
        }
        out.merchant = value(afterLabels: ["beneficiario", "cedente", "favorecido", "razao social", "nome do beneficiario"], lines: lines, norm: norm).map(tidyName)
        out.cnpj = cnpj(in: lines.joined(separator: "\n"))
    }

    private static func extractBoletoWithoutCode(lines: [String], norm: [String], today: Date, into out: inout ReceiptExtraction) {
        out.kind = .boleto
        var ignored: [String] = []
        out.dueDate = pickDate(lines: lines, norm: norm, preferred: ["vencimento"], avoiding: [], today: .distantPast, warnings: &ignored)
        for i in lines.indices where norm[i].contains("valor do documento") || norm[i].contains("valor cobrado") || norm[i].contains("valor do boleto") {
            if let v = moneyValues(in: lines[i]).last ?? (i + 1 < lines.count ? moneyValues(in: lines[i + 1]).first : nil) { out.amount = v; break }
        }
        out.merchant = value(afterLabels: ["beneficiario", "cedente", "favorecido", "razao social", "nome do beneficiario"], lines: lines, norm: norm).map(tidyName)
        out.cnpj = cnpj(in: lines.joined(separator: "\n"))
        out.warnings.append("Não encontrei a linha digitável; os dados vêm só do texto e não foram validados.")
    }
}

// MARK: - Interpretação do que a câmera leu (QR ou texto)

enum ScanOutcome: Sendable, Equatable {
    case nfce(NFCeQRCode)
    case receipt(ReceiptExtraction)
    case failure(String)

    var prefill: ReceiptPrefill? {
        switch self {
        case .nfce(let qr):
            return ReceiptPrefill(type: .expense, amount: qr.totalAmount, date: qr.emissionDate, title: "Compra (NFC-e \(qr.key.uf))",
                                  note: "NFC-e \(qr.key.uf), CNPJ \(qr.key.formattedCNPJ), chave \(qr.key.value)", externalId: qr.externalId)
        case .receipt(let r): return r.hasUsefulData ? r.prefill : nil
        case .failure: return nil
        }
    }
}

enum ScanInterpreter {
    /// Decide se o conteúdo é o QR de uma NFC-e (URL com `p=`/`chNFe=` ou chave de 44 dígitos) ou texto de comprovante.
    static func interpret(_ raw: String, today: Date) -> ScanOutcome {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .failure("Nada foi lido. Tente de novo com mais luz e o documento reto.") }
        let lower = text.lowercased()
        let looksLikeNFCeURL = lower.hasPrefix("http") && (lower.contains("p=") || lower.contains("chnfe=") || lower.contains("nfce"))
        let digitsOnly = text.allSatisfy { $0.isNumber || $0 == " " || $0 == "." || $0 == "-" }
        if looksLikeNFCeURL || lower.hasPrefix("p=") || (digitsOnly && BrazilianDocument.digits(text).count == 44) {
            do { return .nfce(try NFCeParser.parse(text)) }
            catch let e as NFCeParseError {
                if digitsOnly, let boleto = BoletoParser.parse(digits: text, today: today) {
                    return .receipt(ReceiptTextExtractor.extract(from: boleto.digits, today: today))
                }
                return .failure(e.message)
            } catch { return .failure("Não foi possível ler este QR Code.") }
        }
        if lower.hasPrefix("http") { return .failure("Este QR Code é um link que não parece ser de uma nota fiscal.") }
        let r = ReceiptTextExtractor.extract(from: text, today: today)
        return r.hasUsefulData ? .receipt(r) : .failure("Não encontrei valor, data ou estabelecimento no texto.")
    }
}
