import SwiftUI

/// Numeral dividido: reais grandes, "R$" e centavos pequenos alinhados pelo topo (assinatura visual do app).
struct SplitAmount: View {
    enum Style {
        case hero, large
        var base: CGFloat { self == .hero ? 48 : 28 }
        var minorScale: CGFloat { self == .hero ? 0.45 : 0.55 }
    }

    let value: Decimal
    var style: Style = .hero
    /// nil = automático (negativo em `danger`, senão `textPrimary`).
    var color: Color? = nil

    @Environment(\.valuesHidden) private var hidden
    @ScaledMetric(relativeTo: .largeTitle) private var heroScale: CGFloat = 1
    @ScaledMetric(relativeTo: .title) private var largeScale: CGFloat = 1

    var body: some View {
        let size = style.base * (style == .hero ? heroScale : largeScale)
        let minor = size * style.minorScale
        let p = hidden ? MoneyParts(sign: "", symbol: "R$", integer: "••••", fraction: "") : MoneyDisplay.parts(value)
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(p.sign + p.symbol)
                .font(.system(size: minor, weight: .medium))
                .baselineOffset(size * 0.70 - minor * 0.70)
                .padding(.trailing, minor * 0.12)
            Text(p.integer)
                .font(.system(size: size, weight: .semibold))
                .tracking(-size * 0.025)
            Text(p.fraction)
                .font(.system(size: minor, weight: .medium))
                .baselineOffset(size * 0.70 - minor * 0.70)
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.4)
        .foregroundStyle(color ?? (value < 0 ? Color.danger : Color.textPrimary))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MoneyDisplay.spoken(value, hidden: hidden))
    }
}

/// Reproduz a contagem do saldo ao abrir o Início (uma vez por sessão; desligada com Reduzir Movimento e em testes de UI).
struct CountUpSplitAmount: View {
    let value: Decimal
    var style: SplitAmount.Style = .hero

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: Double = (UIRuntime.countUpPlayed || UIRuntime.skipsAnimations) ? 1 : 0

    var body: some View {
        CountingLayer(target: value, progress: progress, style: style)
            .onAppear {
                guard progress < 1 else { return }
                UIRuntime.countUpPlayed = true
                if reduceMotion { progress = 1 } else { withAnimation(.easeOut(duration: 0.6)) { progress = 1 } }
            }
    }

    private struct CountingLayer: View, @preconcurrency Animatable {
        var target: Decimal
        var progress: Double
        var style: SplitAmount.Style
        var animatableData: Double {
            get { progress }
            set { progress = newValue }
        }
        var body: some View {
            let shown = progress >= 1 ? target : (target * Decimal(progress)).rounded(scale: 2)
            SplitAmount(value: shown, style: style)
        }
    }
}

/// Valor em linha (lista): tabular, com sinal e cor pela regra de tokens.
struct AmountText: View {
    enum Size { case row, caption }

    let text: String
    let spoken: String
    var role: AmountRole = .positive
    var size: Size = .row

    @Environment(\.valuesHidden) private var hidden

    /// Saldo/valor simples: negativo em `danger`, zero em `textSecondary`.
    init(balance value: Decimal, size: Size = .row, role: AmountRole? = nil) {
        self.text = MoneyDisplay.text(value)
        self.spoken = MoneyDisplay.spoken(value)
        self.role = role ?? MoneyDisplay.role(for: value)
        self.size = size
    }

    /// Valor com sinal explícito (despesa −, receita +).
    init(_ value: Decimal, sign: AmountSign, role: AmountRole, size: Size = .row) {
        self.text = MoneyDisplay.text(value, sign: sign)
        self.spoken = MoneyDisplay.spoken(value, prefix: sign == .income ? "mais" : (sign == .expense ? "menos" : nil))
        self.role = role
        self.size = size
    }

    init(transaction tx: Transaction, size: Size = .row) {
        self.text = MoneyDisplay.text(for: tx)
        self.spoken = MoneyDisplay.spoken(for: tx)
        self.role = MoneyDisplay.role(for: tx)
        self.size = size
    }

    var body: some View {
        Text(hidden ? MoneyDisplay.masked : text)
            .font(size == .row ? .body.weight(.medium) : .footnote.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(hidden ? Color.textPrimary : role.color)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel(hidden ? MoneyDisplay.hiddenSpoken : spoken)
    }
}

#Preview("Numeral dividido") {
    VStack(alignment: .leading, spacing: 16) {
        SplitAmount(value: dec("24568.90"))
        SplitAmount(value: dec("-1234.56"))
        SplitAmount(value: 0)
        SplitAmount(value: dec("987654321.99"))
        SplitAmount(value: dec("4812.37"), style: .large)
        SplitAmount(value: dec("-45.90"), style: .large)
        CountUpSplitAmount(value: dec("4812.37"))
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.canvas)
}

#Preview("Numeral dividido, escuro, oculto, texto grande") {
    VStack(alignment: .leading, spacing: 16) {
        SplitAmount(value: dec("24568.90"))
        SplitAmount(value: dec("24568.90"), style: .large).environment(\.valuesHidden, true)
        SplitAmount(value: dec("-98765.43"))
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.canvas)
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility2)
}

#Preview("Valores em linha") {
    VStack(alignment: .trailing, spacing: 8) {
        AmountText(dec("45.90"), sign: .expense, role: .expense)
        AmountText(dec("5200"), sign: .income, role: .income)
        AmountText(dec("500"), sign: .none, role: .transfer)
        AmountText(balance: dec("-1250.5"))
        AmountText(balance: 0)
        AmountText(balance: dec("12345678.90"), size: .caption)
        AmountText(balance: dec("999")).environment(\.valuesHidden, true)
    }
    .padding()
    .background(Color.surface)
}

#Preview("Valores em linha, escuro") {
    VStack(alignment: .trailing, spacing: 8) {
        AmountText(dec("45.90"), sign: .expense, role: .expense)
        AmountText(dec("5200"), sign: .income, role: .income)
        AmountText(balance: dec("-1250.5"))
    }
    .padding()
    .background(Color.surface)
    .preferredColorScheme(.dark)
}
