import Foundation

/// Transação candidata lida de um extrato (ainda não salva).
struct CandidateTransaction: Sendable, Equatable {
    var date: Date
    var title: String
    /// Valor com sinal como no extrato (negativo = saída).
    var amount: Decimal
    var externalId: String?
    var isDuplicate: Bool = false
    var suggestedCategoryId: UUID? = nil

    var type: TransactionType { amount < 0 ? .expense : .income }

    func toTransaction(accountId: UUID, status: TransactionStatus = .paid, categoryId: UUID? = nil) -> Transaction {
        Transaction(type: type, amount: amount.magnitude, date: date, title: title, status: status,
                    accountId: accountId, categoryId: categoryId ?? suggestedCategoryId, externalId: externalId)
    }
}

struct ImportIssue: Sendable, Equatable {
    var line: Int
    var message: String
}

struct ImportResult: Sendable, Equatable {
    var candidates: [CandidateTransaction] = []
    var issues: [ImportIssue] = []
}

enum TextDecoding {
    /// UTF-8 (com/sem BOM) com fallback para Windows-1252/Latin-1 (comum em extratos brasileiros).
    static func string(from data: Data) -> String {
        if let s = String(data: data, encoding: .utf8) { return s.hasPrefix("\u{FEFF}") ? String(s.dropFirst()) : s }
        if let s = String(data: data, encoding: .windowsCP1252) { return s }
        return String(decoding: data, as: UTF8.self)
    }

    static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
            .lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum DateParsing {
    /// dd/MM/yyyy, dd/MM/yy, dd-MM-yyyy, dd.MM.yyyy, yyyy-MM-dd, yyyy/MM/dd. Datas inválidas (31/02) retornam nil.
    static func parse(_ raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        let seps = CharacterSet(charactersIn: "/-.")
        let parts = s.components(separatedBy: seps)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } }) else { return nil }
        var y: Int, m: Int, d: Int
        if parts[0].count == 4 { y = Int(parts[0])!; m = Int(parts[1])!; d = Int(parts[2])! }
        else if parts[2].count == 4 { d = Int(parts[0])!; m = Int(parts[1])!; y = Int(parts[2])! }
        else if parts[2].count == 2 { d = Int(parts[0])!; m = Int(parts[1])!; y = 2000 + Int(parts[2])! }
        else { return nil }
        guard (1...12).contains(m), d >= 1, d <= YearMonth(year: y, month: m).daysInMonth else { return nil }
        return FinanceCalendar.date(y, m, d)
    }
}

