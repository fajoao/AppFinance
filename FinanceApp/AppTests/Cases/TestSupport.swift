import Foundation
#if canImport(FinanceApp)
@testable import FinanceApp
#endif

// Mini framework de testes (mesmo modelo do CoreTests), compartilhado entre o runner (swiftc) e a ponte XCTest.

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

    func throwsError<E: Error & Equatable, R>(_ expected: E, _ body: () throws -> R, file: String = #fileID, line: Int = #line) {
        assertions += 1
        do { _ = try body(); failures.append("\(file):\(line) esperava erro \(expected)") }
        catch let e as E { if e != expected { failures.append("\(file):\(line) erro \(e) != \(expected)") } }
        catch { failures.append("\(file):\(line) erro inesperado \(error)") }
    }
}

struct TestCase {
    let name: String
    let body: (TestContext) throws -> Void
    init(_ name: String, _ body: @escaping (TestContext) throws -> Void) { self.name = name; self.body = body }
}

/// Executa o corpo no MainActor (AppStore é @MainActor). O runner roda na thread principal.
func onMain<R: Sendable>(_ body: @MainActor () throws -> R) rethrows -> R {
    try MainActor.assumeIsolated(body)
}

// Fixtures
func D(_ y: Int, _ m: Int, _ d: Int) -> Date { FinanceCalendar.date(y, m, d) }
func ymd(_ date: Date) -> String { let c = FinanceCalendar.components(date); return String(format: "%04d-%02d-%02d", c.year, c.month, c.day) }

/// "Hoje" fixo dos testes: 19/10/2026.
let testToday = D(2026, 10, 19)

@MainActor
func makeStore(seed: Bool = false, onboarded: Bool = true) -> AppStore {
    let store = AppStore(repository: InMemoryStore(), preferences: InMemoryPreferences(),
                         reminders: NoopReminderScheduler(), clock: { testToday })
    if seed { try! store.loadDemoData() }
    else if onboarded {
        var d = OnboardingDraft(); d.accountName = "Nubank"; d.balanceText = "1.000,00"
        try! store.completeOnboarding(d)
    }
    return store
}
