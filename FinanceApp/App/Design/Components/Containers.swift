import SwiftUI

// MARK: - Grupo de lista (surface sobre canvas, sem sombra)

struct ListGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

/// Bloco destacado (fatura, meta): raio maior.
struct HighlightBlock<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) { content }
            .padding(Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
    }
}

struct RowSeparator: View {
    var inset: CGFloat = Space.lg
    var body: some View {
        Rectangle().fill(Color.separator).frame(height: 0.5).padding(.leading, inset).accessibilityHidden(true)
    }
}

/// Linhas de um array separadas por hairline (sem linha depois da última).
struct SeparatedRows<Item: Identifiable, Row: View>: View {
    let items: [Item]
    var inset: CGFloat = Space.lg
    @ViewBuilder var row: (Item) -> Row

    var body: some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            row(item)
            if index < items.count - 1 { RowSeparator(inset: inset) }
        }
    }
}

/// Linha padrão: ícone opcional, título + subtítulo, valor à direita. Com tamanhos de texto de acessibilidade,
/// o valor passa para baixo, alinhado à direita (nunca trunca).
struct ListRow<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Space.xs) {
                    HStack(spacing: Space.md) { leading; titles }
                    trailing.frame(maxWidth: .infinity, alignment: .trailing)
                }
            } else {
                HStack(spacing: Space.md) {
                    leading
                    titles.frame(maxWidth: .infinity, alignment: .leading)
                    trailing.fixedSize(horizontal: true, vertical: false)
                }
            }
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .frame(minHeight: Space.rowMinHeight)
        // A linha inteira é tocável (não só o texto): sem isto, o espaço vazio entre o texto e o "›" não ativava o NavigationLink/Button.
        .contentShape(Rectangle())
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.body).foregroundStyle(Color.textPrimary).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                Text(subtitle).font(.footnote).foregroundStyle(Color.textSecondary).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Cabeçalho de seção

struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(Color.textSecondary)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            trailing
        }
        .padding(.horizontal, Space.xs)
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) { self.init(title: title) { EmptyView() } }
}

// MARK: - Estado vazio

struct EmptyState: View {
    let symbol: String
    let title: String
    var message: String? = nil
    var actionTitle: String? = nil
    var actionIdentifier: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: Space.md) {
            Image(systemName: symbol).font(.system(size: 36, weight: .light)).foregroundStyle(Color.textTertiary)
                .accessibilityHidden(true)
            Text(title).font(.headline).foregroundStyle(Color.textPrimary).multilineTextAlignment(.center)
            if let message {
                Text(message).font(.subheadline).foregroundStyle(Color.textSecondary).multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(LinkButtonStyle())
                    .accessibilityIdentifier(actionIdentifier ?? "empty.action")
            }
        }
        .padding(Space.xxl)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Campo de texto rotulado, com erro inline

struct LabeledField: View {
    let label: String
    @Binding var text: String
    var prompt: String = ""
    var error: String? = nil
    var isDecimal: Bool = false
    var identifier: String

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(label).font(.footnote.weight(.semibold)).foregroundStyle(Color.textSecondary)
            Group {
                if isDecimal {
                    TextField(prompt, text: $text).decimalKeyboard()
                } else {
                    TextField(prompt, text: $text).sentenceCapitalization()
                }
            }
            .font(.body)
            .focused($focused)
            .padding(.horizontal, Space.md)
            .frame(minHeight: Space.minTouchTarget)
            .background(Color.sunken, in: RoundedRectangle(cornerRadius: Radius.sm, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(error != nil ? Color.danger : (focused ? Color.focus : Color.border.opacity(0.5)), lineWidth: focused || error != nil ? 2 : 1))
            .accessibilityIdentifier(identifier)
            if let error {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote).foregroundStyle(Color.danger)
                    .accessibilityIdentifier(identifier + ".error")
            }
        }
    }
}

// MARK: - Toast (flutuante, com sombra)

struct ToastView: View {
    let message: ToastMessage

    var body: some View {
        HStack(spacing: Space.sm) {
            Image(systemName: message.isWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(message.isWarning ? Color.warning : Color.income)
            Text(message.text).font(.subheadline).foregroundStyle(Color.textPrimary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Space.lg)
        .padding(.vertical, Space.md)
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Color.separator, lineWidth: 0.5))
        .shadow(color: Color(red: 0x15 / 255, green: 0x24 / 255, blue: 0x1F / 255).opacity(0.10), radius: 10, y: 6)
        .padding(.horizontal, Space.screenMargin)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("toast")
    }
}