enum CSVParser {
    /// Quebra o texto em linhas/campos (aspas, aspas escapadas "", quebras de linha dentro de aspas, CRLF).
    static func rows(_ text: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var chars = Array(text)
        if chars.first == "\u{FEFF}" { chars.removeFirst() }
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 } else { inQuotes = false }
                } else { field.append(c) }
            } else if c == "\"" { inQuotes = true }
            else if c == delimiter { row.append(field); field = "" }
            else if c == "\n" || c == "\r\n" || c == "\r" {
                row.append(field); field = ""
                if !(row.count == 1 && row[0].trimmingCharacters(in: .whitespaces).isEmpty) { rows.append(row) }
                row = []
            } else { field.append(c) }
            i += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            if !(row.count == 1 && row[0].trimmingCharacters(in: .whitespaces).isEmpty) { rows.append(row) }
        }
        return rows
    }

    static func detectDelimiter(_ text: String) -> Character {
        let firstLine = text.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }).first.map(String.init) ?? ""
        var best: Character = ";"; var bestCount = -1
        for d in [";", ",", "\t"] as [Character] {
            var n = 0, q = false
            for c in firstLine { if c == "\"" { q.toggle() } else if c == d && !q { n += 1 } }
            if n > bestCount { best = d; bestCount = n }
        }
        return best
    }

    static func parse(_ text: String, delimiter: Character? = nil) -> ImportResult {
        let delim = delimiter ?? detectDelimiter(text)
        let all = rows(text, delimiter: delim)
        var result = ImportResult()
        guard !all.isEmpty else { return result }

        // Mapeia colunas pelo cabeçalho (pt/en); sem cabeçalho assume data, descrição, valor.
        let header = all[0].map(TextDecoding.normalize)
        func index(_ keys: [String]) -> Int? { header.firstIndex { h in keys.contains { h.contains($0) } } }
        let hasHeader = DateParsing.parse(all[0].first ?? "") == nil
        var dateCol = 0, descCol = 1, amountCol: Int? = 2, debitCol: Int? = nil, creditCol: Int? = nil, idCol: Int? = nil
        var startRow = 0
        if hasHeader {
            startRow = 1
            guard let dc = index(["data", "date"]) else {
                result.issues.append(ImportIssue(line: 1, message: "Coluna de data não encontrada"))
                return result
            }
            dateCol = dc
            descCol = index(["descricao", "historico", "description", "memo", "estabelecimento", "lancamento", "titulo", "detalhe"]) ?? (dc == 0 ? 1 : 0)
            amountCol = index(["valor", "amount", "value", "quantia"])
            debitCol = index(["debito", "saida", "debit"])
            creditCol = index(["credito", "entrada", "credit"])
            idCol = index(["identificador", "fitid", "documento"])
            if idCol == dc || idCol == descCol || idCol == amountCol { idCol = nil }
            if amountCol == nil && debitCol == nil && creditCol == nil {
                result.issues.append(ImportIssue(line: 1, message: "Coluna de valor não encontrada"))
                return result
            }
        }
        for r in startRow..<all.count {
            let row = all[r]
            let line = r + 1
            func cell(_ i: Int?) -> String? { guard let i, i < row.count else { return nil }; return row[i].trimmingCharacters(in: .whitespaces) }
            guard let dateText = cell(dateCol), let date = DateParsing.parse(dateText) else {
                result.issues.append(ImportIssue(line: line, message: "Data inválida")); continue
            }
            var amount: Decimal?
            if let a = cell(amountCol), !a.isEmpty { amount = Money.parse(a) }
            else {
                let debit = cell(debitCol).flatMap { $0.isEmpty ? nil : Money.parse($0) }
                let credit = cell(creditCol).flatMap { $0.isEmpty ? nil : Money.parse($0) }
                if let debit { amount = -debit.magnitude } else if let credit { amount = credit.magnitude }
            }
            guard let value = amount else {
                result.issues.append(ImportIssue(line: line, message: "Valor inválido")); continue
            }
            let title = cell(descCol) ?? ""
            let ext = cell(idCol).flatMap { $0.isEmpty ? nil : $0 }
            result.candidates.append(CandidateTransaction(date: date, title: title.isEmpty ? "Sem descrição" : title, amount: value, externalId: ext))
        }
        return result
    }

    static func parse(data: Data, delimiter: Character? = nil) -> ImportResult { parse(TextDecoding.string(from: data), delimiter: delimiter) }
}

