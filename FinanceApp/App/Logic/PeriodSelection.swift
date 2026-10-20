import Foundation

/// Regras do seletor global de período (mês/ano): limites, navegação, escolha na sheet e textos pt-BR.
/// Puro (sem SwiftUI) para ser testado com swiftc. O estado fica em `AppStore.viewedMonth`.
enum PeriodSelection {
    /// Limites razoáveis: de janeiro de 2000 a dezembro de 2100.
    static let minimum = YearMonth(year: 2000, month: 1)
    static let maximum = YearMonth(year: 2100, month: 12)
    static var years: ClosedRange<Int> { minimum.year...maximum.year }

    static func clamp(_ month: YearMonth) -> YearMonth { min(max(month, minimum), maximum) }

    static func canMove(_ month: YearMonth, by months: Int) -> Bool {
        let target = month.adding(months: months)
        return target >= minimum && target <= maximum
    }

    /// Anda `months` meses (negativo = para trás), sem passar dos limites.
    static func moved(_ month: YearMonth, by months: Int) -> YearMonth { clamp(month.adding(months: months)) }

    /// Mês escolhido na sheet (grade de meses + ano).
    static func select(month: Int, year: Int) -> YearMonth { clamp(YearMonth(year: year, month: month)) }

    static func canSelectYear(_ year: Int) -> Bool { years.contains(year) }

    static func current(today: Date) -> YearMonth { YearMonth(today) }

    static func isCurrent(_ month: YearMonth, today: Date) -> Bool { month == current(today: today) }

    /// "Outubro de 2026"
    static func title(_ month: YearMonth) -> String { DateText.monthYear(month) }

    /// Leitura do VoiceOver para o título do seletor.
    static func accessibilityLabel(_ month: YearMonth) -> String { "\(title(month)), selecionar mês" }

    /// "Jan", "Fev"... (3 letras, sem ponto) para a grade 3x4.
    static func gridLabel(month: Int) -> String {
        DateText.capitalized(DateText.months3[month - 1].replacingOccurrences(of: ".", with: ""))
    }

    /// "Maio de 2027" (leitura de cada célula da grade).
    static func monthAccessibilityLabel(month: Int, year: Int) -> String { title(YearMonth(year: year, month: month)) }
}