#Preview("Grupo de lista") {
    VStack(spacing: 16) {
        SectionHeader("Contas")
        ListGroup {
            ListRow(title: "Nubank", subtitle: "Conta corrente") { Image(systemName: "building.columns") } trailing: { AmountText(balance: dec("4812.37")) }
            RowSeparator(inset: 56)
            ListRow(title: "Itaú", subtitle: "Cheque especial") { Image(systemName: "building.columns") } trailing: { AmountText(balance: dec("-1240.90")) }
            RowSeparator(inset: 56)
            ListRow(title: "Conta corrente do banco com um nome absurdamente longo para testar a quebra de linha", subtitle: "Saldo de hoje") {
                Image(systemName: "building.columns")
            } trailing: { AmountText(balance: dec("98765432.10")) }
        }
        HighlightBlock { Text("Bloco destacado").font(.headline); SplitAmount(value: dec("2104.77"), style: .large) }
    }
    .padding()
    .background(Color.canvas)
}

#Preview("Grupo de lista, escuro e texto grande") {
    ListGroup {
        ListRow(title: "Nubank", subtitle: "Conta corrente") { Image(systemName: "building.columns") } trailing: { AmountText(balance: dec("4812.37")) }
    }
    .padding()
    .background(Color.canvas)
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility3)
}

#Preview("Estado vazio e campo") {
    VStack(spacing: 16) {
        EmptyState(symbol: "tray", title: "Nenhum lançamento encontrado", message: "Tente outra busca ou limpe os filtros.", actionTitle: "Limpar busca e filtros") {}
        LabeledField(label: "Nome da conta", text: .constant(""), prompt: "Ex.: Nubank", error: "Dê um nome para a conta.", identifier: "preview.field")
        LabeledField(label: "Saldo de hoje", text: .constant("1.250,00"), isDecimal: true, identifier: "preview.field2")
        ToastView(message: ToastMessage(text: "Mercado: estourou o orçamento em R$ 42,10.", isWarning: true))
        ToastView(message: ToastMessage(text: "Lançamento salvo."))
    }
    .padding()
    .background(Color.canvas)
}

#Preview("Estado vazio, escuro") {
    VStack {
        EmptyState(symbol: "tray", title: "Nenhum lançamento", message: "Toque em Novo para registrar.")
        ToastView(message: ToastMessage(text: "Pronto", isWarning: false))
    }
    .background(Color.canvas)
    .preferredColorScheme(.dark)
}

/// Mostra o toast da store sobre o conteúdo. Cada sheet usa o seu, porque o toast da raiz fica atrás dela.
struct ToastHost: ViewModifier {
    @Environment(AppStore.self) private var store
    var announces: Bool

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let toast = store.toast {
                ToastView(message: toast)
                    .padding(.top, Space.sm)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: toast.id) {
                        if announces { AccessibilityNotification.Announcement(toast.text).post() }
                        // Se a tarefa for cancelada (ex.: a sheet que a criou fechou), NÃO limpa o toast: quem continua na tela cuida disso.
                        // Antes, `try?` engolia o cancelamento e o toast sumia logo depois de fechar a sheet.
                        do { try await Task.sleep(nanoseconds: 3_500_000_000) } catch { return }
                        if store.toast?.id == toast.id { withAnimation { store.toast = nil } }
                    }
                    .zIndex(10)
            }
        }
    }
}

extension View {
    func toastHost(announces: Bool = false) -> some View { modifier(ToastHost(announces: announces)) }
}

// MARK: - Atualizar (puxar para baixo)

extension View {
    /// Puxar para atualizar: `AppStore.refresh()` + háptico leve ao concluir. Só em telas rolável principais (nunca em
    /// sheets de formulário nem no teclado numérico do Novo lançamento).
    func refreshableStore() -> some View { modifier(StoreRefreshable()) }
}

struct StoreRefreshable: ViewModifier {
    @Environment(AppStore.self) private var store

    func body(content: Content) -> some View {
        content.refreshable {
            if await store.refresh(announcesSuccess: false) == .updated { Haptics.tap() }
        }
    }
}

/// Botão de atualizar da barra de navegação: gira enquanto atualiza e fica desabilitado.
struct RefreshButton: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let time: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "pt_BR"); f.dateFormat = "HH:mm:ss"; return f
    }()

    var body: some View {
        let busy = store.isRefreshing
        Button { Task { if await store.refresh() == .updated { Haptics.tap() } } } label: {
            Image(systemName: "arrow.clockwise")
                .rotationEffect(.degrees(busy && !reduceMotion ? 360 : 0))
                .animation(busy && !reduceMotion ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: busy)
                .opacity(busy && reduceMotion ? 0.4 : 1)
        }
        .disabled(busy)
        .accessibilityLabel("Atualizar")
        .accessibilityValue(busy ? "Atualizando" : (store.lastRefreshAt.map { "Atualizado às " + Self.time.string(from: $0) } ?? ""))
        .accessibilityIdentifier("refresh.button")
    }
}