enum OFXParser {
    /// Lê OFX/QFX (SGML 1.x ou XML 2.x). Retorna uma candidata por <STMTTRN>.
    static func parse(_ text: String) -> ImportResult {
        var result = ImportResult()
        guard text.uppercased().contains("<OFX") || text.uppercased().contains("<STMTTRN") else {
            result.issues.append(ImportIssue(line: 0, message: "Não parece um arquivo OFX"))
            return result
        }
        // tokeniza <TAG>valor
        var tokens: [(tag: String, value: String)] = []
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            if chars[i] == "<" {
                var j = i + 1
                while j < chars.count && chars[j] != ">" { j += 1 }
                if j >= chars.count { break }
                let tag = String(chars[(i + 1)..<j]).uppercased()
                var k = j + 1
                while k < chars.count && chars[k] != "<" { k += 1 }
                let value = String(chars[(j + 1)..<k]).trimmingCharacters(in: .whitespacesAndNewlines)
                tokens.append((tag, value))
                i = k
            } else { i += 1 }
        }
        var cur: [String: String]? = nil
        var n = 0
        func flush() {
            guard let c = cur else { return }
            n += 1
            cur = nil
            guard let dt = c["DTPOSTED"], dt.count >= 8, let date = parseOFXDate(dt) else {
                result.issues.append(ImportIssue(line: n, message: "Data inválida na transação \(n)")); return
            }
            guard let amtText = c["TRNAMT"], let amt = Money.parse(amtText, style: amtText.contains(",") ? .comma : .dot) else {
                result.issues.append(ImportIssue(line: n, message: "Valor inválido na transação \(n)")); return
            }
            let name = decode(c["NAME"] ?? "")
            let memo = decode(c["MEMO"] ?? "")
            let title = !memo.isEmpty ? (name.isEmpty || name == memo ? memo : "\(name) - \(memo)") : (name.isEmpty ? "Sem descrição" : name)
            result.candidates.append(CandidateTransaction(date: date, title: title, amount: amt, externalId: c["FITID"].flatMap { $0.isEmpty ? nil : $0 }))
        }
        for (tag, value) in tokens {
            switch tag {
            case "STMTTRN": flush(); cur = [:]
            case "/STMTTRN", "/BANKTRANLIST", "/CCSTMTRS", "/STMTRS": flush()
            default:
                if cur != nil, !tag.hasPrefix("/"), !value.isEmpty { cur![tag] = value }
            }
        }
        flush()
        return result
    }

    static func parse(data: Data) -> ImportResult { parse(TextDecoding.string(from: data)) }

    /// YYYYMMDD[HHMMSS[.XXX][offset]] -> dia civil (ignora hora/fuso: usa o dia declarado).
    static func parseOFXDate(_ s: String) -> Date? {
        let digits = Array(s.prefix(8))
        guard digits.count == 8, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        let y = Int(String(digits[0..<4]))!, m = Int(String(digits[4..<6]))!, d = Int(String(digits[6..<8]))!
        guard (1...12).contains(m), d >= 1, d <= YearMonth(year: y, month: m).daysInMonth else { return nil }
        return FinanceCalendar.date(y, m, d)
    }

    private static func decode(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
    }
}

enum DuplicateDetector {
    /// Marca candidatas que já existem. Critérios: mesmo `externalId`; ou mesmo dia + mesmo valor com sinal +
    /// descrição igual/contida (normalizada). Cada lançamento existente "consome" no máximo uma candidata,
    /// então duas compras idênticas no mesmo dia só são duplicadas se já houver dois lançamentos.
    static func mark(_ candidates: [CandidateTransaction], existing: [Transaction], accountId: UUID? = nil) -> [CandidateTransaction] {
        let pool = existing.filter { accountId == nil || $0.accountId == accountId || $0.destinationAccountId == accountId }
        var used = Set<UUID>()
        func signed(_ t: Transaction) -> Decimal { t.type == .transfer ? (t.accountId == accountId ? -t.amount : t.amount) : t.signedAmount }
        return candidates.map { c in
            var c = c
            if let ext = c.externalId, let hit = pool.first(where: { $0.externalId == ext && !used.contains($0.id) }) {
                used.insert(hit.id); c.isDuplicate = true; return c
            }
            let ct = TextDecoding.normalize(c.title)
            if let hit = pool.first(where: { t in
                guard !used.contains(t.id), FinanceCalendar.isSameDay(t.date, c.date), signed(t) == c.amount else { return false }
                let tt = TextDecoding.normalize(t.title)
                return tt == ct || tt.contains(ct) || ct.contains(tt)
            }) { used.insert(hit.id); c.isDuplicate = true }
            return c
        }
    }
}

// MARK: - Exportação CSV

struct CSVExportOptions: Sendable {
    var delimiter: Character = ";"
    /// Valores com vírgula decimal (pt-BR, Excel BR). Se false, usa ponto.
    var decimalComma: Bool = true
}

enum CSVExporter {
    static let header = ["data", "descricao", "tipo", "valor", "status", "conta", "categoria", "tags", "observacao"]

    static func formatDate(_ d: Date) -> String {
        let c = FinanceCalendar.components(d)
        return String(format: "%02d/%02d/%04d", c.day, c.month, c.year)
    }

