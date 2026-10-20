import Foundation

// Runner swiftc: executa todas as suítes; sai com código 1 se houver falhas.
let suites: [(String, [TestCase])] = allAppSuites()

var passed = 0, failed = 0, assertions = 0
for (suite, tests) in suites {
    print("== \(suite)")
    for test in tests {
        let t = TestContext()
        do { try test.body(t) } catch { t.fail("erro inesperado: \(error)") }
        assertions += t.assertions
        if t.failures.isEmpty { passed += 1; print("  ok   \(test.name)") }
        else {
            failed += 1
            print("  FAIL \(test.name)")
            for f in t.failures { print("       - \(f)") }
        }
    }
}
print("\nResultado: \(passed) passaram, \(failed) falharam (\(assertions) asserções)")
exit(failed == 0 ? 0 : 1)
