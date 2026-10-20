import Foundation

// NFC-e: leitura do QR Code impresso no cupom (nota fiscal de consumidor eletrônica).
//
// O QR Code contém uma URL da SEFAZ do estado com o parâmetro `p=` (ou, em layouts antigos, `chNFe=`).
// A chave de acesso tem 44 dígitos: cUF(2) AAMM(4) CNPJ(14) modelo(2) série(3) número(9) tpEmis(1) cNF(8) DV(1).
// O DV é módulo 11 (pesos 2 a 9, da direita para a esquerda). Tudo aqui é local: nenhuma consulta de rede.
// A consulta online à SEFAZ (nome do estabelecimento, itens) NÃO está implementada; veja `NFCeLookupService`.

/// Documentos brasileiros (validação de dígito verificador).
enum BrazilianDocument {
    /// Soma ponderada módulo 11 com pesos 2...9 repetidos, da direita para a esquerda. DV = 0 se resto 0 ou 1.
    static func mod11(_ digits: [Int]) -> Int {
        var sum = 0
        var weight = 2
        for d in digits.reversed() {
            sum += d * weight
            weight = weight == 9 ? 2 : weight + 1
        }
        let r = sum % 11
        return r <= 1 ? 0 : 11 - r
    }

    static func digits(_ s: String) -> [Int] { s.compactMap { $0.isASCII ? $0.wholeNumberValue : nil } }

    static func isValidCNPJ(_ raw: String) -> Bool {
        let d = digits(raw)
        guard d.count == 14, Set(d).count > 1 else { return false }
        func dv(_ n: Int) -> Int {
            let weights = n == 12 ? [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2] : [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]
            let sum = zip(d.prefix(n), weights).reduce(0) { $0 + $1.0 * $1.1 }
            let r = sum % 11
            return r < 2 ? 0 : 11 - r
        }
        return dv(12) == d[12] && dv(13) == d[13]
    }

    /// "12.345.678/0001-95"
    static func formatCNPJ(_ raw: String) -> String {
        let d = digits(raw).map(String.init).joined()
        guard d.count == 14 else { return raw }
        let a = Array(d)
        return "\(String(a[0..<2])).\(String(a[2..<5])).\(String(a[5..<8]))/\(String(a[8..<12]))-\(String(a[12..<14]))"
    }
}

enum NFCeEnvironment: String, Sendable, Equatable { case production, homologation }

/// Chave de acesso decomposta.
struct NFCeAccessKey: Sendable, Equatable {
    let value: String            // 44 dígitos
    let ufCode: Int
    let emissionMonth: YearMonth
    let cnpj: String             // 14 dígitos
    let model: Int               // 65 = NFC-e, 55 = NF-e
    let series: Int
    let number: Int

    var uf: String { NFCeParser.ufAcronym(code: ufCode) ?? "??" }
    var isNFCe: Bool { model == 65 }
    var cnpjIsValid: Bool { BrazilianDocument.isValidCNPJ(cnpj) }
    var formattedCNPJ: String { BrazilianDocument.formatCNPJ(cnpj) }
    /// Chave agrupada de 4 em 4 dígitos, como impressa no cupom.
    var grouped: String {
        stride(from: 0, to: value.count, by: 4).map { i in
            let a = Array(value)
            return String(a[i..<min(i + 4, a.count)])
        }.joined(separator: " ")
    }
}

/// O que dá para saber só pelo QR Code (sem internet).
struct NFCeQRCode: Sendable, Equatable {
    var key: NFCeAccessKey
    var qrVersion: Int?
    var environment: NFCeEnvironment?
    /// Dia da emissão (só no QR Code de contingência offline, onde o valor também vem no QR).
    var emissionDay: Int?
    /// Valor total (vNF). Só existe no QR Code de contingência offline; no QR online é nil e exige consulta à SEFAZ.
    var totalAmount: Decimal?
    var host: String?

    /// Data de emissão quando conhecida (mês da chave + dia do QR de contingência).
    var emissionDate: Date? {
        guard let day = emissionDay, (1...key.emissionMonth.daysInMonth).contains(day) else { return nil }
        return key.emissionMonth.date(day: day)
    }

    /// Identificador para evitar lançar a mesma nota duas vezes (`Transaction.externalId`).
    var externalId: String { "nfce:" + key.value }
}

enum NFCeParseError: Error, Equatable, Sendable {
    case notAnNFCe          // não há chave de acesso no texto
    case invalidLength      // chave sem 44 dígitos
    case invalidCheckDigit  // DV da chave não confere
    case invalidFields      // UF/mês/modelo incoerentes

    var message: String {
        switch self {
        case .notAnNFCe: return "Este QR Code não parece ser de uma nota fiscal (NFC-e)."
        case .invalidLength: return "A chave de acesso não tem 44 dígitos."
        case .invalidCheckDigit: return "O dígito verificador da chave não confere. O QR Code pode estar danificado."
        case .invalidFields: return "A chave de acesso tem campos inválidos (UF, mês ou modelo)."
        }
    }
}

