import SwiftUI
#if canImport(PhotosUI)
import PhotosUI
#endif

/// scan: ler o QR Code da NFC-e, uma foto de comprovante (OCR no aparelho) ou um texto colado, e levar o resultado
/// para o "Novo lançamento". Nada é salvo aqui e nada sai do aparelho. A consulta à SEFAZ não existe (ver docs/ocr-nfce.md).
struct ScanReceiptView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onUse: (ReceiptPrefill) -> Void

    @State private var mode: Mode = .choose
    @State private var pastedText = ""
    @State private var summary: ScanSummary?
    @State private var errorText: String?
    @State private var isWorking = false
    #if canImport(PhotosUI)
    @State private var pickedPhoto: PhotosPickerItem?
    #endif
    #if canImport(AVFoundation)
    @State private var capture = QRCaptureController()
    #endif

    enum Mode { case choose, camera, paste }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    if let summary { result(summary) } else { chooser }
                    if let errorText {
                        Label(errorText, systemImage: "exclamationmark.circle.fill").font(.footnote).foregroundStyle(Color.danger)
                            .accessibilityIdentifier("scan.error")
                    }
                    Text("A leitura acontece no aparelho. O QR Code de uma NFC-e traz UF, CNPJ e chave; o valor só vem em notas emitidas em contingência. A consulta automática à SEFAZ não está disponível. Sempre confira os dados antes de salvar.")
                        .font(.footnote).foregroundStyle(Color.textTertiary)
                        .accessibilityIdentifier("scan.disclaimer")
                }
                .padding(.horizontal, Space.screenMargin)
                .padding(.vertical, Space.lg)
            }
            .background(Color.canvas)
            .navigationTitle("Ler nota ou comprovante")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { stopCamera(); dismiss() }.accessibilityIdentifier("scan.close")
                }
            }
            #if canImport(PhotosUI)
            .onChange(of: pickedPhoto) { _, item in if let item { Task { await recognize(item) } } }
            #endif
        }
        .accessibilityIdentifier("scan")
        .onDisappear(perform: stopCamera)
    }

    // MARK: Escolha

    private var chooser: some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            #if canImport(AVFoundation) && os(iOS)
            if mode == .camera {
                QRCameraView(controller: capture)
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                    .accessibilityLabel("Câmera lendo o QR Code")
                    .accessibilityIdentifier("scan.camera")
                Button("Cancelar leitura") { stopCamera(); mode = .choose }.buttonStyle(.secondary).accessibilityIdentifier("scan.camera.cancel")
            }
            #endif
            if mode != .camera {
                ListGroup {
                    #if canImport(AVFoundation) && os(iOS)
                    Button { Task { await startCamera() } } label: { ScanOptionRow(symbol: "qrcode.viewfinder", title: "Ler QR Code da nota (NFC-e)", subtitle: "Aponte a câmera para o QR Code do cupom") }
                        .buttonStyle(.plain).accessibilityIdentifier("scan.qr")
                    RowSeparator(inset: 56)
                    #endif
                    #if canImport(PhotosUI)
                    PhotosPicker(selection: $pickedPhoto, matching: .images) {
                        ScanOptionRow(symbol: "doc.text.viewfinder", title: "Foto de cupom, PIX ou boleto", subtitle: "Reconhece o texto da imagem no aparelho")
                    }
                    .buttonStyle(.plain).accessibilityIdentifier("scan.photo")
                    RowSeparator(inset: 56)
                    #endif
                    Button { mode = mode == .paste ? .choose : .paste } label: { ScanOptionRow(symbol: "text.alignleft", title: "Digitar ou colar o texto", subtitle: "Para quando você já copiou a linha digitável ou o comprovante") }
                        .buttonStyle(.plain).accessibilityIdentifier("scan.paste")
                }
                if mode == .paste { pasteEditor }
                if isWorking { ProgressView("Lendo…").accessibilityIdentifier("scan.working") }
            }
        }
    }

    private var pasteEditor: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            TextEditor(text: $pastedText)
                .frame(minHeight: 140)
                .padding(Space.sm)
                .scrollContentBackground(.hidden)
                .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                .noAutocapitalization()
                .accessibilityLabel("Texto do comprovante, endereço do QR Code ou linha digitável")
                .accessibilityIdentifier("scan.text")
            Button("Interpretar") { interpret(pastedText) }
                .buttonStyle(.primary)
                .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("scan.interpret")
        }
    }

    // MARK: Resultado

    private func result(_ s: ScanSummary) -> some View {
        VStack(alignment: .leading, spacing: Space.lg) {
            Text(s.title).font(.title3.weight(.semibold)).foregroundStyle(Color.textPrimary)
                .accessibilityAddTraits(.isHeader).accessibilityIdentifier("scan.result.title")
            if !s.rows.isEmpty {
                ListGroup {
                    ForEach(Array(s.rows.enumerated()), id: \.offset) { index, row in
                        ListRow(title: row.label, subtitle: row.value) { EmptyView() } trailing: { EmptyView() }
                            .accessibilityElement(children: .combine)
                            .accessibilityIdentifier(row.identifier)
                        if index < s.rows.count - 1 { RowSeparator() }
                    }
                }
            }
            ForEach(Array(s.warnings.enumerated()), id: \.offset) { _, w in
                Label(w, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(Color.warning)
                    .accessibilityIdentifier("scan.result.warning")
            }
            if let prefill = s.prefill {
                Button("Usar no lançamento") { stopCamera(); onUse(prefill); dismiss() }
                    .buttonStyle(.primary).accessibilityIdentifier("scan.use")
            }
            Button("Ler outro") { summary = nil; errorText = nil; mode = .choose; pastedText = "" }
                .buttonStyle(.secondary).accessibilityIdentifier("scan.again")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("scan.result")
    }

    // MARK: Ações

    private func interpret(_ text: String) {
        errorText = nil
        let outcome = store.interpretScan(text)
        var recorded = false
        if case .nfce(let qr) = outcome { recorded = store.isAlreadyRecorded(externalId: qr.externalId) }
        if case .receipt(let r) = outcome { recorded = store.isAlreadyRecorded(externalId: r.externalId) }
        summary = ScanSummaryBuilder.make(outcome, alreadyRecorded: recorded)
    }

    private func startCamera() async {
        #if canImport(AVFoundation) && os(iOS)
        errorText = nil
        if QRCaptureController.isDenied {
            errorText = "O acesso à câmera está desligado. Ative em Ajustes do iPhone > Finanças > Câmera."; return
        }
        if !QRCaptureController.isAuthorized, !(await QRCaptureController.requestAccess()) {
            errorText = "Sem permissão da câmera. Você ainda pode usar uma foto ou colar o texto."; return
        }
        do { try capture.configure() } catch {
            errorText = "Não foi possível abrir a câmera neste aparelho. Use uma foto ou cole o texto."; return
        }
        capture.onCode = { code in Task { @MainActor in stopCamera(); mode = .choose; interpret(code) } }
        mode = .camera
        capture.start()
        #endif
    }

    private func stopCamera() {
        #if canImport(AVFoundation)
        capture.stop()
        #endif
    }

    #if canImport(PhotosUI)
    private func recognize(_ item: PhotosPickerItem) async {
        errorText = nil; isWorking = true
        defer { isWorking = false; pickedPhoto = nil }
        #if canImport(Vision)
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else { errorText = "Não foi possível abrir a imagem."; return }
            let text = try await ReceiptTextRecognizer.recognize(imageData: data)
            interpret(text)
        } catch ReceiptTextRecognizer.RecognitionError.noText {
            errorText = "Não encontrei texto na imagem. Tente de novo com mais luz e o documento reto."
        } catch {
            errorText = "Não foi possível ler a imagem."
        }
        #else
        errorText = "O reconhecimento de texto não está disponível neste sistema."
        #endif
    }
    #endif
}

private struct ScanOptionRow: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        ListRow(title: title, subtitle: subtitle) {
            Image(systemName: symbol).foregroundStyle(Color.brandPrimary).frame(width: 28).accessibilityHidden(true)
        } trailing: {
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Color.textTertiary).accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}

#Preview("Ler nota") {
    ScanReceiptView { _ in }.previewing(PreviewData.demo)
}

#Preview("Ler nota, escuro") {
    ScanReceiptView { _ in }.previewing(PreviewData.demo, dark: true)
}
