import Foundation

/// Apresentação dos insights: aplica "Ocultar valores" aos textos prontos do Core e dá símbolo/rótulo por tipo.
enum InsightsPresentation {
    static let hiddenMoney = "R$\u{00A0}••••"

    /// Troca todo valor em reais do texto ("R$ 1.234,56", "-R$ 20,00") por "R$ ••••". Datas e percentuais ficam.
    static func maskMoney(in text: String) -> String {
        let prefix = Array("R$\u{00A0}")
        let chars = Array(text)
        var out = ""
        var i = 0
        while i < chars.count {
            if i + prefix.count <= chars.count, Array(chars[i..<(i + prefix.count)]) == prefix {
                var j = i + prefix.count
                while j < chars.count, chars[j].isASCII && chars[j].isNumber || chars[j] == "." || chars[j] == "," {
                    // vírgula/ponto finais pertencem à frase, não ao número
                    if (chars[j] == "." || chars[j] == ","), !(j + 1 < chars.count && chars[j + 1].isASCII && chars[j + 1].isNumber) { break }
                    j += 1
                }
                out += hiddenMoney
                i = j
            } else {
                out.append(chars[i]); i += 1
            }
        }
        return out
    }

    static func text(_ s: String, hidden: Bool) -> String { hidden ? maskMoney(in: s) : s }

    static func symbol(for kind: InsightKind) -> String {
        switch kind {
        case .negativeRisk: return "exclamationmark.triangle.fill"
        case .forecast: return "chart.line.uptrend.xyaxis"
        case .anomaly: return "waveform.path.ecg"
        case .subscription: return "arrow.triangle.2.circlepath"
        case .saving: return "leaf"
        }
    }

    static func sectionTitle(for kind: InsightKind) -> String {
        switch kind {
        case .negativeRisk, .anomaly: return "Atenção"
        case .forecast: return "Previsão"
        case .subscription: return "Assinaturas e recorrências"
        case .saving: return "Sugestões de economia"
        }
    }

    /// "mensal", "semanal", "anual"
    static func frequencyText(_ f: RecurrenceFrequency) -> String {
        switch f {
        case .monthly: return "todo mês"
        case .weekly: return "toda semana"
        case .yearly: return "todo ano"
        }
    }
}
