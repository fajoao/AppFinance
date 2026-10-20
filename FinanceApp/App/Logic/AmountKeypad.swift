import Foundation

/// Teclado numérico próprio do "Novo lançamento": 1-9, vírgula, 0 e apagar. Sem Double.
struct AmountKeypad: Equatable, Sendable {
    enum Key: Equatable, Sendable { case digit(Int), comma, delete }

    static let maxIntegerDigits = 9
    static let maxFractionDigits = 2

    private(set) var integerDigits: String = ""
    /// nil = vírgula ainda não digitada.
    private(set) var fractionDigits: String? = nil

    init() {}

    init(value: Decimal) {
        let v = value.rounded(scale: 2).magnitude
        guard v > 0 else { return }
        let plain = Money.plain(v, decimalSeparator: ".")   // "1234.50"
        let pieces = plain.split(separator: ".")
        integerDigits = String(pieces[0])
        var frac = pieces.count > 1 ? String(pieces[1]) : ""
        while frac.hasSuffix("0") { frac.removeLast() }
        if !frac.isEmpty { fractionDigits = frac }
        if integerDigits == "0" { integerDigits = "" }
    }

    var isEmpty: Bool { integerDigits.isEmpty && (fractionDigits ?? "").isEmpty }

    mutating func press(_ key: Key) {
        switch key {
        case .digit(let d):
            guard (0...9).contains(d) else { return }
            if var f = fractionDigits {
                guard f.count < Self.maxFractionDigits else { return }
                f.append(String(d)); fractionDigits = f
            } else {
                if integerDigits.isEmpty && d == 0 { integerDigits = "0"; return }
                if integerDigits == "0" { integerDigits = String(d); return }
                guard integerDigits.count < Self.maxIntegerDigits else { return }
                integerDigits.append(String(d))
            }
        case .comma:
            if fractionDigits == nil { fractionDigits = "" ; if integerDigits.isEmpty { integerDigits = "0" } }
        case .delete:
            if let f = fractionDigits {
                fractionDigits = f.isEmpty ? nil : String(f.dropLast())
            } else if !integerDigits.isEmpty {
                integerDigits.removeLast()
            }
        }
    }

    mutating func clear() { integerDigits = ""; fractionDigits = nil }

    /// Valor digitado (>= 0).
    var value: Decimal {
        let i = integerDigits.isEmpty ? "0" : integerDigits
        let f = fractionDigits ?? ""
        return Decimal(string: f.isEmpty ? i : "\(i).\(f)", locale: nil) ?? 0
    }

    /// Partes para o numeral dividido: milhar agrupado e centavos exatamente como digitados (",5" ou ",50" com cursor).
    var displayParts: MoneyParts {
        let i = integerDigits.isEmpty ? "0" : integerDigits
        let grouped = Money.format(Decimal(string: i, locale: nil) ?? 0, withSymbol: false).split(separator: ",")[0]
        let frac: String
        if let f = fractionDigits { frac = "," + f + String(repeating: "0", count: Self.maxFractionDigits - f.count) }
        else { frac = ",00" }
        return MoneyParts(sign: "", symbol: Money.currencySymbol, integer: String(grouped), fraction: frac)
    }

    /// Quantos dígitos de centavos ainda são "fantasma" (preenchidos com zero na exibição).
    var typedFractionCount: Int { fractionDigits?.count ?? 0 }
}
