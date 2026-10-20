import Foundation

/// O que a tela de leitura mostra antes de a pessoa usar os dados no lançamento. Sem SwiftUI, testável.
struct ScanSummary: Equatable, Sendable {
    struct Row: Equatable, Sendable {
        var label: String
        var value: String
        var identifier: String
    }

    var title: String
    var rows: [Row] = []
    var warnings: [String] = []
    var prefill: ReceiptPrefill?
    var canUse: Bool { prefill != nil }
}

enum ScanSummaryBuilder {
    static func make(_ outcome: ScanOutcome, alreadyRecorded: Bool) -> ScanSummary {
        var summary: ScanSummary
        switch outcome {
        case .failure(let message):
            return ScanSummary(title: "Não foi possível ler", warnings: [message], prefill: nil)
        case .nfce(let qr):
            summary = ScanSummary(title: "Nota fiscal (NFC-e)", prefill: outcome.prefill)
            summary.rows = [
                .init(label: "Estado", value: qr.key.uf, identifier: "scan.result.uf"),
                .init(label: "CNPJ do emitente", value: qr.key.formattedCNPJ + (qr.key.cnpjIsValid ? "" : " (inválido)"), identifier: "scan.result.cnpj"),
                .init(label: "Valor", value: qr.totalAmount.map { Money.format($0) } ?? "Não consta no QR Code", identifier: "scan.result.amount"),
                .init(label: "Chave de acesso", value: qr.key.grouped, identifier: "scan.result.key"),
            ]
            if let d = qr.emissionDate { summary.rows.insert(.init(label: "Data", value: ReportDocumentBuilder.dateText(d), identifier: "scan.result.date"), at: 3) }
            if qr.totalAmount == nil {
                summary.warnings.append("O QR Code da NFC-e não traz o valor. Digite o total do cupom. A consulta automática à SEFAZ não está disponível.")
            }
            if !qr.key.isNFCe { summary.warnings.append("Este documento é uma NF-e (modelo 55), não uma NFC-e de consumidor.") }
        case .receipt(let r):
            summary = ScanSummary(title: r.kind.displayName, prefill: outcome.prefill)
            if let a = r.amount { summary.rows.append(.init(label: "Valor", value: Money.format(a), identifier: "scan.result.amount")) }
            if r.kind == .boleto {
                if let d = r.dueDate { summary.rows.append(.init(label: "Vencimento", value: ReportDocumentBuilder.dateText(d), identifier: "scan.result.date")) }
                if let b = r.boleto { summary.rows.append(.init(label: "Linha digitável", value: b.formatted + (b.isValid ? " (válida)" : " (inválida)"), identifier: "scan.result.line")) }
            } else if let d = r.date {
                summary.rows.append(.init(label: "Data", value: ReportDocumentBuilder.dateText(d), identifier: "scan.result.date"))
            }
            if let m = r.merchant { summary.rows.append(.init(label: r.kind == .pix ? (r.suggestedType == .income ? "Origem" : "Destino") : (r.kind == .boleto ? "Beneficiário" : "Estabelecimento"), value: m, identifier: "scan.result.merchant")) }
            if r.kind == .pix { summary.rows.append(.init(label: "Tipo", value: r.suggestedType == .income ? "Receita (PIX recebido)" : "Despesa (PIX enviado)", identifier: "scan.result.type")) }
            summary.warnings = r.warnings
        }
        if alreadyRecorded { summary.warnings.append("Este documento já foi lançado antes. Salvar de novo cria um lançamento repetido.") }
        return summary
    }
}
