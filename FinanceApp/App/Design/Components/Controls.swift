import SwiftUI

// MARK: - Badge

struct Badge: View {
    let text: String
    var tone: BillStatus.Tone = .neutral

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tone.text)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, Space.xs)
            .background(tone.soft, in: Capsule())
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Chip

struct ChipLabel: View {
    let title: String
    var systemImage: String? = nil
    var isSelected: Bool = false
    var badgeCount: Int? = nil

    var body: some View {
        HStack(spacing: Space.xs) {
            if let systemImage { Image(systemName: systemImage).imageScale(.small) }
            Text(title).lineLimit(1)
            if let badgeCount, badgeCount > 0 {
                Text("\(badgeCount)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.textOnBrand)
                    .frame(minWidth: 18, minHeight: 18)
                    .background(Color.brandPrimary, in: Circle())
            }
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(isSelected ? Color.brandPrimary : Color.textPrimary)
        .padding(.horizontal, Space.md)
        .frame(minHeight: 36)
        .background(isSelected ? Color.brandSoft : Color.sunken, in: Capsule())
        .overlay(Capsule().strokeBorder(isSelected ? Color.brandPrimary : Color.clear, lineWidth: 1))
        .frame(minHeight: Space.minTouchTarget)
        .contentShape(Rectangle())
    }
}

struct Chip: View {
    let title: String
    var systemImage: String? = nil
    var isSelected: Bool = false
    var badgeCount: Int? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ChipLabel(title: title, systemImage: systemImage, isSelected: isSelected, badgeCount: badgeCount)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Progress

struct ProgressBar: View {
    var fraction: Double
    var tone: BillStatus.Tone = .brand
    /// Marca (por exemplo 0,8 para o alerta de orçamento).
    var marker: Double? = nil
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Color.sunken)
                Capsule().fill(tone.fill).frame(width: max(height, w * min(max(fraction, 0), 1)))
                    .opacity(fraction <= 0 ? 0 : 1)
                if let marker {
                    Rectangle().fill(Color.textTertiary.opacity(0.7))
                        .frame(width: 2, height: height + 6)
                        .offset(x: w * marker - 1)
                }
            }
            .frame(height: height + 6, alignment: .center)
        }
        .frame(height: height + 6)
        .accessibilityHidden(true)   // o texto ao lado ("82% usado") carrega a informação
    }
}

// MARK: - Ícone de categoria

struct CategoryIcon: View {
    var token: String = CategoryStyle.fallbackToken
    var symbol: String = CategoryStyle.fallbackIcon
    var size: CGFloat = 36

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.44, weight: .semibold))
            .foregroundStyle(Color.category(token))
            .frame(width: size, height: size)
            .background(Color.category(token).opacity(0.14), in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .accessibilityHidden(true)
    }
}

extension CategoryIcon {
    init(category: Category?, lookup: FinanceLookup, size: CGFloat = 36) {
        self.init(token: CategoryStyle.token(for: category, in: lookup), symbol: CategoryStyle.icon(for: category), size: size)
    }
}

// MARK: - Botões

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(isEnabled ? Color.textOnBrand : Color.textTertiary)
            .frame(maxWidth: .infinity, minHeight: Space.rowMinHeight)
            .background(isEnabled ? Color.brandPrimary : Color.sunken, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Capsule())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(isEnabled ? Color.brandPrimary : Color.textTertiary)
            .frame(maxWidth: .infinity, minHeight: Space.minTouchTarget)
            .background(Color.brandSoft, in: Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Capsule())
    }
}

/// Botão de texto (ações secundárias em linhas e blocos), com alvo de 44pt.
struct LinkButtonStyle: ButtonStyle {
    var tone: BillStatus.Tone = .brand
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tone == .danger ? Color.danger : Color.brandPrimary)
            .frame(minHeight: Space.minTouchTarget)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle { static var primary: PrimaryButtonStyle { .init() } }
extension ButtonStyle where Self == SecondaryButtonStyle { static var secondary: SecondaryButtonStyle { .init() } }

// MARK: - Seletor segmentado (Planejar, Carteira)

struct SegmentedTabs<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    var identifier: String

    var body: some View {
        Picker("Seção", selection: $selection) {
            ForEach(options, id: \.value) { Text($0.title).tag($0.value) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier(identifier)
    }
}

#Preview("Controles") {
    VStack(alignment: .leading, spacing: 16) {
        HStack { Badge(text: "Restam R$ 120,00", tone: .brand); Badge(text: "82% usado", tone: .warning); Badge(text: "Estourou R$ 42,10", tone: .danger) }
        HStack { Badge(text: "Pago", tone: .ok); Badge(text: "Pendente", tone: .neutral) }
        HStack { Chip(title: "Filtros", systemImage: "line.3.horizontal.decrease", badgeCount: 2) {}; Chip(title: "Despesas", isSelected: true) {}; Chip(title: "Receitas") {} }
        ProgressBar(fraction: 0.4, marker: 0.8)
        ProgressBar(fraction: 0.85, tone: .warning, marker: 0.8)
        ProgressBar(fraction: 1, tone: .danger, marker: 0.8)
        ProgressBar(fraction: 0)
        HStack { CategoryIcon(token: "catMoradia", symbol: "house"); CategoryIcon(token: "catMercado", symbol: "cart"); CategoryIcon(token: "catLazer", symbol: "ticket"); CategoryIcon() }
        Button("Salvar despesa") {}.buttonStyle(.primary)
        Button("Salvar despesa") {}.buttonStyle(.primary).disabled(true)
        Button("Guardar dinheiro") {}.buttonStyle(.secondary)
        Button("Pagar") {}.buttonStyle(LinkButtonStyle())
    }
    .padding()
    .background(Color.canvas)
}

#Preview("Controles, escuro") {
    VStack(alignment: .leading, spacing: 16) {
        HStack { Badge(text: "Restam R$ 120,00", tone: .brand); Badge(text: "82% usado", tone: .warning); Badge(text: "Estourou", tone: .danger) }
        HStack { Chip(title: "Despesas", isSelected: true) {}; Chip(title: "Receitas") {} }
        ProgressBar(fraction: 0.85, tone: .warning, marker: 0.8)
        HStack { CategoryIcon(token: "catMoradia", symbol: "house"); CategoryIcon(token: "catSaude", symbol: "heart") }
        Button("Salvar receita") {}.buttonStyle(.primary)
    }
    .padding()
    .background(Color.canvas)
    .preferredColorScheme(.dark)
}

#Preview("Badge com texto longo e texto grande") {
    VStack(alignment: .leading, spacing: 16) {
        Badge(text: "Recebimento atrasado há muitos dias, confira", tone: .danger)
        Chip(title: "Uma categoria com nome extremamente longo", isSelected: true) {}
        Button("Salvar transferência entre contas") {}.buttonStyle(.primary)
    }
    .padding()
    .background(Color.canvas)
    .dynamicTypeSize(.accessibility3)
}
