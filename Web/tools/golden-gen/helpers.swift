import Foundation

// Helpers do gerador de vetores dourados. Cada caso: {"name","kind","input","expected"}.
// Entradas de entidades usam o JSON Codable REAL do Core (JSONFileStore.encoder); saídas usam strings exatas
// para Decimal e "yyyy-MM-dd" para dias civis.

typealias J = [String: Any]

func uid(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }
func d(_ y: Int, _ m: Int, _ day: Int) -> Date { FinanceCalendar.date(y, m, day) }
func S(_ x: Decimal) -> String { "\(x)" }
func S(_ x: Decimal?) -> Any { x.map { "\($0)" } ?? NSNull() }
func iso(_ date: Date) -> String {
    let c = FinanceCalendar.components(date)
    return String(format: "%04d-%02d-%02d", c.year, c.month, c.day)
}
func isoN(_ date: Date?) -> Any { date.map { iso($0) } ?? NSNull() }
func YMj(_ m: YearMonth) -> J { ["year": m.year, "month": m.month] }
func U(_ id: UUID?) -> Any { id.map { $0.uuidString } ?? NSNull() }

let stampDate = Date(timeIntervalSinceReferenceDate: 800_000_000)

/// Entidade -> JSON de rede (mesmo encoder do JSONFileStore).
func ent<T: Encodable>(_ x: T) -> Any {
    let data = try! JSONFileStore.encoder.encode(x)
    return try! JSONSerialization.jsonObject(with: data)
}
func ents<T: Encodable>(_ xs: [T]) -> Any { xs.map { ent($0) } }

func acct(_ n: Int, _ name: String, _ type: AccountType = .checking, initial: String = "0", archived: Bool = false, vis: Visibility = .shared, owner: Int? = nil) -> Account {
    var a = Account(name: name, type: type, initialBalance: dec(initial))
    a.id = uid(n); a.isArchived = archived; a.visibility = vis; a.ownerId = owner.map(uid)
    a.createdAt = stampDate; a.updatedAt = stampDate
    return a
}
func cat(_ n: Int, _ name: String, _ kind: CategoryKind = .expense, parent: Int? = nil, tax: TaxDeductionKind? = nil, vis: Visibility = .shared, owner: Int? = nil) -> Category {
    var c = Category(name: name, kind: kind)
    c.id = uid(n); c.parentId = parent.map(uid); c.taxKind = tax; c.visibility = vis; c.ownerId = owner.map(uid)
    c.createdAt = stampDate; c.updatedAt = stampDate
    return c
}
func card(_ n: Int, _ name: String, limit: String, closing: Int, due: Int) -> CreditCard {
    var c = CreditCard(name: name, limit: dec(limit), closingDay: closing, dueDay: due)
    c.id = uid(n); c.createdAt = stampDate; c.updatedAt = stampDate
    return c
}
func tx(_ n: Int, _ type: TransactionType, _ amount: String, _ date: Date, _ title: String, status: TransactionStatus = .paid,
        account: Int? = nil, dest: Int? = nil, cat: Int? = nil, card: Int? = nil, invoice: UUID? = nil, member: Int? = nil,
        ext: String? = nil, recurrence: RecurrenceRule? = nil, parent: UUID? = nil) -> Transaction {
    var t = Transaction(type: type, amount: dec(amount), date: date, title: title, status: status)
    t.id = uid(n); t.accountId = account.map(uid); t.destinationAccountId = dest.map(uid); t.categoryId = cat.map(uid)
    t.creditCardId = card.map(uid); t.invoiceId = invoice; t.memberId = member.map(uid); t.externalId = ext
    t.recurrence = recurrence; t.recurrenceParentId = parent
    t.createdAt = Date(timeIntervalSinceReferenceDate: 800_000_000 + Double(n)); t.updatedAt = t.createdAt
    return t
}

struct Case {
    var name: String
    var kind: String
    var input: J
    var expected: Any
    var json: J { ["name": name, "kind": kind, "input": input, "expected": expected] }
}

var allCases: [Case] = []
func add(_ kind: String, _ name: String, input: J, expected: Any) {
    allCases.append(Case(name: name, kind: kind, input: input, expected: expected))
}

func writeCases(to dir: String) throws {
    var grouped: [String: [J]] = [:]
    for c in allCases { grouped[String(c.kind.split(separator: ".")[0]), default: []].append(c.json) }
    for (suite, cases) in grouped {
        let obj: J = ["suite": suite, "cases": cases]
        let data = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(suite).json"))
    }
    print("Casos gerados: \(allCases.count) em \(grouped.count) arquivos")
    for (s, c) in grouped.sorted(by: { $0.key < $1.key }) { print("  \(s): \(c.count)") }
}
