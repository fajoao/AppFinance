import Foundation
#if canImport(FinanceApp)
@testable import FinanceApp
#endif

func periodTests() -> [TestCase] {
    let oct26 = YearMonth(year: 2026, month: 10)
    return [
        TestCase("PeriodSelection: títulos e rótulo de acessibilidade em pt-BR") { t in
            t.equal(PeriodSelection.title(oct26), "Outubro de 2026")
            t.equal(PeriodSelection.accessibilityLabel(oct26), "Outubro de 2026, selecionar mês")
            t.equal(PeriodSelection.gridLabel(month: 3), "Mar")
            t.equal(PeriodSelection.gridLabel(month: 12), "Dez")
            t.equal(PeriodSelection.monthAccessibilityLabel(month: 5, year: 2027), "Maio de 2027")
        },
        TestCase("PeriodSelection: navegação ±1 mês cruza o ano") { t in
            t.equal(PeriodSelection.moved(YearMonth(year: 2026, month: 1), by: -1), YearMonth(year: 2025, month: 12))
            t.equal(PeriodSelection.moved(YearMonth(year: 2026, month: 12), by: 1), YearMonth(year: 2027, month: 1))
            t.equal(PeriodSelection.moved(oct26, by: 12), YearMonth(year: 2027, month: 10))
            t.equal(PeriodSelection.moved(oct26, by: -12), YearMonth(year: 2025, month: 10))
        },
        TestCase("PeriodSelection: limites 01/2000 a 12/2100") { t in
            t.equal(PeriodSelection.minimum, YearMonth(year: 2000, month: 1))
            t.equal(PeriodSelection.maximum, YearMonth(year: 2100, month: 12))
            t.check(!PeriodSelection.canMove(PeriodSelection.minimum, by: -1))
            t.check(PeriodSelection.canMove(PeriodSelection.minimum, by: 1))
            t.check(!PeriodSelection.canMove(PeriodSelection.maximum, by: 1))
            t.check(PeriodSelection.canMove(oct26, by: -1) && PeriodSelection.canMove(oct26, by: 1))
            t.equal(PeriodSelection.moved(PeriodSelection.minimum, by: -1), PeriodSelection.minimum)
            t.equal(PeriodSelection.moved(PeriodSelection.maximum, by: 5), PeriodSelection.maximum)
            t.equal(PeriodSelection.clamp(YearMonth(year: 1990, month: 6)), PeriodSelection.minimum)
            t.equal(PeriodSelection.clamp(YearMonth(year: 2200, month: 6)), PeriodSelection.maximum)
            t.equal(PeriodSelection.clamp(oct26), oct26)
        },
        TestCase("PeriodSelection: escolher mês e ano na sheet") { t in
            t.equal(PeriodSelection.select(month: 3, year: 2025), YearMonth(year: 2025, month: 3))
            t.equal(PeriodSelection.select(month: 13, year: 2025), YearMonth(year: 2026, month: 1))   // normaliza como YearMonth
            t.equal(PeriodSelection.select(month: 6, year: 1900), PeriodSelection.minimum)
            t.equal(PeriodSelection.select(month: 6, year: 3000), PeriodSelection.maximum)
            t.equal(PeriodSelection.years, 2000...2100)
            t.check(PeriodSelection.canSelectYear(2026) && !PeriodSelection.canSelectYear(2101) && !PeriodSelection.canSelectYear(1999))
        },
        TestCase("PeriodSelection: mês atual e retorno a hoje") { t in
            t.check(PeriodSelection.isCurrent(oct26, today: testToday))
            t.check(!PeriodSelection.isCurrent(oct26.previous, today: testToday))
            t.equal(PeriodSelection.current(today: testToday), oct26)
        },
        TestCase("AppStore: viewedMonth começa no mês de hoje, navega, limita e volta para hoje") { t in onMain {
            let store = makeStore()
            t.equal(store.viewedMonth, store.currentMonth)
            t.check(store.isViewingCurrentMonth)
            store.stepViewedMonth(by: -1)
            t.equal(store.viewedMonth, store.currentMonth.previous)
            t.check(!store.isViewingCurrentMonth)
            t.equal(store.currentMonth, YearMonth(testToday))   // "agora" não muda
            store.setViewedMonth(YearMonth(year: 1800, month: 1))
            t.equal(store.viewedMonth, PeriodSelection.minimum)
            store.resetViewedMonth()
            t.equal(store.viewedMonth, store.currentMonth)
        } },
        TestCase("AppStore: orçamento e cópia valem para o mês visualizado") { t in onMain {
            let store = makeStore()
            let c = store.expenseCategories
            let viewed = store.currentMonth.adding(months: 2)
            try! store.setBudget(categoryId: c[0].id, limit: 100, month: viewed.previous)
            store.setViewedMonth(viewed)
            try! store.setBudget(categoryId: c[1].id, limit: 50)          // sem mês: usa o visualizado
            t.equal(store.budgets.filter { $0.month == viewed }.count, 1)
            t.equal(try! store.copyBudgetsFromPreviousMonth(), 1)          // copia de viewed.previous para viewed
            t.equal(store.budgets.filter { $0.month == viewed }.count, 2)
            t.equal(store.budgets.filter { $0.month == store.currentMonth }.count, 0)
        } },
        TestCase("AppStore: faturas abrem no mês visualizado") { t in onMain {
            let store = makeStore()
            try! store.addCard(name: "Nu", limit: 1000, closingDay: 10, dueDay: 17, paymentAccountId: nil)
            let card = store.creditCards[0]
            let tabsNow = store.invoiceTabs(for: card)
            t.equal(tabsNow[1].invoice.month, CreditCardEngine.currentInvoiceMonth(card: card, asOf: store.today))
            store.setViewedMonth(YearMonth(year: 2025, month: 3))
            let tabs = store.invoiceTabs(for: card)
            t.equal(tabs.map(\.invoice.month), [YearMonth(year: 2025, month: 2), YearMonth(year: 2025, month: 3),
                                                YearMonth(year: 2025, month: 4), YearMonth(year: 2025, month: 5)])
            t.equal(tabs[1].total, 0)
        } },
        TestCase("TransactionFilter: período 'mês' segue o mês visualizado") { t in
            let acc = Account(name: "C", type: .checking)
            let lookup = FinanceLookup(accounts: [acc], categories: [], tags: [], cards: [])
            let sep = Transaction(type: .expense, amount: 10, date: D(2026, 9, 20), title: "Set", accountId: acc.id)
            let oct = Transaction(type: .expense, amount: 20, date: D(2026, 10, 5), title: "Out", accountId: acc.id)
            let nov = Transaction(type: .expense, amount: 30, date: D(2026, 11, 5), title: "Nov", accountId: acc.id)
            let all = [sep, oct, nov]
            let f = TransactionFilter()
            t.equal(f.apply(to: all, lookup: lookup, today: testToday).map(\.title), ["Out"])
            t.equal(f.apply(to: all, lookup: lookup, today: testToday, month: YearMonth(year: 2026, month: 9)).map(\.title), ["Set"])
            t.equal(f.apply(to: all, lookup: lookup, today: testToday, month: YearMonth(year: 2026, month: 11)).map(\.title), ["Nov"])
            var last = TransactionFilter(); last.period = .lastMonth
            t.equal(last.apply(to: all, lookup: lookup, today: testToday, month: YearMonth(year: 2026, month: 11)).map(\.title), ["Out"])
            t.equal(FilterPeriod.thisMonth.title(viewed: oct26, today: testToday), "Este mês")
            t.equal(FilterPeriod.thisMonth.title(viewed: oct26.previous, today: testToday), "Setembro de 2026")
            t.equal(FilterPeriod.lastMonth.title(viewed: oct26.previous, today: testToday), "Agosto de 2026")
        },
        TestCase("ReportPeriod: intervalos relativos ao mês visualizado") { t in
            let sep = YearMonth(year: 2026, month: 9)
            let r = ReportPeriod.thisMonth.range(today: testToday, month: sep)
            t.equal(Fmt.date(r.from), "01/09/2026"); t.equal(Fmt.date(r.to), "30/09/2026")
            let l = ReportPeriod.lastMonth.range(today: testToday, month: sep)
            t.equal(Fmt.date(l.from), "01/08/2026"); t.equal(Fmt.date(l.to), "31/08/2026")
            let q = ReportPeriod.last3Months.range(today: testToday, month: sep)
            t.equal(Fmt.date(q.from), "01/07/2026"); t.equal(Fmt.date(q.to), "30/09/2026")
            let y = ReportPeriod.thisYear.range(today: testToday, month: YearMonth(year: 2025, month: 3))
            t.equal(Fmt.date(y.from), "01/01/2025")
            t.equal(Fmt.date(ReportPeriod.thisMonth.range(today: testToday).to), "31/10/2026")   // sem mês: igual a antes
            t.equal(ReportPeriod.thisMonth.title(viewed: sep, today: testToday), "Setembro de 2026")
            t.equal(ReportPeriod.thisMonth.title(viewed: oct26, today: testToday), "Este mês")
        },
    ]
}
