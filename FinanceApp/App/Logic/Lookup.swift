import Foundation

/// Índices por id para a UI resolver nomes sem varrer arrays a cada linha.
struct FinanceLookup: Sendable, Equatable {
    var accounts: [UUID: Account] = [:]
    var categories: [UUID: Category] = [:]
    var tags: [UUID: Tag] = [:]
    var cards: [UUID: CreditCard] = [:]
    var members: [UUID: FamilyMember] = [:]

    init() {}

    init(accounts: [Account], categories: [Category], tags: [Tag], cards: [CreditCard], members: [FamilyMember] = []) {
        self.members = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0) })
        self.accounts = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        self.categories = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        self.tags = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
        self.cards = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
    }

    func categoryName(_ id: UUID?) -> String { id.flatMap { categories[$0]?.name } ?? "Sem categoria" }

    func memberName(_ id: UUID?) -> String { id.flatMap { members[$0]?.name } ?? "Sem membro" }

    var reportNames: ReportNames {
        ReportNames(categories: categories.mapValues(\.name), members: members.mapValues(\.name), accounts: accounts.mapValues(\.name))
    }

    /// Conta ou cartão de origem do lançamento.
    func sourceName(of tx: Transaction) -> String {
        if let c = tx.creditCardId, let card = cards[c] { return card.name }
        if let a = tx.accountId, let acc = accounts[a] { return acc.name }
        return "—"
    }

    /// "Nubank → Poupança" para transferências; senão o nome de origem.
    func accountLabel(of tx: Transaction) -> String {
        if tx.type == .transfer, !tx.isInvoicePayment, let d = tx.destinationAccountId, let dest = accounts[d] {
            return "\(sourceName(of: tx)) → \(dest.name)"
        }
        return sourceName(of: tx)
    }

    func tagNames(of tx: Transaction) -> [String] { tx.tagIds.compactMap { tags[$0]?.name } }
}

/// Estilo visual de categoria: o token de cor e o símbolo SF ficam em `Category.colorHex` / `Category.icon`
/// (convenção do App: `colorHex` guarda o NOME do token, ex. "catMoradia").
enum CategoryStyle {
    static let fallbackToken = "catOutros"
    static let fallbackIcon = "ellipsis.circle"

    static func token(for category: Category?, in lookup: FinanceLookup) -> String {
        guard let c = category else { return fallbackToken }
        if let t = c.colorHex, t.hasPrefix("cat") || t == "income" { return t }
        if let p = c.parentId, let parent = lookup.categories[p] { return token(for: parent, in: lookup) }
        return fallbackToken
    }

    static func icon(for category: Category?) -> String { category?.icon ?? fallbackIcon }
}

/// Categorias padrão criadas no onboarding, com palavras-chave para a sugestão automática.
enum DefaultCategories {
    struct Spec { var name: String; var kind: CategoryKind; var icon: String; var token: String; var keywords: [String] }

    static let specs: [Spec] = [
        Spec(name: "Moradia", kind: .expense, icon: "house", token: "catMoradia",
             keywords: ["aluguel", "energia", "enel", "agua", "condominio", "internet", "iptu", "conta de luz"]),
        Spec(name: "Mercado", kind: .expense, icon: "cart", token: "catMercado",
             keywords: ["mercado", "carrefour", "assai", "padaria", "pao de acucar", "feira", "acougue", "hortifruti", "ifood", "atacad"]),
        Spec(name: "Transporte", kind: .expense, icon: "car", token: "catTransporte",
             keywords: ["uber", "99 pop", "99pop", "posto", "gasolina", "metro", "onibus", "estacionamento", "pedagio"]),
        Spec(name: "Lazer", kind: .expense, icon: "ticket", token: "catLazer",
             keywords: ["cinema", "netflix", "spotify", "show", "restaurante", "viagem", "hotel", "bar do"]),
        Spec(name: "Saúde", kind: .expense, icon: "heart", token: "catSaude",
             keywords: ["farmacia", "drogasil", "droga", "medic", "consulta", "dentista", "exame", "academia"]),
        Spec(name: "Educação", kind: .expense, icon: "book", token: "catEducacao",
             keywords: ["escola", "curso", "livro", "faculdade", "mensalidade", "ingles"]),
        Spec(name: "Outros", kind: .expense, icon: "ellipsis.circle", token: "catOutros", keywords: []),
        Spec(name: "Salário", kind: .income, icon: "briefcase", token: "income", keywords: ["salario", "holerite"]),
        Spec(name: "Freelance", kind: .income, icon: "laptopcomputer", token: "income", keywords: ["freela", "cliente", "projeto"]),
        Spec(name: "Rendimentos", kind: .income, icon: "chart.line.uptrend.xyaxis", token: "income", keywords: ["rendimento", "juros", "dividendo"]),
        Spec(name: "Outros", kind: .income, icon: "ellipsis.circle", token: "income", keywords: []),
    ]

    static func make() -> [Category] {
        specs.map { spec in
            // Saúde e Educação já nascem marcadas como dedutíveis no IR (o usuário pode desmarcar).
            let tax: TaxDeductionKind? = spec.kind == .expense ? (spec.name == "Saúde" ? .health : (spec.name == "Educação" ? .education : nil)) : nil
            return Category(name: spec.name, kind: spec.kind, icon: spec.icon, colorHex: spec.token, taxKind: tax)
        }
    }

    /// Palavras-chave por categoria existente (casando pelo nome e tipo).
    static func keywords(for categories: [Category], kind: CategoryKind) -> [UUID: [String]] {
        var result: [UUID: [String]] = [:]
        for c in categories where c.kind == kind && c.parentId == nil {
            if let spec = specs.first(where: { $0.name == c.name && $0.kind == kind }), !spec.keywords.isEmpty {
                result[c.id] = spec.keywords
            }
        }
        return result
    }
}
