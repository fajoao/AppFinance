import Foundation

func foundationCases() {
    // Money.format / plain
    let formatInputs = ["0", "5", "1.5", "100.01", "1234.56", "-45.9", "1234567.891", "-0.004", "0.005", "-0.005", "999999.995", "12345678901234.56"]
    for v in formatInputs {
        add("money.format", "format \(v)", input: ["value": v], expected: Money.format(dec(v)))
        add("money.plain", "plain \(v)", input: ["value": v], expected: Money.plain(dec(v)))
    }
    // Money.parse
    let parseInputs = ["R$ 1.234,56", "R$\u{00A0}1.234,56", "-1234.56", "(123,45)", "1.234", "12,5", "1.234.567", "1,234.56", "1.234,5", "0,99", "abc", "", "  ", "-", "12,", "1,2,3", "+50", "100-", "1.5", "1.50", "12.345", "R$ -10,00", "--5", "1e5", "٣"]
    for r in parseInputs {
        add("money.parse", "parse '\(r)'", input: ["raw": r, "style": "auto"], expected: S(Money.parse(r)))
    }
    for (r, st, style) in [("1.234", "comma", DecimalStyle.comma), ("1.234", "dot", DecimalStyle.dot), ("1,234", "dot", DecimalStyle.dot), ("12,5", "comma", DecimalStyle.comma)] {
        add("money.parse", "parse styled \(r) \(st)", input: ["raw": r, "style": st], expected: S(Money.parse(r, style: style)))
    }
    // split / allocate
    for (t, n) in [("100.01", 10), ("100.01", 3), ("0.01", 3), ("1000", 3), ("-100.01", 3), ("10", 1), ("99.99", 7), ("0", 4), ("100.005", 3), ("1234.57", 12)] {
        add("money.split", "split \(t)/\(n)", input: ["total": t, "count": n], expected: Money.split(dec(t), into: n).map(S))
    }
    for (t, w) in [("100", ["1", "1", "1"]), ("100.01", ["50", "30", "20"]), ("0.05", ["1", "1"]), ("100", ["0", "0"]), ("333.33", ["33.33", "33.33", "33.34"]), ("-90", ["1", "2"])] {
        add("money.allocate", "allocate \(t) \(w)", input: ["total": t, "weights": w], expected: Money.allocate(dec(t), weights: w.map(dec)).map(S))
    }
    // rounding
    for (v, scale, mode, m) in [("2.345", 2, Decimal.RoundingMode.plain, "plain"), ("-2.345", 2, .plain, "plain"), ("2.345", 2, .down, "down"), ("2.341", 2, .up, "up"), ("0.5", 0, .plain, "plain"), ("1.00005", 4, .plain, "plain"), ("-0.5", 0, .plain, "plain")] {
        add("money.round", "round \(v) \(scale) \(m)", input: ["value": v, "scale": scale, "mode": m], expected: S(dec(v).rounded(scale: scale, mode: mode)))
    }
    // datas
    let dates = ["31/01/2026", "31/02/2026", "29/02/2024", "29/02/2025", "1/1/26", "2026-10-05", "2026/10/05", "05-10-2026", "05.10.2026", "5/10/99", "13/13/2026", "00/10/2026", "abc", "2026-1-5", "10/2026", "32/01/2026", "01/01/12345"]
    for r in dates { add("date.parse", "parse date \(r)", input: ["raw": r], expected: isoN(DateParsing.parse(r))) }
    for (dt, n) in [(d(2026, 1, 31), 1), (d(2026, 1, 31), 13), (d(2024, 1, 31), 1), (d(2026, 3, 31), -1), (d(2026, 12, 31), 2), (d(2026, 10, 15), -11)] {
        add("calendar.addMonths", "addMonths \(iso(dt)) \(n)", input: ["date": iso(dt), "n": n], expected: iso(FinanceCalendar.addMonths(dt, n)))
    }
    for (dt, n) in [(d(2024, 2, 29), 1), (d(2024, 2, 29), 4), (d(2026, 6, 15), -2)] {
        add("calendar.addYears", "addYears \(iso(dt)) \(n)", input: ["date": iso(dt), "n": n], expected: iso(FinanceCalendar.addYears(dt, n)))
    }
    for (a, b) in [(d(2026, 1, 1), d(2026, 12, 31)), (d(2026, 3, 1), d(2026, 2, 1)), (d(2024, 2, 28), d(2024, 3, 1))] {
        add("calendar.daysBetween", "daysBetween \(iso(a)) \(iso(b))", input: ["a": iso(a), "b": iso(b)], expected: FinanceCalendar.daysBetween(a, b))
    }
}
