import Foundation

/// Opções do sheet "Pagar fatura" (wallet.payInvoice): total, mínimo (15%) ou outro valor.
struct PayInvoiceModel: Equatable, Sendable {
    enum Option: Equatable, Sendable { case full, minimum, custom }

    /// Percentual mínimo exigido pelos emissores (15% do saldo da fatura é a regra usual no Brasil).
    static let minimumPercent: Decimal = 15

    var remaining: Decimal
    var option: Option = .full
    var customText: String = ""
    var accountId: UUID? = nil

    /// Mínimo = 15% do que falta, arredondado para cima em centavos (nunca acima do restante).
    var minimum: Decimal {
        min((remaining * Self.minimumPercent / 100).rounded(scale: 2, mode: .up), remaining)
    }

    var customAmount: Decimal? {
        let t = customText.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : Money.parse(t, style: .comma)
    }

    /// Valor que será pago com a opção atual (nil = inválido).
    var amount: Decimal? {
        switch option {
        case .full: return remaining
        case .minimum: return minimum
        case .custom: return customAmount
        }
    }

    /// Pagar menos que o total deixa saldo no rotativo (juros altos).
    var leavesRevolvingBalance: Bool {
        guard let a = amount else { return false }
        return a < remaining
    }

    var amountError: String? {
        guard option == .custom else { return nil }
        guard let a = customAmount, a > 0 else { return "Informe um valor maior que zero." }
        if a > remaining { return "O valor é maior que o saldo da fatura (\(MoneyDisplay.text(remaining)))." }
        return nil
    }

    func isInsufficient(accountBalance: Decimal?) -> Bool {
        guard let b = accountBalance, let a = amount else { return false }
        return b < a
    }

    func canPay(accountBalance: Decimal?) -> Bool {
        remaining > 0 && accountId != nil && amount.map { $0 > 0 && $0 <= remaining } == true && amountError == nil
    }
}
