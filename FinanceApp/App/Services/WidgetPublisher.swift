import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Grava o resumo no App Group e pede ao WidgetKit para recarregar. Só escreve quando o conteúdo muda.
/// Sem a capability App Groups configurada (`SharedContainer.widgetFileURL()` nil), não faz nada.
final class AppGroupWidgetPublisher: WidgetPublishing {
    private var last: WidgetSnapshot?
    private let url: URL?

    init(url: URL? = SharedContainer.widgetFileURL()) { self.url = url }

    func publish(_ snapshot: WidgetSnapshot) {
        guard let url else { return }
        var comparable = snapshot; comparable.generatedAt = .distantPast
        var previous = last; previous?.generatedAt = .distantPast
        guard comparable != previous else { return }
        do {
            try WidgetSnapshotStore.save(snapshot, to: url)
            last = snapshot
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        } catch {
            // Falha de escrita não deve afetar o app; o widget continua com o último resumo.
        }
    }
}

func makeWidgetPublisher() -> WidgetPublishing {
    SharedContainer.widgetFileURL() == nil ? NoopWidgetPublisher() : AppGroupWidgetPublisher()
}
