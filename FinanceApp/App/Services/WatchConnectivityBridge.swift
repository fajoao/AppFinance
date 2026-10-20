import Foundation
#if canImport(WatchConnectivity) && os(iOS)
import WatchConnectivity

/// Ponte iPhone <-> Apple Watch (WatchConnectivity). Envia o resumo (`WidgetSnapshot`) por `applicationContext` e recebe
/// despesas ditadas no relógio por `transferUserInfo`. Só transporte: o formato e as regras estão em `Core/WatchLink.swift`.
/// Sem relógio pareado ou sem o app do relógio instalado, não faz nada.
final class WatchConnectivityBridge: NSObject, WCSessionDelegate, WidgetPublishing, @unchecked Sendable {
    private var last: WidgetSnapshot?
    /// Chamado no MainActor para cada despesa ditada recebida.
    @MainActor var onQuickAdd: ((WatchQuickAddRequest) -> Void)?

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func publish(_ snapshot: WidgetSnapshot) {
        last = snapshot
        push()
    }

    private func push() {
        guard WCSession.isSupported(), let last else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        try? session.updateApplicationContext(WatchLink.context(for: last))
    }

    // MARK: WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) { push() }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    func sessionWatchStateDidChange(_ session: WCSession) { push() }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let request = WatchLink.quickAdd(from: userInfo) else { return }
        Task { @MainActor in self.onQuickAdd?(request) }
    }
}
#endif

/// Repassa o resumo para vários destinos (widgets e relógio).
struct CompositeWidgetPublisher: WidgetPublishing {
    let targets: [WidgetPublishing]
    func publish(_ snapshot: WidgetSnapshot) { targets.forEach { $0.publish(snapshot) } }
}
