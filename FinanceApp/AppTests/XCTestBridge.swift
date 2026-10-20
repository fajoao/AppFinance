// Ponte para o Xcode: cada suíte vira um XCTestCase que executa os mesmos TestCase do runner swiftc.
// Este arquivo NÃO entra no runner (`scripts/test-app.sh`), pois XCTest não existe nas Command Line Tools.
#if canImport(XCTest)
import XCTest
#if canImport(FinanceApp)
@testable import FinanceApp
#endif

@MainActor
final class AppLogicTests: XCTestCase {
    func testAllSuites() throws {
        for (suite, cases) in allAppSuites() {
            for c in cases {
                let ctx = TestContext()
                do { try c.body(ctx) } catch { ctx.fail("erro inesperado: \(error)") }
                XCTAssertTrue(ctx.failures.isEmpty, "[\(suite)] \(c.name): \(ctx.failures.joined(separator: " | "))")
            }
        }
    }
}
#endif
