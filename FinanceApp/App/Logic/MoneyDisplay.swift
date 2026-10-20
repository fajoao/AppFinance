import Foundation

/// Partes de um valor monetário para o numeral dividido (R$ pequeno, reais grandes, centavos pequenos).
struct MoneyParts: Equatable, Sendable {
    var sign: String      // "" ou "−" (U+2212)
    var symbol: String    // "R$"
    var integer: String   // "1.234"
    var fraction: String  // ",56"
}

/// Como o sinal é mostrado em uma linha de valor.
enum AmountSign: Sendable {
    /// Menos tipográfico apenas se o valor for negativo.
    case natural
    /// Despesa: "−" (se o valor for um estorno negativo, vira "+").
    case expense
    /// Receita: "+" (receita negativa vira "−").
    case income
    /// Sem sinal (transferências).
    case none
}

/// Papel de cor de um valor (a UI mapeia para os tokens de cor).
enum AmountRole: Equatable, Sendable { case income, expense, transfer, negative, zero, positive }

/// Formatação de valores para exibição. Os dígitos vêm de `Money.format` (Core); aqui só entram sinal tipográfico,
/// máscara de privacidade e leitura por extenso para VoiceOver.
enum MoneyDisplay {
    static let minus = "\u{2212}"
    static let nbsp = "\u{00A0}"
    static let masked = "R$" + nbsp + "••••"
    static let hiddenSpoken = "valor oculto"

    static func parts(_ value: Decimal) -> MoneyParts {
        let r = value.rounded(scale: 2)
        let digits = Money.format(r.magnitude, withSymbol: false)
        let pieces = digits.split(separator: ",", omittingEmptySubsequences: false)
        return MoneyParts(sign: r < 0 ? minus : "", symbol: Money.currencySymbol,
                          integer: String(pieces[0]), fraction: "," + (pieces.count > 1 ? String(pieces[1]) : "00"))
    }

    /// "R$ 1.234,56", "−R$ 45,90", "+R$ 5.200,00". Oculto: "R$ ••••".
    static func text(_ value: Decimal, sign: AmountSign = .natural, hidden: Bool = false) -> String {
        if hidden { return masked }
        let r = value.rounded(scale: 2)
        let body = Money.format(r.magnitude)
        switch sign {
        case .natural: return (r < 0 ? minus : "") + body
        case .none: return body
        case .expense: return r == 0 ? body : (r > 0 ? minus : "+") + body
        case .income: return r == 0 ? body : (r > 0 ? "+" : minus) + body
        }
    }

    /// Valor sem símbolo para campos de edição ("1.234,56").
    static func number(_ value: Decimal) -> String { Money.format(value, withSymbol: false) }

    static func role(for value: Decimal) -> AmountRole { value < 0 ? .negative : (value == 0 ? .zero : .positive) }

    static func role(for tx: Transaction) -> AmountRole {
        if tx.isInvoicePayment { return .transfer }
        switch tx.type {
        case .income: return .income
        case .expense: return .expense
        case .transfer: return .transfer
        }
    }

    static func text(for tx: Transaction, hidden: Bool = false) -> String {
        switch tx.type {
        case .income: return text(tx.amount, sign: .income, hidden: hidden)
        case .expense: return text(tx.amount, sign: .expense, hidden: hidden)
        case .transfer: return text(tx.amount, sign: .none, hidden: hidden)
        }
    }

    /// Leitura por extenso: "menos quarenta e cinco reais e noventa centavos".
    static func spoken(_ value: Decimal, prefix: String? = nil, hidden: Bool = false) -> String {
        if hidden { return hiddenSpoken }
        let r = value.rounded(scale: 2)
        var s = PortugueseWords.currency(r.magnitude)
        if r < 0 { s = "menos " + s } else if let prefix { s = prefix + " " + s }
        return s
    }

    static func spoken(for tx: Transaction, hidden: Bool = false) -> String {
        if hidden { return hiddenSpoken }
        if tx.isInvoicePayment { return "pagamento de fatura, " + spoken(tx.amount) }
        switch tx.type {
        case .income: return "receita, " + spoken(tx.amount, prefix: "mais")
        case .expense: return "despesa, " + spoken(tx.amount, prefix: "menos")
        case .transfer: return "transferência, " + spoken(tx.amount)
        }
    }

