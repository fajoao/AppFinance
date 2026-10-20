import SwiftUI

/// Teclado numérico próprio (1-9, vírgula, 0, apagar). Identificadores: keypad.<tecla>.
struct NumericKeypad: View {
    let onKey: (AmountKeypad.Key) -> Void

    private let rows: [[AmountKeypad.Key]] = [
        [.digit(1), .digit(2), .digit(3)],
        [.digit(4), .digit(5), .digit(6)],
        [.digit(7), .digit(8), .digit(9)],
        [.comma, .digit(0), .delete],
    ]

    var body: some View {
        VStack(spacing: Space.sm) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: Space.sm) {
                    ForEach(rows[r].indices, id: \.self) { c in key(rows[r][c]) }
                }
            }
        }
        .padding(Space.sm)
        .background(Color.surfaceRaised)
    }

    private func key(_ key: AmountKeypad.Key) -> some View {
        Button {
            Haptics.tap()
            onKey(key)
        } label: {
            Group {
                switch key {
                case .digit(let d): Text("\(d)").font(.title2.weight(.medium)).monospacedDigit()
                case .comma: Text(",").font(.title2.weight(.medium))
                case .delete: Image(systemName: "delete.left").font(.title3)
                }
            }
            .foregroundStyle(Color.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.sunken, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label(key))
        .accessibilityIdentifier("keypad." + id(key))
    }

    private func label(_ k: AmountKeypad.Key) -> String {
        switch k {
        case .digit(let d): return "\(d)"
        case .comma: return "vírgula"
        case .delete: return "apagar"
        }
    }

    private func id(_ k: AmountKeypad.Key) -> String {
        switch k {
        case .digit(let d): return "\(d)"
        case .comma: return "comma"
        case .delete: return "delete"
        }
    }
}

/// Valor em edição com cursor piscante (respeita Reduzir Movimento).
struct AmountEntryDisplay: View {
    let keypad: AmountKeypad
    var color: Color = .textPrimary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var cursorOn = true
    @ScaledMetric(relativeTo: .largeTitle) private var scale: CGFloat = 1

    var body: some View {
        let p = keypad.displayParts
        let size = 48 * scale, minor = size * 0.45
        let dim = keypad.isEmpty
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(p.symbol).font(.system(size: minor, weight: .medium))
                .baselineOffset(size * 0.70 - minor * 0.70).padding(.trailing, minor * 0.12)
            Text(p.integer).font(.system(size: size, weight: .semibold)).tracking(-size * 0.025)
            Rectangle().fill(Color.brandPrimary).frame(width: 2, height: size * 0.8)
                .opacity(cursorOn ? 1 : 0).accessibilityHidden(true)
            Text(p.fraction).font(.system(size: minor, weight: .medium))
                .baselineOffset(size * 0.70 - minor * 0.70)
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.4)
        .foregroundStyle(dim ? Color.textTertiary : color)
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 530_000_000)
                cursorOn.toggle()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dim ? "Valor, zero reais" : "Valor, " + MoneyDisplay.spoken(keypad.value))
        .accessibilityIdentifier("transaction.new.amount")
    }
}

#Preview("Teclado") {
    VStack(spacing: 0) {
        AmountEntryDisplay(keypad: AmountKeypad()).padding()
        AmountEntryDisplay(keypad: AmountKeypad(value: dec("1234.5"))).padding()
        Spacer()
        NumericKeypad { _ in }
    }
    .background(Color.canvas)
}

#Preview("Teclado, escuro e valor grande") {
    VStack(spacing: 0) {
        AmountEntryDisplay(keypad: AmountKeypad(value: dec("987654321.99"))).padding()
        Spacer()
        NumericKeypad { _ in }
    }
    .background(Color.canvas)
    .preferredColorScheme(.dark)
}
