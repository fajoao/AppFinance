import SwiftUI

#if DEBUG
/// Galeria de componentes (somente builds de debug): mostra os componentes do design system juntos.
struct ComponentGallery: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                block("Numeral dividido") {
                    SplitAmount(value: dec("24568.90"))
                    SplitAmount(value: dec("-1234.56"), style: .large)
                }
                block("Valores em linha") {
                    AmountText(dec("45.90"), sign: .expense, role: .expense)
                    AmountText(dec("5200"), sign: .income, role: .income)
                    AmountText(dec("500"), sign: .none, role: .transfer)
                    AmountText(balance: dec("-250.10"))
                }
                block("Badges") {
                    FlowLayout {
                        Badge(text: "Pago", tone: .ok); Badge(text: "Vence amanhã", tone: .warning)
                        Badge(text: "Atrasado 4 dias", tone: .danger); Badge(text: "A receber", tone: .brand); Badge(text: "Pendente")
                    }
                }
                block("Chips") {
                    FlowLayout {
                        Chip(title: "Filtros", systemImage: "line.3.horizontal.decrease", badgeCount: 2) {}
                        Chip(title: "Despesas", isSelected: true) {}
                        Chip(title: "Receitas") {}
                    }
                }
                block("Barras de progresso") {
                    ProgressBar(fraction: 0.35, marker: 0.8)
                    ProgressBar(fraction: 0.85, tone: .warning, marker: 0.8)
                    ProgressBar(fraction: 1, tone: .danger, marker: 0.8)
                }
                block("Categorias") {
                    HStack {
                        ForEach(["catMoradia", "catMercado", "catTransporte", "catLazer", "catSaude", "catEducacao", "catOutros"], id: \.self) {
                            CategoryIcon(token: $0, symbol: "circle.fill")
                        }
                    }
                }
                block("Botões") {
                    Button("Salvar despesa") {}.buttonStyle(.primary)
                    Button("Guardar dinheiro") {}.buttonStyle(.secondary)
                }
                block("Campo com erro") {
                    LabeledField(label: "Nome da conta", text: .constant(""), error: "Dê um nome para a conta.", identifier: "gallery.field")
                }
                block("Toast") { ToastView(message: ToastMessage(text: "Orçamento de Mercado em 82%.", isWarning: true)) }
            }
            .padding(Space.screenMargin)
        }
        .background(Color.canvas)
        .navigationTitle("Galeria")
        .inlineNavigationTitle()
        .accessibilityIdentifier("gallery")
    }

    private func block<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(title)
            VStack(alignment: .leading, spacing: Space.md) { content() }
                .padding(Space.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
    }
}

#Preview("Galeria") {
    NavigationStack { ComponentGallery() }
}

#Preview("Galeria, escuro") {
    NavigationStack { ComponentGallery() }.preferredColorScheme(.dark)
}
#endif
