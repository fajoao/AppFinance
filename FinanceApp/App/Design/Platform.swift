import SwiftUI

// Pequenos adaptadores para APIs que só existem no iOS. O alvo de produção é iOS 17+; os ramos `#else`
// existem apenas para que `scripts/typecheck-app.sh` consiga verificar a sintaxe com o SDK do macOS.

extension View {
    /// Título de navegação compacto.
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// Título grande (telas raiz).
    func largeNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.large)
        #else
        self
        #endif
    }

    func decimalKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.decimalPad)
        #else
        self
        #endif
    }

    /// Teclado numérico (PIN).
    func numberKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.numberPad)
        #else
        self
        #endif
    }

    func noAutocapitalization() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.never).autocorrectionDisabled()
        #else
        self
        #endif
    }

    func sentenceCapitalization() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.sentences)
        #else
        self
        #endif
    }

    /// Toque fora de campos de texto fecha o teclado (o teclado decimal não tem tecla de retorno).
    /// Usa um reconhecedor de toque do UIKit na janela, que ignora toques em campos de texto e controles e não cancela
    /// o toque. Duas versões com gestos do SwiftUI deram problema no iOS 26 (Xcode 26.4 beta): `simultaneousGesture` fazia o
    /// teclado fechar logo depois de focar o campo, e `onTapGesture` em `background` derrubava o app com SIGSEGV em
    /// `initializeWithCopy for AddGestureModifier` ao reavaliar a tela do PIN.
    func dismissesKeyboardOnTap() -> some View {
        #if os(iOS)
        background { KeyboardTapDismisser() }
        #else
        self
        #endif
    }

    /// Esconde o fundo padrão de rolagem para mostrar `canvas`.
    func canvasBackground() -> some View {
        background(Color.canvas.ignoresSafeArea())
    }
}

extension ToolbarItemPlacement {
    static var trailingBar: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .automatic
        #endif
    }
    static var leadingBar: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .automatic
        #endif
    }
}

enum Haptics {
    @MainActor static func success() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }
    @MainActor static func tap() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

/// Imagem a partir de bytes (comprovantes). UIKit no iOS, AppKit no macOS (só typecheck).
struct DataImage: View {
    let data: Data
    var body: some View {
        #if canImport(UIKit)
        if let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit() } else { placeholder }
        #elseif canImport(AppKit)
        if let image = NSImage(data: data) { Image(nsImage: image).resizable().scaledToFit() } else { placeholder }
        #else
        placeholder
        #endif
    }
    private var placeholder: some View { Image(systemName: "photo").foregroundStyle(Color.textTertiary) }
}

#if os(iOS)
/// Instala (enquanto a tela está visível) um `UITapGestureRecognizer` na janela que fecha o teclado.
private struct KeyboardTapDismisser: UIViewRepresentable {
    func makeUIView(context: Context) -> Anchor { Anchor() }
    func updateUIView(_ uiView: Anchor, context: Context) {}

    final class Anchor: UIView, UIGestureRecognizerDelegate {
        private lazy var recognizer: UITapGestureRecognizer = {
            let r = UITapGestureRecognizer(target: self, action: #selector(handleTap))
            r.cancelsTouchesInView = false
            r.delegate = self
            return r
        }()
        private weak var host: UIWindow?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) não é usado") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            host?.removeGestureRecognizer(recognizer)
            host = window
            window?.addGestureRecognizer(recognizer)
        }

        @objc private func handleTap() { window?.endEditing(true) }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let v = view {
                if v is UITextField || v is UITextView || v is UIControl { return false }
                view = v.superview
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}
#endif
