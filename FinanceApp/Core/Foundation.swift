import Foundation

// MARK: - Decimal helpers

/// Cria um Decimal exato a partir de texto ("100.01"). Nunca use literais fracionários
/// (`100.01`) para dinheiro: o Swift os converte via Double e perde precisão.
func dec(_ s: String) -> Decimal {
    guard let d = Decimal(string: s, locale: nil) else { preconditionFailure("Decimal inválido: \(s)") }
    return d
}

extension Decimal {
    /// Arredonda para `scale` casas (padrão 2) com "meio para cima" (away from zero), como o varejo BR.
    func rounded(scale: Int = 2, mode: Decimal.RoundingMode = .plain) -> Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, scale, mode)
        return result
    }

    /// Arredonda em direção a zero para `scale` casas (truncamento).
    func truncated(scale: Int = 2) -> Decimal {
        let mag = self.magnitude.rounded(scale: scale, mode: .down)
        return self < 0 ? -mag : mag
    }
}

// MARK: - Calendar (sempre Gregoriano, UTC, 12:00)

/// Todas as datas do Core são "dias civis" representados em UTC ao meio-dia.
/// A UI deve criar datas com `FinanceCalendar.date(...)` ou `FinanceCalendar.normalize(_:)`
/// (converte o dia local do usuário para o dia civil equivalente) para evitar saltos de fuso.
enum FinanceCalendar {
    static let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.locale = Locale(identifier: "pt_BR")
        return c
    }()

    /// Data civil (meio-dia UTC). `day` é limitado ao último dia do mês.
    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        YearMonth(year: year, month: month).date(day: day)
    }

    /// Converte um instante para o dia civil local do `timeZone` informado (padrão: fuso atual).
    static func normalize(_ date: Date, in timeZone: TimeZone = .current) -> Date {
        var local = Calendar(identifier: .gregorian)
        local.timeZone = timeZone
        let c = local.dateComponents([.year, .month, .day], from: date)
        return self.date(c.year!, c.month!, c.day!)
    }

    static func components(_ date: Date) -> (year: Int, month: Int, day: Int) {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return (c.year!, c.month!, c.day!)
    }

    static func startOfDay(_ date: Date) -> Date { calendar.startOfDay(for: date) }

    static func isSameDay(_ a: Date, _ b: Date) -> Bool { calendar.isDate(a, inSameDayAs: b) }

    /// Compara apenas o dia civil. true se `a` é anterior a `b` (dia).
    static func isBeforeDay(_ a: Date, _ b: Date) -> Bool { startOfDay(a) < startOfDay(b) }

    static func addDays(_ date: Date, _ n: Int) -> Date { calendar.date(byAdding: .day, value: n, to: date)! }

    /// Soma meses limitando o dia (31/jan + 1 mês = 28 ou 29/fev).
    static func addMonths(_ date: Date, _ n: Int) -> Date { calendar.date(byAdding: .month, value: n, to: date)! }

    /// Soma anos (29/fev + 1 ano = 28/fev).
    static func addYears(_ date: Date, _ n: Int) -> Date { calendar.date(byAdding: .year, value: n, to: date)! }

    /// Número de dias entre os dias civis (b - a).
    static func daysBetween(_ a: Date, _ b: Date) -> Int {
        calendar.dateComponents([.day], from: startOfDay(a), to: startOfDay(b)).day!
    }

    static func isLeapYear(_ year: Int) -> Bool { (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 }
}

/// Ano + mês (ex.: mês de referência de orçamento/fatura).
struct YearMonth: Codable, Hashable, Comparable, Sendable {
    var year: Int
    var month: Int // 1...12

    init(year: Int, month: Int) {
        // normaliza meses fora de 1...12
        let total = year * 12 + (month - 1)
        var y = total / 12
        if total % 12 < 0 { y -= 1 }
        self.year = y
        self.month = total - y * 12 + 1
    }

    init(_ date: Date) {
        let c = FinanceCalendar.components(date)
        self.init(year: c.year, month: c.month)
    }

    static func < (l: YearMonth, r: YearMonth) -> Bool { (l.year, l.month) < (r.year, r.month) }

    func adding(months n: Int) -> YearMonth { YearMonth(year: year, month: month + n) }
    var previous: YearMonth { adding(months: -1) }
    var next: YearMonth { adding(months: 1) }

    var daysInMonth: Int {
        switch month {
        case 2: return FinanceCalendar.isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    /// Data civil do dia `day` limitado a 1...daysInMonth.
    func date(day: Int) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = min(max(day, 1), daysInMonth); c.hour = 12
        return FinanceCalendar.calendar.date(from: c)!
    }

    var firstDay: Date { date(day: 1) }
    var lastDay: Date { date(day: daysInMonth) }

    func contains(_ date: Date) -> Bool { YearMonth(date) == self }

    /// Quantidade de meses de `self` até `other` (other - self).
    func months(to other: YearMonth) -> Int { (other.year - year) * 12 + (other.month - month) }

    /// "10/2025"
    var label: String { String(format: "%02d/%d", month, year) }
}

// MARK: - Money

enum DecimalStyle: Sendable { case auto, comma, dot }

enum Money {
    static let currencySymbol = "R$"
    static let nbsp = "\u{00A0}"

