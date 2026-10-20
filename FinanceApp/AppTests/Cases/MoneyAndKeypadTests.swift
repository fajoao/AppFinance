import Foundation
#if canImport(FinanceApp)
@testable import FinanceApp
#endif

func moneyDisplayTests() -> [TestCase] {
    [
        TestCase("parts separa sinal, símbolo, reais e centavos") { t in
            let p = MoneyDisplay.parts(dec("-1234.5"))
            t.equal(p, MoneyParts(sign: "\u{2212}", symbol: "R$", integer: "1.234", fraction: ",50"))
            t.equal(MoneyDisplay.parts(0).integer, "0")
            t.equal(MoneyDisplay.parts(dec("12345678.9")).integer, "12.345.678")
        },
        TestCase("sinais: despesa −, receita +, transferência sem sinal, saldo negativo −") { t in
            let n = "\u{00A0}"
            t.equal(MoneyDisplay.text(dec("45.9"), sign: .expense), "\u{2212}R$\(n)45,90")
            t.equal(MoneyDisplay.text(dec("5200"), sign: .income), "+R$\(n)5.200,00")
            t.equal(MoneyDisplay.text(dec("500"), sign: .none), "R$\(n)500,00")
            t.equal(MoneyDisplay.text(dec("-12.3")), "\u{2212}R$\(n)12,30")
            t.equal(MoneyDisplay.text(0, sign: .expense), "R$\(n)0,00")
            // estorno: despesa negativa vira entrada
            t.equal(MoneyDisplay.text(dec("-50"), sign: .expense), "+R$\(n)50,00")
        },
        TestCase("valores ocultos usam máscara e VoiceOver lê 'valor oculto'") { t in
            t.equal(MoneyDisplay.text(dec("999"), hidden: true), "R$\u{00A0}••••")
            t.equal(MoneyDisplay.spoken(dec("999"), hidden: true), "valor oculto")
        },
        TestCase("leitura por extenso em pt-BR") { t in
            t.equal(MoneyDisplay.spoken(dec("-45.90")), "menos quarenta e cinco reais e noventa centavos")
            t.equal(MoneyDisplay.spoken(1), "um real")
            t.equal(MoneyDisplay.spoken(0), "zero reais")
            t.equal(MoneyDisplay.spoken(dec("0.01")), "um centavo")
            t.equal(MoneyDisplay.spoken(dec("100")), "cem reais")
            t.equal(MoneyDisplay.spoken(dec("101")), "cento e um reais")
            t.equal(MoneyDisplay.spoken(dec("1001")), "mil e um reais")
            t.equal(MoneyDisplay.spoken(dec("1234.56")), "mil duzentos e trinta e quatro reais e cinquenta e seis centavos")
            t.equal(MoneyDisplay.spoken(dec("2000")), "dois mil reais")
            t.equal(MoneyDisplay.spoken(dec("1000000")), "um milhão de reais")
            t.equal(MoneyDisplay.spoken(dec("1500000")), "um milhão e quinhentos mil reais")
            t.equal(MoneyDisplay.spoken(dec("5200"), prefix: "mais"), "mais cinco mil e duzentos reais")
        },
        TestCase("eixo de gráfico abrevia sem centavos") { t in
            t.equal(MoneyDisplay.axis(dec("1200")), "R$\u{00A0}1,2 mil")
            t.equal(MoneyDisplay.axis(dec("3000")), "R$\u{00A0}3 mil")
            t.equal(MoneyDisplay.axis(dec("50")), "R$\u{00A0}50")
        },
        TestCase("lançamento: texto e papel por tipo") { t in
            let exp = Transaction(type: .expense, amount: dec("45.9"), date: testToday, title: "x")
            let inc = Transaction(type: .income, amount: dec("10"), date: testToday, title: "x")
            let inv = Transaction(type: .transfer, amount: dec("10"), date: testToday, title: "x", invoiceId: UUID())
            t.equal(MoneyDisplay.role(for: exp), .expense)
            t.equal(MoneyDisplay.role(for: inc), .income)
            t.equal(MoneyDisplay.role(for: inv), .transfer)
            t.equal(MoneyDisplay.spoken(for: inv), "pagamento de fatura, dez reais")
            t.equal(MoneyDisplay.role(for: dec("-1")), .negative)
            t.equal(MoneyDisplay.role(for: 0), .zero)
        },
    ]
}

func keypadTests() -> [TestCase] {
    func type(_ keys: String) -> AmountKeypad {
        var k = AmountKeypad()
        for ch in keys {
            if ch == "," { k.press(.comma) } else if ch == "<" { k.press(.delete) } else if let d = ch.wholeNumberValue { k.press(.digit(d)) }
        }
        return k
    }
    return [
        TestCase("digitação básica e centavos") { t in
            t.equal(type("1234,5").value, dec("1234.5"))
            t.equal(type("1234,56").value, dec("1234.56"))
            t.equal(type("0,07").value, dec("0.07"))
            t.equal(type("").value, 0)
            t.check(type("").isEmpty)
        },
        TestCase("máximo de 2 casas e 9 dígitos inteiros") { t in
            t.equal(type("1,999").value, dec("1.99"))
            t.equal(type("12345678901").value, dec("123456789"))
        },
        TestCase("zeros à esquerda e vírgula inicial") { t in
            t.equal(type("007").value, 7)
            t.equal(type(",5").value, dec("0.5"))
            t.equal(type("000").value, 0)
        },
        TestCase("apagar remove centavo, depois a vírgula, depois o inteiro") { t in
            var k = type("12,3")
            k.press(.delete); t.equal(k.displayParts.fraction, ",00"); t.equal(k.value, 12)
            k.press(.delete); t.equal(k.value, 12)       // remove a vírgula
            k.press(.digit(5)); t.equal(k.value, 125)
            k.press(.delete); k.press(.delete); k.press(.delete); k.press(.delete)
            t.check(k.isEmpty)
        },
        TestCase("exibição agrupa milhar e mantém centavos digitados") { t in
            let k = type("1234,5")
            t.equal(k.displayParts.integer, "1.234")
            t.equal(k.displayParts.fraction, ",50")
            t.equal(k.typedFractionCount, 1)
        },
        TestCase("inicializa a partir de um Decimal") { t in
            t.equal(AmountKeypad(value: dec("12.50")).value, dec("12.5"))
            t.equal(AmountKeypad(value: dec("1000")).value, 1000)
            t.equal(AmountKeypad(value: dec("0.05")).value, dec("0.05"))
            t.check(AmountKeypad(value: 0).isEmpty)
        },
    ]
}