    static func escape(_ s: String, delimiter: Character) -> String {
        // Prefixa fórmulas (=,+,-,@) para evitar injeção em planilhas, exceto números.
        var v = s
        if let f = v.first, "=@".contains(f) { v = "'" + v }
        if v.contains(delimiter) || v.contains("\"") || v.contains("\n") || v.contains("\r") {
            return "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return v
    }

    static func export(transactions: [Transaction], accounts: [Account] = [], categories: [Category] = [], tags: [Tag] = [],
                       options: CSVExportOptions = CSVExportOptions()) -> String {
        let accountName = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0.name) })
        let categoryName = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0.name) })
        let tagName = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0.name) })
        let d = String(options.delimiter)
        var lines = [header.joined(separator: d)]
        for tx in transactions.sorted(by: { $0.date < $1.date }) {
            let signed: Decimal = tx.type == .transfer ? -tx.amount : tx.signedAmount
            let amount = Money.plain(signed, decimalSeparator: options.decimalComma ? "," : ".")
            let tipo = tx.type == .income ? "receita" : (tx.type == .expense ? "despesa" : "transferencia")
            let fields = [
                formatDate(tx.date), tx.title, tipo, amount,
                tx.status == .paid ? "pago" : "pendente",
                tx.accountId.flatMap { accountName[$0] } ?? "",
                tx.categoryId.flatMap { categoryName[$0] } ?? "",
                tx.tagIds.compactMap { tagName[$0] }.joined(separator: "|"),
                tx.note ?? "",
            ]
            lines.append(fields.map { escape($0, delimiter: options.delimiter) }.joined(separator: d))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

// MARK: - Sugestão de categoria

struct CategorySuggester: Sendable {
    private var exact: [String: [UUID: Int]] = [:]
    private var tokenCounts: [TransactionType: [String: [UUID: Int]]] = [:]
    /// Palavras-chave manuais (categoria -> termos), têm prioridade sobre o histórico estatístico.
    var keywords: [UUID: [String]] = [:]

    static let stopwords: Set<String> = ["de", "da", "do", "das", "dos", "em", "no", "na", "para", "com", "por", "pix", "compra", "pagamento", "pag", "the", "and", "ltda", "sa"]

    static func tokens(_ s: String) -> [String] {
        TextDecoding.normalize(s)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 && !stopwords.contains($0) && !$0.allSatisfy(\.isNumber) }
    }

    init(history: [Transaction] = [], keywords: [UUID: [String]] = [:]) {
        self.keywords = keywords
        for tx in history { learn(tx) }
    }

    mutating func learn(_ tx: Transaction) {
        guard let cat = tx.categoryId, tx.type != .transfer else { return }
        exact[TextDecoding.normalize(tx.title), default: [:]][cat, default: 0] += 1
        for t in Set(Self.tokens(tx.title)) {
            tokenCounts[tx.type, default: [:]][t, default: [:]][cat, default: 0] += 1
        }
    }

    func suggest(for title: String, type: TransactionType = .expense) -> UUID? {
        let norm = TextDecoding.normalize(title)
        if norm.isEmpty { return nil }
        // 1) palavras-chave manuais (ordem determinística por uuid)
        for (cat, words) in keywords.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            if words.contains(where: { norm.contains(TextDecoding.normalize($0)) }) { return cat }
        }
        // 2) descrição idêntica no histórico
        if let m = exact[norm], let best = Self.best(m) { return best }
        // 3) votação por palavras
        var score: [UUID: Double] = [:]
        for t in Set(Self.tokens(title)) {
            guard let m = tokenCounts[type]?[t] else { continue }
            let total = Double(m.values.reduce(0, +))
            for (cat, n) in m { score[cat, default: 0] += Double(n) / total }
        }
        let top = score.max { a, b in a.value != b.value ? a.value < b.value : a.key.uuidString > b.key.uuidString }
        return top?.key
    }

    private static func best(_ m: [UUID: Int]) -> UUID? {
        m.max { a, b in a.value != b.value ? a.value < b.value : a.key.uuidString > b.key.uuidString }?.key
    }
}
