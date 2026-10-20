import SwiftUI

/// Linha de lançamento (lista, painel de busca, fatura).
struct TransactionRow: View {
    let transaction: Transaction
    let lookup: FinanceLookup
    var showsDate = false

    var body: some View {
        let tx = transaction
        let category = tx.categoryId.flatMap { lookup.categories[$0] }
        ListRow(title: tx.title, subtitle: subtitle(category)) {
            icon(category)
        } trailing: {
            AmountText(transaction: tx)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func icon(_ category: Category?) -> some View {
        if transaction.isInvoicePayment {
            CategoryIcon(token: "transfer", symbol: "creditcard")
        } else if transaction.type == .transfer {
            CategoryIcon(token: "transfer", symbol: "arrow.left.arrow.right")
        } else {
            CategoryIcon(category: category, lookup: lookup)
        }
    }

    private func subtitle(_ category: Category?) -> String {
        var parts: [String] = []
        if showsDate { parts.append(DateText.dayMonthShort(transaction.date)) }
        if transaction.type == .transfer { parts.append(transaction.isInvoicePayment ? "Pagamento de fatura" : "Transferência") }
        else { parts.append(category?.name ?? "Sem categoria") }
        parts.append(lookup.accountLabel(of: transaction))
        if transaction.status == .pending { parts.append("Pendente") }
        if let tag = lookup.tagNames(of: transaction).first { parts.append("#\(tag)") }
        return parts.joined(separator: " · ")
    }
}

#Preview("Linhas de lançamento") {
    let store = PreviewData.demo
    ListGroup {
        ForEach(Array(store.transactions.sorted { $0.date > $1.date }.prefix(6))) { tx in
            TransactionRow(transaction: tx, lookup: store.lookup)
            RowSeparator(inset: 64)
        }
    }
    .padding()
    .background(Color.canvas)
}

#Preview("Linhas: negativo, valor grande, texto longo, oculto") {
    let long = Transaction(type: .expense, amount: dec("98765432.10"), date: PreviewData.today,
                           title: "Compra com um nome extremamente longo que precisa quebrar em duas linhas sem cortar o valor",
                           status: .pending)
    let refund = Transaction(type: .expense, amount: dec("-50"), date: PreviewData.today, title: "Estorno")
    let invoice = Transaction(type: .transfer, amount: dec("2104.77"), date: PreviewData.today, title: "Pagamento fatura", invoiceId: UUID())
    ListGroup {
        TransactionRow(transaction: long, lookup: FinanceLookup())
        RowSeparator(inset: 64)
        TransactionRow(transaction: refund, lookup: FinanceLookup())
        RowSeparator(inset: 64)
        TransactionRow(transaction: invoice, lookup: FinanceLookup()).environment(\.valuesHidden, true)
    }
    .padding()
    .background(Color.canvas)
    .preferredColorScheme(.dark)
}

#Preview("Linha vazia (lista sem lançamentos)") {
    ListGroup {
        EmptyState(symbol: "tray", title: "Nenhum lançamento")
    }
    .padding()
    .background(Color.canvas)
}
