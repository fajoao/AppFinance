import Foundation

final class TestContext: @unchecked Sendable {
    var failures: [String] = []
    var assertions = 0

    func fail(_ msg: String) { failures.append(msg) }

    func check(_ cond: Bool, _ msg: @autoclosure () -> String = "condição falsa", file: String = #fileID, line: Int = #line) {
        assertions += 1
        if !cond { failures.append("\(file):\(line) \(msg())") }
    }

    func equal<T: Equatable>(_ a: T, _ b: T, _ msg: String = "", file: String = #fileID, line: Int = #line) {
        assertions += 1
        if a != b { failures.append("\(file):\(line) esperado \(b), obtido \(a) \(msg)") }
    }

    func isNil<T>(_ v: T?, _ msg: String = "", file: String = #fileID, line: Int = #line) {
        assertions += 1
        if v != nil { failures.append("\(file):\(line) esperado nil, obtido \(v!) \(msg)") }
    }

    func throwsError<R>(_ expected: FinanceError, _ body: () throws -> R, file: String = #fileID, line: Int = #line) {
        assertions += 1
        do { _ = try body(); failures.append("\(file):\(line) esperava erro \(expected)") }
        catch let e as FinanceError { if e != expected { failures.append("\(file):\(line) erro \(e) != \(expected)") } }
        catch { failures.append("\(file):\(line) erro inesperado \(error)") }
    }
}

struct TestCase {
    let name: String
    let body: @Sendable (TestContext) throws -> Void
    init(_ name: String, _ body: @escaping @Sendable (TestContext) throws -> Void) { self.name = name; self.body = body }
}

// Atalhos de fixtures
func D(_ y: Int, _ m: Int, _ d: Int) -> Date { FinanceCalendar.date(y, m, d) }
func ymd(_ date: Date) -> String { let c = FinanceCalendar.components(date); return String(format: "%04d-%02d-%02d", c.year, c.month, c.day) }
func ymds(_ dates: [Date]) -> [String] { dates.map(ymd) }
func tx(_ type: TransactionType = .expense, _ amount: String, _ date: Date, _ title: String = "x", status: TransactionStatus = .paid,
        account: UUID? = nil, category: UUID? = nil) -> Transaction {
    Transaction(type: type, amount: dec(amount), date: date, title: title, status: status, accountId: account, categoryId: category)
}