enum NFCeParser {
    static let ufCodes: [Int: String] = [
        11: "RO", 12: "AC", 13: "AM", 14: "RR", 15: "PA", 16: "AP", 17: "TO", 21: "MA", 22: "PI", 23: "CE", 24: "RN",
        25: "PB", 26: "PE", 27: "AL", 28: "SE", 29: "BA", 31: "MG", 32: "ES", 33: "RJ", 35: "SP", 41: "PR", 42: "SC",
        43: "RS", 50: "MS", 51: "MT", 52: "GO", 53: "DF",
    ]

    static func ufAcronym(code: Int) -> String? { ufCodes[code] }

    /// Valida e decompõe uma chave de 44 dígitos (aceita espaços e pontuação).
    static func parseKey(_ raw: String) throws -> NFCeAccessKey {
        let d = BrazilianDocument.digits(raw)
        guard d.count == 44 else { throw NFCeParseError.invalidLength }
        guard BrazilianDocument.mod11(Array(d.prefix(43))) == d[43] else { throw NFCeParseError.invalidCheckDigit }
        func num(_ r: Range<Int>) -> Int { d[r].reduce(0) { $0 * 10 + $1 } }
        let uf = num(0..<2), yy = num(2..<4), mm = num(4..<6), model = num(20..<22)
        guard ufCodes[uf] != nil, (1...12).contains(mm), model == 55 || model == 65 else { throw NFCeParseError.invalidFields }
        let cnpj = d[6..<20].map(String.init).joined()
        return NFCeAccessKey(value: d.map(String.init).joined(), ufCode: uf, emissionMonth: YearMonth(year: 2000 + yy, month: mm),
                             cnpj: cnpj, model: model, series: num(22..<25), number: num(25..<34))
    }

    /// Lê o texto de um QR Code: URL com `p=` (`chave|versão|tpAmb|...`), `chNFe=` (layout antigo) ou a chave pura.
    ///
    /// Layout do parâmetro `p` na versão 2 (conforme a nota técnica da NFC-e; confira a versão vigente da SEFAZ do seu estado):
    /// - online: `chave|2|tpAmb|idCSC|hash`
    /// - contingência offline: `chave|2|tpAmb|dia|vNF|digestValue|idCSC|hash` (é o único caso em que o valor vem no QR)
    static func parse(_ text: String) throws -> NFCeQRCode {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NFCeParseError.notAnNFCe }

        var host: String?
        var payload: String?
        if let comps = URLComponents(string: trimmed), comps.host != nil {
            host = comps.host
            let items = comps.queryItems ?? []
            payload = items.first { $0.name.lowercased() == "p" }?.value
                ?? items.first { $0.name.lowercased() == "chnfe" }?.value
        } else if trimmed.lowercased().hasPrefix("p=") {
            payload = String(trimmed.dropFirst(2))   // "p=..." solto, sem URL completa
        }
        if payload == nil {
            // Chave pura (somente dígitos e separadores).
            guard trimmed.allSatisfy({ $0.isNumber || $0 == " " || $0 == "." || $0 == "-" }), !BrazilianDocument.digits(trimmed).isEmpty else {
                throw NFCeParseError.notAnNFCe
            }
            payload = trimmed
        }

        let fields = payload!.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        let key = try parseKey(fields[0])
        var result = NFCeQRCode(key: key, qrVersion: nil, environment: nil, emissionDay: nil, totalAmount: nil, host: host)
        if fields.count > 1 { result.qrVersion = Int(fields[1]) }
        if fields.count > 2 { result.environment = fields[2] == "1" ? .production : (fields[2] == "2" ? .homologation : nil) }
        if result.qrVersion == 2, fields.count >= 8 {
            // contingência offline: dia | vNF | digestValue | idCSC | hash
            result.emissionDay = Int(fields[3])
            if let v = Decimal(string: fields[4], locale: nil), v > 0, fields[4].allSatisfy({ $0.isNumber || $0 == "." }) {
                result.totalAmount = v.rounded(scale: 2)
            }
        }
        return result
    }
}

// MARK: - Consulta online (NÃO implementada)

/// Dados que só a consulta à SEFAZ entrega.
struct NFCeReceipt: Sendable, Equatable {
    struct Item: Sendable, Equatable {
        var description: String
        var quantity: Decimal
        var total: Decimal
    }
    var merchantName: String
    var merchantCNPJ: String
    var issuedAt: Date
    var total: Decimal
    var items: [Item]
}

enum NFCeLookupError: Error, Equatable, Sendable {
    case notConfigured          // não há implementação neste build
    case unavailable            // portal fora do ar / captcha / termos
    case notFound
}

/// Contrato para buscar os dados completos da nota. **Não há implementação concreta de propósito:** cada SEFAZ estadual
/// tem portal, formato e termos de uso próprios (muitos exigem captcha ou proíbem raspagem automatizada), então a consulta
/// precisa de um serviço/contrato próprio (por exemplo um backend ou um provedor de dados fiscais). Ver `docs/ocr-nfce.md`.
/// O app funciona sem isso: o QR Code já entrega UF, CNPJ, chave e, em contingência, o valor.
protocol NFCeLookupService: Sendable {
    func lookup(_ qr: NFCeQRCode) async throws -> NFCeReceipt
}
