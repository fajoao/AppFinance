import Foundation

// Boleto: validação da linha digitável / código de barras (padrão Febraban) e extração de valor e vencimento.
//
// Boleto bancário: 47 dígitos na linha digitável, 44 no código de barras.
//   barras = banco(3) moeda(1) DV(1) fator de vencimento(4) valor(10, em centavos) campo livre(25)
//   linha  = [banco moeda livre1-5 DV1] [livre6-15 DV2] [livre16-25 DV3] [DV geral] [fator valor]
//   DV1, DV2, DV3: módulo 10 dos 9, 10 e 10 dígitos anteriores. DV geral: módulo 11 dos outros 43 dígitos do código de barras.
// Boleto de arrecadação/convênio (contas de consumo, tributos): começa com 8; 48 dígitos na linha (4 blocos de 11 + DV),
//   44 no código de barras. O 3º dígito indica valor real (6 ou 7, módulo 10) ou referência (8 ou 9, módulo 11).
// Nada aqui consulta banco ou registradora: só confere a matemática dos dígitos. Um boleto matematicamente válido
// ainda pode estar pago, vencido ou ser falso; o app apenas pré-preenche um lançamento.

struct BoletoInfo: Sendable, Equatable {
    enum Kind: String, Sendable { case bank, utility }

    var kind: Kind
    /// Linha digitável (47/48 dígitos) ou código de barras (44), somente dígitos, como foi lido.
    var digits: String
    /// Código de barras de 44 dígitos reconstruído.
    var barcode: String
    var isValid: Bool
    var invalidReason: String?
    /// nil se o boleto não traz valor (valor livre) ou se o valor é uma referência que não é em reais.
    var amount: Decimal?
    /// nil se não há vencimento codificado (fator 0000) ou se o boleto é de arrecadação.
    var dueDate: Date?
    /// Código do banco (3 dígitos) nos boletos bancários.
    var bankCode: String?

    /// Linha digitável com a pontuação impressa no boleto.
    var formatted: String {
        let a = Array(digits)
        func s(_ r: Range<Int>) -> String { String(a[r]) }
        switch (kind, a.count) {
        case (.bank, 47):
            return "\(s(0..<5)).\(s(5..<10)) \(s(10..<15)).\(s(15..<21)) \(s(21..<26)).\(s(26..<32)) \(s(32..<33)) \(s(33..<47))"
        case (.utility, 48):
            return stride(from: 0, to: 48, by: 12).map { s($0..<($0 + 12)) }.joined(separator: " ")
        default:
            return digits
        }
    }
}

enum BoletoParser {
    // MARK: Dígitos verificadores

    /// Módulo 10: pesos 2,1,2,1... da direita para a esquerda; produtos > 9 somam os algarismos.
    static func mod10(_ d: [Int]) -> Int {
        var sum = 0
        var weight = 2
        for x in d.reversed() {
            let p = x * weight
            sum += p > 9 ? p / 10 + p % 10 : p
            weight = weight == 2 ? 1 : 2
        }
        return (10 - sum % 10) % 10
    }

    /// Módulo 11 do DV geral do boleto bancário: pesos 2...9; DV 0, 10 ou 11 vira 1.
    static func bankMod11(_ d: [Int]) -> Int {
        var sum = 0
        var weight = 2
        for x in d.reversed() {
            sum += x * weight
            weight = weight == 9 ? 2 : weight + 1
        }
        let dv = 11 - sum % 11
        return dv == 0 || dv == 10 || dv == 11 ? 1 : dv
    }

    // MARK: Vencimento

    /// Data-base do fator de vencimento: 07/10/1997. Em 22/02/2025 o fator voltou para 1000 (a cada 9000 dias).
    static let factorBase = FinanceCalendar.date(1997, 10, 7)
    static let factorCycle = 9000

    /// Converte o fator para uma data dentro da janela [hoje - 3000, hoje + 5500] dias (recomendação da Febraban).
    static func dueDate(factor: Int, today: Date) -> Date? {
        guard factor > 0 else { return nil }
        var candidate = FinanceCalendar.addDays(factorBase, factor)
        for _ in 0..<4 {
            let delta = FinanceCalendar.daysBetween(today, candidate)
            if delta >= -3000 && delta <= 5500 { return candidate }
            candidate = FinanceCalendar.addDays(candidate, factorCycle)
        }
        return nil
    }

    // MARK: Análise

    /// Interpreta 44 (código de barras), 47 ou 48 (linha digitável) dígitos. nil se o tamanho não for um desses.
    static func parse(digits raw: String, today: Date) -> BoletoInfo? {
        let d = BrazilianDocument.digits(raw)
        guard raw.allSatisfy({ $0.isASCII && $0.isNumber || $0 == " " || $0 == "." || $0 == "-" }) else { return nil }
        let text = d.map(String.init).joined()
        switch d.count {
        case 47: return parseBankLine(d, text: text, today: today)
        case 44: return d[0] == 8 ? parseUtility(barcode: d, blockDVs: nil, text: text) : parseBankBarcode(d, text: text, today: today)
        case 48:
            guard d[0] == 8 else { return nil }
            return parseUtilityLine(d, text: text)
        default: return nil
        }
    }

