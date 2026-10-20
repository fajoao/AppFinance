import SwiftUI

/// watch.add: despesa rápida. O campo de texto do watchOS oferece ditado; o texto vai ao iPhone, que interpreta
/// ("gastei 45,90 no mercado"). O relógio só confere se há um valor antes de enviar.
struct WatchQuickAddView: View {
    @Environment(WatchModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        let preview = WatchQuickAdd.preview(text)
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Ditar despesa", text: $text)
                    .accessibilityIdentifier("watch.add.text")
                Text("Ex.: \"gastei 45,90 no mercado\"").font(.caption2).foregroundStyle(.secondary)
                if let preview {
                    Text("\(preview.title): \(Money.format(preview.amount))").font(.footnote.weight(.semibold))
                        .accessibilityIdentifier("watch.add.preview")
                } else if !text.isEmpty {
                    Text("Não achei o valor.").font(.footnote).foregroundStyle(.orange)
                }
                Button("Enviar ao iPhone") { model.send(text: text) }
                    .disabled(preview == nil)
                    .accessibilityIdentifier("watch.add.send")
                switch model.sendState {
                case .idle: EmptyView()
                case .queued:
                    Label("Enviado. O iPhone registra quando receber.", systemImage: "checkmark.circle").font(.footnote).foregroundStyle(.green)
                        .accessibilityIdentifier("watch.add.queued")
                case .failed(let message):
                    Text(message).font(.footnote).foregroundStyle(.red).accessibilityIdentifier("watch.add.error")
                }
            }
        }
        .navigationTitle("Nova despesa")
        .onDisappear { model.resetSendState() }
    }
}

#Preview("Despesa rápida") {
    NavigationStack { WatchQuickAddView() }.environment(WatchModel())
}
