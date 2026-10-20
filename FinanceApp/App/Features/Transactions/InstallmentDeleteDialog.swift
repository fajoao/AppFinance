import SwiftUI

/// Pergunta o escopo ao excluir uma parcela: só esta, esta e as seguintes, ou todas.
struct InstallmentDeleteDialog: ViewModifier {
    @Environment(AppStore.self) private var store
    @Binding var transaction: Transaction?
    var onDeleted: () -> Void = {}

    func body(content: Content) -> some View {
        content.confirmationDialog(
            title, isPresented: Binding(get: { transaction != nil }, set: { if !$0 { transaction = nil } }), titleVisibility: .visible
        ) {
            if let tx = transaction {
                ForEach(InstallmentScope.allCases, id: \.self) { scope in
                    Button(scope.displayName, role: .destructive) {
                        if store.attempt({ try store.deleteInstallments(of: tx.id, scope: scope) }) { onDeleted() }
                        transaction = nil
                    }
                }
            }
        } message: {
            if let tx = transaction, let info = tx.installment {
                Text("Parcela \(info.label) de um parcelamento com \(store.installmentCount(of: tx.id)) parcelas.")
            }
        }
    }

    private var title: String { "Excluir parcelas" }
}

extension View {
    func installmentDeleteDialog(for transaction: Binding<Transaction?>, onDeleted: @escaping () -> Void = {}) -> some View {
        modifier(InstallmentDeleteDialog(transaction: transaction, onDeleted: onDeleted))
    }
}