    private static func amount(_ digits: ArraySlice<Int>) -> Decimal? {
        let cents = digits.reduce(Decimal(0)) { $0 * 10 + Decimal($1) }
        return cents == 0 ? nil : cents / 100
    }

    private static func bankInfo(barcode b: [Int], text: String, today: Date, fieldDVOK: Bool, reason: String?) -> BoletoInfo {
        let generalOK = bankMod11(Array(b[0..<4]) + Array(b[5..<44])) == b[4]
        var problem = reason
        if problem == nil, !generalOK { problem = "O dígito verificador geral não confere." }
        let factor = b[5..<9].reduce(0) { $0 * 10 + $1 }
        let valid = fieldDVOK && generalOK
        return BoletoInfo(kind: .bank, digits: text, barcode: b.map(String.init).joined(), isValid: valid, invalidReason: valid ? nil : problem,
                          amount: amount(b[9..<19]), dueDate: dueDate(factor: factor, today: today),
                          bankCode: b[0..<3].map(String.init).joined())
    }

    private static func parseBankBarcode(_ b: [Int], text: String, today: Date) -> BoletoInfo {
        bankInfo(barcode: b, text: text, today: today, fieldDVOK: true, reason: nil)
    }

    private static func parseBankLine(_ l: [Int], text: String, today: Date) -> BoletoInfo {
        let barcode = Array(l[0..<4]) + [l[32]] + Array(l[33..<47]) + Array(l[4..<9]) + Array(l[10..<20]) + Array(l[21..<31])
        let ok1 = mod10(Array(l[0..<9])) == l[9]
        let ok2 = mod10(Array(l[10..<20])) == l[20]
        let ok3 = mod10(Array(l[21..<31])) == l[31]
        var reason: String?
        if !ok1 || !ok2 || !ok3 {
            let bad = [(!ok1, "1º"), (!ok2, "2º"), (!ok3, "3º")].filter { $0.0 }.map { $0.1 }.joined(separator: ", ")
            reason = "Dígito verificador do \(bad) bloco não confere."
        }
        return bankInfo(barcode: barcode, text: text, today: today, fieldDVOK: ok1 && ok2 && ok3, reason: reason)
    }

    private static func utilityDV(_ block: [Int], valueId: Int) -> Int {
        valueId == 6 || valueId == 7 ? mod10(block) : BrazilianDocument.mod11(block)
    }

    private static func parseUtilityLine(_ l: [Int], text: String) -> BoletoInfo {
        let valueId = l[2]
        var blocks: [[Int]] = []
        var dvs: [Int] = []
        for i in 0..<4 { blocks.append(Array(l[(i * 12)..<(i * 12 + 11)])); dvs.append(l[i * 12 + 11]) }
        return parseUtility(barcode: blocks.flatMap { $0 }, blockDVs: dvs, text: text, blocks: blocks, valueId: valueId)
    }

    private static func parseUtility(barcode b: [Int], blockDVs: [Int]?, text: String, blocks: [[Int]]? = nil, valueId vid: Int? = nil) -> BoletoInfo {
        let valueId = vid ?? b[2]
        var reason: String?
        var ok = true
        if ![6, 7, 8, 9].contains(valueId) { ok = false; reason = "Identificador de valor desconhecido." }
        if ok, let blocks, let blockDVs {
            for (i, block) in blocks.enumerated() where utilityDV(block, valueId: valueId) != blockDVs[i] {
                ok = false; reason = "Dígito verificador do \(i + 1)º bloco não confere."; break
            }
        }
        if ok {
            let rest = Array(b[0..<3]) + Array(b[4..<44])
            if utilityDV(rest, valueId: valueId) != b[3] { ok = false; reason = "O dígito verificador geral não confere." }
        }
        let isReal = valueId == 6 || valueId == 7
        return BoletoInfo(kind: .utility, digits: text, barcode: b.map(String.init).joined(), isValid: ok, invalidReason: reason,
                          amount: isReal ? amount(b[4..<15]) : nil, dueDate: nil, bankCode: nil)
    }

    // MARK: Busca no texto reconhecido

    /// Sequências de dígitos (com pontos, espaços e hífens entre eles) que têm 44, 47 ou 48 dígitos.
    static func candidates(in text: String) -> [String] {
        var out: [String] = []
        for line in text.components(separatedBy: .newlines) {
            var run = ""
            func flush() {
                let digits = run.filter { $0.isASCII && $0.isNumber }
                if [44, 47, 48].contains(digits.count) { out.append(digits) }
                run = ""
            }
            for ch in line {
                if ch.isASCII && ch.isNumber { run.append(ch) }
                else if (ch == "." || ch == " " || ch == "-") && !run.isEmpty { run.append(ch) }
                else { flush() }
            }
            flush()
        }
        return out
    }

    /// Primeiro boleto encontrado no texto. Prefere um válido; se só houver inválidos, devolve o primeiro (com o motivo).
    static func find(in text: String, today: Date) -> BoletoInfo? {
        let infos = candidates(in: text).compactMap { parse(digits: $0, today: today) }
        return infos.first { $0.isValid } ?? infos.first
    }
}