    /// "1,2 mil" / "R$ 3,4 mi" para eixos de gráfico (único lugar sem centavos).
    static func axis(_ value: Decimal) -> String {
        let v = NSDecimalNumber(decimal: value).doubleValue   // só exibição de eixo; nunca usado em cálculo
        let a = abs(v)
        func f(_ x: Double) -> String {
            let s = String(format: "%.1f", x).replacingOccurrences(of: ".", with: ",")
            return s.hasSuffix(",0") ? String(s.dropLast(2)) : s
        }
        if a >= 1_000_000 { return "R$" + nbsp + f(v / 1_000_000) + " mi" }
        if a >= 1_000 { return "R$" + nbsp + f(v / 1_000) + " mil" }
        return "R$" + nbsp + f(v)
    }
}

/// Números por extenso em português do Brasil (para leitura de valores).
enum PortugueseWords {
    private static let units = ["zero", "um", "dois", "três", "quatro", "cinco", "seis", "sete", "oito", "nove", "dez",
                                "onze", "doze", "treze", "quatorze", "quinze", "dezesseis", "dezessete", "dezoito", "dezenove"]
    private static let tens = ["", "", "vinte", "trinta", "quarenta", "cinquenta", "sessenta", "setenta", "oitenta", "noventa"]
    private static let hundreds = ["", "cento", "duzentos", "trezentos", "quatrocentos", "quinhentos", "seiscentos",
                                   "setecentos", "oitocentos", "novecentos"]

    /// 0...999
    private static func below1000(_ n: Int) -> String {
        if n == 100 { return "cem" }
        var parts: [String] = []
        let h = n / 100, rest = n % 100
        if h > 0 { parts.append(hundreds[h]) }
        if rest > 0 {
            if rest < 20 { parts.append(units[rest]) }
            else {
                var t = tens[rest / 10]
                if rest % 10 > 0 { t += " e " + units[rest % 10] }
                parts.append(t)
            }
        }
        return parts.joined(separator: " e ")
    }

    /// 0...999.999.999.999
    static func integer(_ n: Int) -> String {
        if n == 0 { return "zero" }
        precondition(n > 0)
        let scales: [(Int, String, String)] = [(1_000_000_000, "bilhão", "bilhões"), (1_000_000, "milhão", "milhões"), (1_000, "mil", "mil")]
        var rest = n
        var chunks: [(text: String, value: Int)] = []
        for (size, singular, plural) in scales {
            let q = rest / size
            rest %= size
            guard q > 0 else { continue }
            let text: String
            if size == 1_000 { text = q == 1 ? "mil" : below1000(q) + " mil" }
            else { text = below1000(q) + " " + (q == 1 ? singular : plural) }
            chunks.append((text, q * size))
        }
        if rest > 0 { chunks.append((below1000(rest), rest)) }
        var out = chunks[0].text
        for (i, c) in chunks.enumerated().dropFirst() {
            let isLast = i == chunks.count - 1
            // "e" antes do último bloco quando ele é < 100 ou múltiplo de 100 ("mil e cem", "mil duzentos e trinta")
            let useE = isLast && (c.value < 100 || c.value % 100 == 0)
            out += (useE ? " e " : " ") + c.text
        }
        return out
    }

    /// "quarenta e cinco reais e noventa centavos" (valor não negativo, 2 casas).
    static func currency(_ value: Decimal) -> String {
        let r = value.rounded(scale: 2)
        let cents = NSDecimalNumber(decimal: r * 100).intValue
        let reais = cents / 100, centavos = cents % 100
        var parts: [String] = []
        if reais > 0 || centavos == 0 {
            let millionExact = reais >= 1_000_000 && reais % 1_000_000 == 0
            parts.append(integer(reais) + (millionExact ? " de" : "") + (reais == 1 ? " real" : " reais"))
        }
        if centavos > 0 { parts.append(integer(centavos) + (centavos == 1 ? " centavo" : " centavos")) }
        return parts.joined(separator: " e ")
    }
}
