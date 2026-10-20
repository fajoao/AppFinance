import Foundation
import Observation
import SwiftUI
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Estado do relógio. Recebe o resumo do iPhone, guarda no arquivo compartilhado com a complicação e envia despesas ditadas.
@MainActor @Observable
final class WatchModel: NSObject {
    enum SendState: Equatable { case idle, queued, failed(String) }

    private(set) var snapshot: WidgetSnapshot?
    private(set) var sendState: SendState = .idle

    var dashboard: WatchDashboard { WatchDashboard.make(snapshot: snapshot, now: Date()) }

    override init() {
        super.init()
        if let url = SharedContainer.widgetFileURL() { snapshot = WidgetSnapshotStore.load(from: url) }
    }

    func start() {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        #endif
    }

    func apply(_ snapshot: WidgetSnapshot) {
        self.snapshot = snapshot
        if let url = SharedContainer.widgetFileURL() { try? WidgetSnapshotStore.save(snapshot, to: url) }
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    /// Envia a despesa ditada ao iPhone. A fila do WatchConnectivity entrega mesmo com o iPhone fora de alcance.
    func send(text: String) {
        guard WatchQuickAdd.preview(text) != nil else { sendState = .failed(WatchQuickAdd.invalidMessage); return }
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { sendState = .failed("Sem conexão com o iPhone."); return }
        WCSession.default.transferUserInfo(WatchLink.message(for: WatchQuickAddRequest(text: text)))
        sendState = .queued
        #else
        sendState = .failed("Sem conexão com o iPhone.")
        #endif
    }

    func resetSendState() { sendState = .idle }
}

#if canImport(WatchConnectivity)
extension WatchModel: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        guard let s = WatchLink.snapshot(from: context) else { return }
        Task { @MainActor in self.apply(s) }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let s = WatchLink.snapshot(from: applicationContext) else { return }
        Task { @MainActor in self.apply(s) }
    }
}
#endif
