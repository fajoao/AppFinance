import Foundation

// Fase 3: insights, leitura de QR/comprovante, Open Finance e Apple Watch. Regras no Core; aqui só a ligação com os dados.

extension AppStore {
    // MARK: Insights

    func insightsReport() -> InsightsReport {
        InsightsEngine.generate(transactions: scopedTransactions, categories: categories, liquidBalance: liquidBalance,
                                invoiceDues: invoiceDueItems(), today: today)
    }

    // MARK: QR da NFC-e e OCR

    func interpretScan(_ text: String) -> ScanOutcome { ScanInterpreter.interpret(text, today: today) }

    /// true se o documento (NFC-e, PIX) já foi lançado antes.
    func isAlreadyRecorded(externalId: String?) -> Bool {
        guard let externalId else { return false }
        return transactions.contains { $0.externalId == externalId }
    }

    /// Rascunho de novo lançamento já preenchido com o que foi lido.
    func makeDraft(applying prefill: ReceiptPrefill) -> TransactionDraft {
        var draft = makeDraft(type: prefill.type)
        let kind: CategoryKind = draft.type == .income ? .income : .expense
        draft.apply(prefill, today: today, suggester: suggester(for: draft.type)) { [lookup] in lookup.categories[$0]?.kind == kind }
        return draft
    }

    // MARK: Open Finance

    func importProviderTransactions(_ list: [Transaction]) throws {
        guard !list.isEmpty else { return }
        var items = list
        for i in items.indices { items[i].memberId = viewerId }
        try repository.saveAll(items)
        reload()
    }

    func setOpenFinanceEnabled(_ on: Bool) {
        updatePreferences {
            $0.openFinanceEnabled = on
            $0.openFinanceConsentAt = on ? today : nil
        }
    }

    // MARK: Apple Watch

    /// Processa uma despesa ditada no relógio. Idempotente (`externalId` "watch:<id>"). Devolve o resultado para o transporte.
    @discardableResult
    func addFromWatch(_ request: WatchQuickAddRequest) -> WatchQuickAddResult {
        let account = activeAccounts.first
        let result = WatchQuickAdd.process(request, existing: transactions, accountId: account?.id,
                                           categoryId: nil, memberId: viewerId, today: today)
        if case .created(var tx) = result {
            tx.categoryId = suggestCategory(for: tx.title, type: .expense)
            guard account != nil else { return .invalid("Cadastre uma conta no app antes de usar o relógio.") }
            if (try? repository.save(tx)) != nil { reload() } else { return .invalid("Não foi possível salvar.") }
            return .created(tx)
        }
        return result
    }
}
