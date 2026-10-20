# Diagrama ER - App Finanças

Modelo de dados do Core (`FinanceApp/Core/Models.swift`). Todas as entidades têm `id` (UUID), `createdAt`, `updatedAt` e `ownerId` (UUID opcional, reservado para multiusuário/CloudKit). Dinheiro é sempre `Decimal` (no SwiftData/CloudKit, armazenar como `Decimal` ou inteiro em centavos).

```mermaid
erDiagram
    HOUSEHOLD ||--o{ FAMILY_MEMBER : "tem"
    FAMILY_MEMBER ||--o{ TRANSACTION : "responsável (memberId)"

    ACCOUNT ||--o{ TRANSACTION : "origem (accountId)"
    ACCOUNT ||--o{ TRANSACTION : "destino de transferência (destinationAccountId)"
    ACCOUNT ||--o{ CREDIT_CARD : "paga a fatura (paymentAccountId)"

    CATEGORY ||--o{ CATEGORY : "subcategoria (parentId)"
    CATEGORY ||--o{ TRANSACTION : "classifica (categoryId)"
    CATEGORY ||--o{ BUDGET : "orçamento mensal"

    TAG }o--o{ TRANSACTION : "tagIds"

    CREDIT_CARD ||--o{ INVOICE : "tem faturas"
    CREDIT_CARD ||--o{ TRANSACTION : "compras (creditCardId)"
    INVOICE ||--o{ TRANSACTION : "pagamentos (invoiceId)"

    TRANSACTION ||--o{ TRANSACTION : "ocorrências (recurrenceParentId)"

    ACCOUNT {
        uuid id PK
        string name
        enum type "checking|savings|wallet|investment"
        decimal initialBalance
        string currency "BRL"
        bool isArchived
        uuid ownerId "opcional"
        date createdAt
        date updatedAt
    }
    CATEGORY {
        uuid id PK
        string name
        enum kind "income|expense"
        uuid parentId FK "opcional"
        string icon
        string colorHex
        uuid ownerId
        date createdAt
        date updatedAt
    }
    TAG {
        uuid id PK
        string name
        uuid ownerId
        date createdAt
        date updatedAt
    }
    TRANSACTION {
        uuid id PK
        enum type "income|expense|transfer"
        decimal amount "magnitude; negativo = estorno"
        date date "dia civil"
        string title
        enum status "pending|paid"
        uuid accountId FK "nulo em compra de cartão"
        uuid destinationAccountId FK "só transferência"
        uuid categoryId FK
        uuid[] tagIds
        uuid creditCardId FK "compra: sem invoiceId"
        uuid invoiceId FK "pagamento de fatura"
        json installment "number,total,groupId"
        json recurrence "frequency,interval,endDate,maxOccurrences"
        uuid recurrenceParentId FK
        string attachmentPath
        string note
        string externalId "FITID OFX"
        uuid memberId FK
        uuid ownerId
        date createdAt
        date updatedAt
    }
    CREDIT_CARD {
        uuid id PK
        string name
        decimal limit
        int closingDay
        int dueDay
        uuid paymentAccountId FK
        bool isArchived
        uuid ownerId
        date createdAt
        date updatedAt
    }
    INVOICE {
        uuid id PK
        uuid cardId FK
        int monthYear "mês do fechamento"
        int monthMonth
        date closingDate
        date dueDate
        decimal paidAmount
        date paidAt
        uuid paymentAccountId FK
        uuid ownerId
        date createdAt
        date updatedAt
    }
    BUDGET {
        uuid id PK
        uuid categoryId FK
        int monthYear
        int monthMonth
        decimal limit
        uuid ownerId
        date createdAt
        date updatedAt
    }
    GOAL {
        uuid id PK
        string name
        decimal targetAmount
        decimal currentAmount
        date deadline
        uuid ownerId
        date createdAt
        date updatedAt
    }
    DEBT {
        uuid id PK
        string name
        decimal balance
        decimal monthlyInterestRate "fração: 0.02 = 2%"
        decimal minimumPayment
        int dueDay
        uuid ownerId
        date createdAt
        date updatedAt
    }
    HOUSEHOLD {
        uuid id PK
        string name
        uuid ownerId
        date createdAt
        date updatedAt
    }
    FAMILY_MEMBER {
        uuid id PK
        uuid householdId FK
        string name
        enum role "admin|member|dependent"
        string email
        uuid ownerId
        date createdAt
        date updatedAt
    }
```

## Regras de modelagem