    /// Formata em pt-BR: "R$ 1.234,56" (espaço não separável); negativos: "-R$ 1.234,56".
    static func format(_ value: Decimal, withSymbol: Bool = true) -> String {
        let r = value.rounded(scale: 2)
        let negative = r < 0
        let abs = r.magnitude
        let text = "\(abs)"
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        let intPart = String(parts[0])
        var frac = parts.count > 1 ? String(parts[1]) : ""
        while frac.count < 2 { frac += "0" }
        var grouped = ""
        for (i, ch) in intPart.reversed().enumerated() {
            if i > 0 && i % 3 == 0 { grouped.append(".") }
            grouped.append(ch)
        }
        let number = String(grouped.reversed()) + "," + frac.prefix(2)
        let body = withSymbol ? currencySymbol + nbsp + number : number
        return negative ? "-" + body : body
    }

    /// Número com 2 casas, sem símbolo nem agrupamento ("-1234,56").
    static func plain(_ value: Decimal, decimalSeparator: Character = ",") -> String {
        let f = format(value, withSymbol: false).replacingOccurrences(of: ".", with: "")
        return f.replacingOccurrences(of: ",", with: String(decimalSeparator))
    }

    /// Interpreta textos como "R$ 1.234,56", "-1234.56", "(123,45)", "1.234", "12,5".
    /// Retorna nil se não for um número válido.
    static func parse(_ raw: String, style: DecimalStyle = .auto) -> Decimal? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "R$", with: "")
            .replacingOccurrences(of: nbsp, with: "")
            .replacingOccurrences(of: " ", with: "")
        if s.isEmpty { return nil }
        var negative = false
        if s.hasPrefix("(") && s.hasSuffix(")") { negative = true; s = String(s.dropFirst().dropLast()) }
        if s.hasPrefix("-") { negative.toggle(); s.removeFirst() }
        else if s.hasPrefix("+") { s.removeFirst() }
        if s.hasSuffix("-") { negative.toggle(); s.removeLast() }
        if s.isEmpty { return nil }
        guard s.allSatisfy({ $0.isNumber && $0.isASCII || $0 == "," || $0 == "." }) else { return nil }

        let commas = s.filter { $0 == "," }.count
        let dots = s.filter { $0 == "." }.count
        var decimalSep: Character? = nil
        switch style {
        case .comma: decimalSep = ","
        case .dot: decimalSep = "."
        case .auto:
            if commas > 0 && dots > 0 {
                decimalSep = s.lastIndex(of: ",")! > s.lastIndex(of: ".")! ? "," : "."
            } else if commas > 0 {
                decimalSep = ","            // pt-BR: vírgula é decimal
            } else if dots == 1 {
                let after = s.split(separator: ".", omittingEmptySubsequences: false).last!.count
                decimalSep = after == 3 ? nil : "."   // "1.234" = mil duzentos e trinta e quatro
            } else {
                decimalSep = nil            // vários pontos = milhares
            }
        }
        var intDigits = "", fracDigits = ""
        var seenDecimal = false
        for ch in s {
            if ch == decimalSep {
                if seenDecimal { return nil }
                seenDecimal = true
            } else if ch == "," || ch == "." {
                continue // separador de milhar
            } else if seenDecimal { fracDigits.append(ch) } else { intDigits.append(ch) }
        }
        if intDigits.isEmpty { intDigits = "0" }
        if seenDecimal && fracDigits.isEmpty { return nil }
        guard let value = Decimal(string: fracDigits.isEmpty ? intDigits : "\(intDigits).\(fracDigits)", locale: nil) else { return nil }
        return negative ? -value : value
    }

    /// Divide `total` em `count` partes de centavos exatos; a última absorve o resto.
    /// Soma das partes == total arredondado a 2 casas. Funciona com valores negativos.
    static func split(_ total: Decimal, into count: Int) -> [Decimal] {
        guard count >= 1 else { return [] }
        let t = total.rounded(scale: 2)
        let sign: Decimal = t < 0 ? -1 : 1
        let abs = t.magnitude
        let base = (abs / Decimal(count)).rounded(scale: 2, mode: .down)
        var parts = [Decimal](repeating: base * sign, count: count)
        parts[count - 1] = t - base * sign * Decimal(count - 1)
        return parts
    }

    /// Divide proporcionalmente a `weights` (ex.: divisão de despesa entre membros). Último absorve o resto.
    static func allocate(_ total: Decimal, weights: [Decimal]) -> [Decimal] {
        guard !weights.isEmpty else { return [] }
        let sum = weights.reduce(0, +)
        guard sum != 0 else { return split(total, into: weights.count) }
        let t = total.rounded(scale: 2)
        var parts: [Decimal] = []
        var acc: Decimal = 0
        for (i, w) in weights.enumerated() {
            if i == weights.count - 1 { parts.append(t - acc) }
            else {
                let p = (t * w / sum).rounded(scale: 2, mode: .plain)
                parts.append(p); acc += p
            }
        }
        return parts
    }
}
