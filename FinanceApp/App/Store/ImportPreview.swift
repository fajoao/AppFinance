import Foundation

/// Resultado da leitura de um extrato (OFX/CSV), pronto para revisão antes de gravar.
struct ImportPreview: Equatable, Sendable {
    var fileName: String
    var candidates: [CandidateTransaction]
    var issues: [ImportIssue]

    var newCandidates: [CandidateTransaction] { candidates.filter { !$0.isDuplicate } }
    var duplicateCount: Int { candidates.filter(\.isDuplicate).count }
    var newCount: Int { newCandidates.count }
    var isEmpty: Bool { candidates.isEmpty }

    /// "3 importados, 1 repetido ignorado"
    var summaryText: String {
        let n = newCount, m = duplicateCount
        let a = n == 1 ? "1 importado" : "\(n) importados"
        let b = m == 1 ? "1 repetido ignorado" : "\(m) repetidos ignorados"
        return "\(a), \(b)"
    }

    enum Format { case ofx, csv }

    static func format(fileName: String, data: Data) -> Format {
        let ext = (fileName as NSString).pathExtension.lowercased()
        if ext == "ofx" || ext == "qfx" { return .ofx }
        if ext == "csv" || ext == "txt" { return .csv }
        let head = TextDecoding.string(from: data.prefix(2048)).uppercased()
        return head.contains("<OFX") || head.contains("OFXHEADER") ? .ofx : .csv
    }

    /// Lê o arquivo (Core: OFXParser/CSVParser), marca duplicadas (DuplicateDetector) e sugere categorias.
    static func make(fileName: String, data: Data, accountId: UUID?, existing: [Transaction],
                     suggestExpense: CategorySuggester, suggestIncome: CategorySuggester) -> ImportPreview {
        let parsed: ImportResult
        switch format(fileName: fileName, data: data) {
        case .ofx: parsed = OFXParser.parse(data: data)
        case .csv: parsed = CSVParser.parse(data: data)
        }
        var marked = DuplicateDetector.mark(parsed.candidates, existing: existing, accountId: accountId)
        for i in marked.indices where !marked[i].isDuplicate {
            let c = marked[i]
            marked[i].suggestedCategoryId = (c.type == .expense ? suggestExpense : suggestIncome).suggest(for: c.title, type: c.type)
        }
        return ImportPreview(fileName: fileName, candidates: marked, issues: parsed.issues)
    }
}

/// Extrato de exemplo (mesmo do protótipo) para testar a importação sem arquivo.
enum SampleStatement {
    static let ofx = """
    OFXHEADER:100
    DATA:OFXSGML
    <OFX><BANKMSGSRSV1><STMTTRNRS><STMTRS><CURDEF>BRL<BANKTRANLIST>
    <STMTTRN><TRNTYPE>DEBIT<DTPOSTED>20261016120000[-3:BRT]<TRNAMT>-58.70<FITID>OFX-001<MEMO>POSTO IPIRANGA
    </STMTTRN><STMTTRN><TRNTYPE>DEBIT<DTPOSTED>20261017090000[-3:BRT]<TRNAMT>-31.90<FITID>OFX-002<MEMO>DROGARIA SAO PAULO
    </STMTTRN><STMTTRN><TRNTYPE>CREDIT<DTPOSTED>20261018100000[-3:BRT]<TRNAMT>350.00<FITID>OFX-003<MEMO>PIX RECEBIDO CLIENTE PROJETO
    </STMTTRN></BANKTRANLIST></STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>
    """
}