- **Fatura**: `Invoice` só é persistida quando há pagamento. O total vem das compras do cartão cujo `date` cai no ciclo (compra no dia do fechamento ou depois vai para a fatura seguinte). `monthYear/monthMonth` representam o mês de **fechamento** (`YearMonth` no código).
- **Compra no cartão**: `Transaction` com `creditCardId` e sem `invoiceId`; não altera saldo de conta, consome limite.
- **Pagamento de fatura**: `Transaction` do tipo `transfer` com `accountId` (conta pagadora), sem `destinationAccountId`, com `creditCardId` e `invoiceId`. Reduz o saldo da conta, libera limite e não conta como despesa nos relatórios.
- **Transferência entre contas**: `type = transfer` com `accountId` e `destinationAccountId`; não entra em receitas/despesas.
- **Parcelas**: cada parcela é uma `Transaction` própria; `installment.groupId` une as parcelas da mesma compra. A última absorve o resto de centavos.
- **Recorrência**: o lançamento modelo guarda `recurrence`; as ocorrências geradas apontam para ele por `recurrenceParentId`.
- **Importação**: `externalId` (FITID do OFX) evita duplicar lançamentos.
- **Sincronização futura**: ids UUID, `updatedAt` para resolução de conflitos (último vence) e `ownerId` para multiusuário/CloudKit.
- **Persistência atual**: `FinanceSnapshot` (JSON, `JSONFileStore`) com um array por entidade.


## Fase 2 (v1): novas entidades e campos

Definidos em `FinanceApp/Core/Models.swift` (campos novos) e `FinanceApp/Core/ModelsPhase2.swift` (entidades novas).
Arquivos antigos continuam válidos: `FinanceSnapshot` e os modelos alterados decodificam com valores padrão quando faltam campos.

```mermaid
erDiagram
    FAMILY_MEMBER ||--o{ ACCOUNT : "dono (ownerId)"
    FAMILY_MEMBER ||--o{ CATEGORY : "dono (ownerId)"
    FAMILY_MEMBER ||--o{ GOAL : "meta de filho (memberId)"
    FAMILY_MEMBER ||--o{ ALLOWANCE : "recebe mesada"
    FAMILY_MEMBER ||--o{ APPROVAL_REQUEST : "pede aprovação"
    FAMILY_MEMBER ||--o{ EXPENSE_SPLIT : "pagou (paidBy)"
    GOAL ||--o{ GOAL_CONTRIBUTION : "histórico de aportes"
    ACCOUNT ||--o{ ALLOWANCE : "origem e destino"
    EXPENSE_SPLIT }o--o| TRANSACTION : "transactionId opcional"
    SPLIT_SETTLEMENT }o--|| FAMILY_MEMBER : "de (fromMemberId)"
    SPLIT_SETTLEMENT }o--|| FAMILY_MEMBER : "para (toMemberId)"

    ACCOUNT {
        enum visibility "shared|private (novo)"
    }
    CATEGORY {
        enum visibility "shared|private (novo)"
        enum taxKind "health|education, opcional (novo)"
    }
    GOAL {
        uuid memberId FK "opcional (novo)"
    }
    FAMILY_MEMBER {
        decimal monthlySpendingLimit "dependente, opcional (novo)"
    }
    GOAL_CONTRIBUTION {
        uuid id PK
        uuid goalId FK
        decimal amount "negativo = retirada"
        date date
        uuid accountId FK "opcional"
        uuid transactionId FK "saída gerada"
    }
    INVESTMENT {
        uuid id PK
        string name
        string ticker
        enum assetClass "fixedIncome|stock|reit|crypto"
        decimal quantity
        decimal averagePrice
        decimal quote "cotação manual"
        date quoteDate
        decimal realizedProfit
        uuid memberId FK
    }
    NET_WORTH_SNAPSHOT {
        uuid id PK
        int monthYear
        int monthMonth
        decimal assets
        decimal liabilities
    }
    EXPENSE_SPLIT {
        uuid id PK
        string title
        decimal total
        date date
        uuid paidBy FK
        enum mode "equal|percentage"
        json shares "memberId,percent,amount"
        uuid transactionId FK
    }
    SPLIT_SETTLEMENT {
        uuid id PK
        uuid fromMemberId FK
        uuid toMemberId FK
        decimal amount
        date date
    }
    ALLOWANCE {
        uuid id PK
        uuid memberId FK
        decimal amount
        int dayOfMonth
        uuid fromAccountId FK
        uuid toAccountId FK
        int startMonth
        int lastPaidMonth
        bool isActive
    }
    APPROVAL_REQUEST {
        uuid id PK
        uuid memberId FK
        string title
        decimal amount
        date date
        enum status "pending|approved|rejected"
        uuid decidedBy FK
        uuid transactionId FK
    }
    TOMBSTONE {
        uuid id PK
        string entityType
        uuid entityId
        date deletedAt
    }
```

Regras:
- **Privacidade**: `visibility = private` + `ownerId` = membro dono. Só o dono enxerga, em qualquer visão. Itens sem dono e compartilhados valem para todos.
- **Aporte em meta**: `GoalContribution` registra o aporte; a saída da conta é um `Transaction` do tipo transferência sem destino (`transactionId` liga os dois para desfazer juntos).
- **Divisão de despesas**: saldo de cada membro = o que pagou − a sua parte, ajustado pelos `SplitSettlement`. O acerto minimiza transferências.
- **Mesada**: gera transferências `Transaction` (origem → conta do dependente) com `memberId` do dependente; `lastPaidMonth` evita pagar duas vezes.
- **Patrimônio**: um `NetWorthSnapshot` por mês (o mais recente substitui). Passivos = dívidas + limite usado dos cartões + saldos negativos de contas.
- **Sincronização**: `Tombstone` registra exclusões para o merge por `updatedAt`; `FinanceSnapshot.version` passa a 2.
