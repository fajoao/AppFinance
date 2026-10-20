import Foundation

func foundationTests() -> [TestCase] {
    let nb = "\u{00A0}"
    return [
        TestCase("dec() mantém centavos exatos") { t in
            t.equal(dec("100.01") * 10, dec("1000.10"))
            t.equal(dec("0.1") + dec("0.2"), dec("0.3"))
        },
        TestCase("formatação BRL básica") { t in
            t.equal(Money.format(dec("1234.56")), "R$\(nb)1.234,56")
            t.equal(Money.format(0), "R$\(nb)0,00")
            t.equal(Money.format(dec("0.5")), "R$\(nb)0,50")
            t.equal(Money.format(1_000_000), "R$\(nb)1.000.000,00")
            t.equal(Money.format(999), "R$\(nb)999,00")
            t.equal(Money.format(1000), "R$\(nb)1.000,00")
        },
        TestCase("formatação de negativos e arredondamento") { t in
            t.equal(Money.format(dec("-1234567.891")), "-R$\(nb)1.234.567,89")
            t.equal(Money.format(dec("0.005")), "R$\(nb)0,01")
            t.equal(Money.format(dec("-0.001")), "R$\(nb)0,00")
            t.equal(Money.format(dec("-0.01")), "-R$\(nb)0,01")
            t.equal(Money.format(dec("1234.5"), withSymbol: false), "1.234,50")
        },
        TestCase("arredondamento meio para cima") { t in
            t.equal(dec("2.345").rounded(), dec("2.35"))
            t.equal(dec("-2.345").rounded(), dec("-2.35"))
            t.equal(dec("2.344").rounded(), dec("2.34"))
            t.equal(dec("-2.999").truncated(), dec("-2.99"))
            t.equal(dec("2.999").truncated(), dec("2.99"))
        },
        TestCase("parse de valores pt-BR e en") { t in
            t.equal(Money.parse("R$ 1.234,56"), dec("1234.56"))
            t.equal(Money.parse("R$\(nb)1.234,56"), dec("1234.56"))
            t.equal(Money.parse("-1.234,56"), dec("-1234.56"))
            t.equal(Money.parse("1234.56"), dec("1234.56"))
            t.equal(Money.parse("1,234.56"), dec("1234.56"))
            t.equal(Money.parse("12,5"), dec("12.5"))
            t.equal(Money.parse("1.234"), dec("1234"))
            t.equal(Money.parse("1.234.567"), dec("1234567"))
            t.equal(Money.parse("(123,45)"), dec("-123.45"))
            t.equal(Money.parse("123,45-"), dec("-123.45"))
            t.equal(Money.parse("+10"), dec("10"))
            t.equal(Money.parse("100"), dec("100"))
            t.equal(Money.parse("0,01"), dec("0.01"))
        },
        TestCase("parse com estilo explícito") { t in
            t.equal(Money.parse("1.234", style: .dot), dec("1.234"))
            t.equal(Money.parse("1.234", style: .comma), dec("1234"))
            t.equal(Money.parse("-12.50", style: .dot), dec("-12.50"))
        },
        TestCase("parse inválido retorna nil") { t in
            t.isNil(Money.parse(""))
            t.isNil(Money.parse("abc"))
            t.isNil(Money.parse("12a"))
            t.isNil(Money.parse("1,2,3"))
            t.isNil(Money.parse("-"))
            t.isNil(Money.parse("12,"))
        },
        TestCase("YearMonth: virada de ano e normalização") { t in
            t.equal(YearMonth(year: 2024, month: 12).next, YearMonth(year: 2025, month: 1))
            t.equal(YearMonth(year: 2025, month: 1).previous, YearMonth(year: 2024, month: 12))
            t.equal(YearMonth(year: 2025, month: 0), YearMonth(year: 2024, month: 12))
            t.equal(YearMonth(year: 2025, month: 13), YearMonth(year: 2026, month: 1))
            t.equal(YearMonth(year: 2025, month: -11), YearMonth(year: 2024, month: 1))
            t.equal(YearMonth(year: 2024, month: 11).adding(months: 14), YearMonth(year: 2026, month: 1))
            t.equal(YearMonth(year: 2024, month: 11).months(to: YearMonth(year: 2026, month: 1)), 14)
            t.check(YearMonth(year: 2024, month: 12) < YearMonth(year: 2025, month: 1))
            t.equal(YearMonth(year: 2025, month: 3).label, "03/2025")
        },
        TestCase("YearMonth: dias do mês e bissexto") { t in
            t.equal(YearMonth(year: 2024, month: 2).daysInMonth, 29)
            t.equal(YearMonth(year: 2023, month: 2).daysInMonth, 28)
            t.equal(YearMonth(year: 2100, month: 2).daysInMonth, 28)
            t.equal(YearMonth(year: 2000, month: 2).daysInMonth, 29)
            t.equal(YearMonth(year: 2025, month: 4).daysInMonth, 30)
            t.equal(YearMonth(year: 2025, month: 12).daysInMonth, 31)
            t.equal(ymd(YearMonth(year: 2025, month: 2).date(day: 31)), "2025-02-28")
            t.equal(ymd(YearMonth(year: 2024, month: 2).lastDay), "2024-02-29")
            t.equal(ymd(YearMonth(year: 2024, month: 2).date(day: 0)), "2024-02-01")
            t.check(YearMonth(year: 2024, month: 2).contains(D(2024, 2, 29)))
            t.check(!YearMonth(year: 2024, month: 2).contains(D(2024, 3, 1)))
        },
        TestCase("calendário: addMonths/addYears/addDays com limites") { t in
            t.equal(ymd(FinanceCalendar.addMonths(D(2024, 1, 31), 1)), "2024-02-29")
            t.equal(ymd(FinanceCalendar.addMonths(D(2023, 1, 31), 1)), "2023-02-28")
            t.equal(ymd(FinanceCalendar.addMonths(D(2024, 12, 15), 1)), "2025-01-15")
            t.equal(ymd(FinanceCalendar.addYears(D(2024, 2, 29), 1)), "2025-02-28")
            t.equal(ymd(FinanceCalendar.addYears(D(2024, 2, 29), 4)), "2028-02-29")
            t.equal(ymd(FinanceCalendar.addDays(D(2024, 12, 31), 1)), "2025-01-01")
            t.equal(FinanceCalendar.daysBetween(D(2024, 2, 28), D(2024, 3, 1)), 2)
            t.equal(FinanceCalendar.daysBetween(D(2023, 2, 28), D(2023, 3, 1)), 1)
            t.check(FinanceCalendar.isLeapYear(2024) && !FinanceCalendar.isLeapYear(1900) && FinanceCalendar.isLeapYear(2000))
        },
        TestCase("normalize converte para dia civil local") { t in
            // 23:30 em UTC-3 em 10/jan = 02:30Z de 11/jan; o dia civil local é 10
            let instant = Date(timeIntervalSince1970: 1_736_562_600) // 2025-01-11T02:30:00Z
            let brt = TimeZone(secondsFromGMT: -3 * 3600)!
            t.equal(ymd(FinanceCalendar.normalize(instant, in: brt)), "2025-01-10")
            t.equal(ymd(FinanceCalendar.normalize(instant, in: TimeZone(identifier: "UTC")!)), "2025-01-11")
        },
        TestCase("split: 100,01 em 10x") { t in
            let p = Money.split(dec("100.01"), into: 10)
            t.equal(p.count, 10)
            t.equal(Array(p.prefix(9)), [Decimal](repeating: dec("10.00"), count: 9))
            t.equal(p[9], dec("10.01"))
            t.equal(p.reduce(0, +), dec("100.01"))
        },
        TestCase("split: resto vai para a última, invariantes de soma") { t in
            t.equal(Money.split(100, into: 3), [dec("33.33"), dec("33.33"), dec("33.34")])
            t.equal(Money.split(dec("0.01"), into: 3), [0, 0, dec("0.01")])
            t.equal(Money.split(dec("0.10"), into: 3), [dec("0.03"), dec("0.03"), dec("0.04")])
            t.equal(Money.split(100, into: 1), [100])
            t.equal(Money.split(100, into: 0), [])
            for total in ["0.01", "1", "9.99", "100.01", "1234.56", "99999.99", "-7.77", "-100", "3333.33"] {
                for n in 1...24 {
                    let parts = Money.split(dec(total), into: n)
                    t.equal(parts.reduce(0, +), dec(total), "total \(total) em \(n)")
                    t.check(parts.allSatisfy { $0.rounded() == $0 }, "centavos exatos \(total)/\(n)")
                }
            }
        },
        TestCase("split: negativos e total com >2 casas") { t in
            t.equal(Money.split(-100, into: 3), [dec("-33.33"), dec("-33.33"), dec("-33.34")])
            t.equal(Money.split(dec("-100.01"), into: 10).last!, dec("-10.01"))
            t.equal(Money.split(dec("10.005"), into: 2).reduce(0, +), dec("10.01"))
            t.equal(Money.split(0, into: 4), [0, 0, 0, 0])
        },
        TestCase("allocate proporcional") { t in
            t.equal(Money.allocate(100, weights: [1, 1, 1]), [dec("33.33"), dec("33.33"), dec("33.34")])
            let p = Money.allocate(dec("100.01"), weights: [50, 30, 20])
            t.equal(p.reduce(0, +), dec("100.01"))
            t.equal(Money.allocate(100, weights: [0, 0]), [50, 50])
            t.equal(Money.allocate(100, weights: []), [])
            t.equal(Money.allocate(90, weights: [2, 1]), [60, 30])
        },
    ]
}
