import Foundation

/// Textos pt-BR para percentuais, juros e quantidades (sem Double).
enum Fmt {
    /// "15,57%": arredonda para `scale` casas e completa com zeros até `scale` casas ("23,0%" com scale 1, "23%" com 0).
    static func percent(_ value: Decimal, scale: Int = 2) -> String {
        let r = value.rounded(scale: scale)
        var s = "\(r)".replacingOccurrences(of: ".", with: ",")
        guard scale > 0 else { return s + "%" }
        if !s.contains(",") { s += "," }
        let frac = s.split(separator: ",", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        s += String(repeating: "0", count: max(scale - frac.count, 0))
        return s + "%"
    }

    /// Percentual com sinal: "+15,57%", "-20,00%".
    static func signedPercent(_ value: Decimal) -> String {
        (value > 0 ? "+" : "") + percent(value)
    }

    /// Juros mensais em fração -> "14,5% ao mês".
    static func monthlyRate(_ fraction: Decimal) -> String {
        let pct = (fraction * 100).rounded(scale: 4)
        return "\(pct)".replacingOccurrences(of: ".", with: ",") + "% ao mês"
    }

    /// Quantidade sem zeros à direita: "100", "0,0042".
    static func quantity(_ value: Decimal) -> String { "\(value)".replacingOccurrences(of: ".", with: ",") }

    /// "19/10/2026"
    static func date(_ date: Date) -> String { ReportDocumentBuilder.dateText(date) }

    /// "out. de 2027"
    static func monthYearShort(_ date: Date) -> String {
        let c = FinanceCalendar.components(date)
        return "\(DateText.months3[c.month - 1]) de \(c.year)"
    }
}
