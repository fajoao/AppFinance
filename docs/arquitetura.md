# Arquitetura da solução (diagramas Mermaid)

A arquitetura formal, no **modelo C4**, está em [`docs/arquitetura/`](arquitetura/README.md). Os diagramas abaixo complementam com visões que o C4 não cobre (modelo de dados, sincronização, fatura de cartão, pipeline de testes). O desenho editável está em
[`docs/arquitetura/arquitetura-solucao.drawio`](arquitetura/arquitetura-solucao.drawio) (abra em [app.diagrams.net](https://app.diagrams.net)).

**Legenda:** linha cheia = existe e foi testado; linha tracejada = planejado ou ainda não ligado.

## 1. Visão geral da solução

```mermaid
flowchart LR
  subgraph Clientes
    iOS["App iOS<br>SwiftUI + Core Swift"]
    Widgets["Widgets<br>WidgetKit"]
    Watch["Apple Watch<br>app + complicação"]
    Web["Versão web<br>React + TypeScript"]
    Proto["Protótipo HTML<br>design e validação"]
  end

  subgraph Borda["Borda (Docker no Mac)"]
    Tunnel(["Cloudflare Tunnel<br>HTTPS público"])
    Nginx["nginx<br>estáticos + proxy /api"]
  end

  subgraph Backend["Backend (Docker)"]
    API["API Fastify 5<br>JWT + argon2id"]
    DB[("Postgres 16<br>records JSONB")]
  end

  subgraph Dev["Ferramentas de desenvolvimento"]
    XcodeGen["XcodeGen<br>gera o projeto Xcode"]
    Compose["Docker Compose<br>sobe db, api, web, túnel"]
    Monitor["Painel de agentes<br>Monitor/"]
    DrawioMCP["draw.io MCP"]
    GitHub["GitHub<br>fajoao/AppFinance"]
  end

  subgraph Futuro["Planejado / não ligado"]
    CloudKit["CloudKit<br>sincronização Apple"]
    OpenFin["Open Finance<br>provedor real"]
    SEFAZ["Consulta SEFAZ<br>NFC-e"]
    Zap["Agente WhatsApp<br>Claude + ferramentas"]
  end

  iOS -- "App Group" --> Widgets
  iOS -- "WatchConnectivity" --> Watch
  Web --> Nginx
  Nginx -- "/api" --> API
  Tunnel --> API
  API --> DB
  iOS -. "sync (ainda não ligado)" .-> Tunnel
  iOS -. "desligado por padrão" .-> CloudKit
  iOS -. "mock apenas" .-> OpenFin
  iOS -. "protocolo sem implementação" .-> SEFAZ
  Zap -.-> API
  Proto -. "referência visual" .-> iOS
  Proto -. "referência visual" .-> Web
```

## 2. Camadas do app iOS

```mermaid
flowchart TB
  subgraph UI["Camada de interface (SwiftUI)"]
    Features["Features<br>Home, Lançamentos, Plan, Wallet,<br>Investments, Reports, Family,<br>Insights, Scan, Settings"]
    Components["Design/Components<br>SplitAmount, MonthPicker, RefreshButton"]
    Router["Router<br>abas, seções, folhas"]
  end

  subgraph Estado["Estado e lógica de tela (sem SwiftUI)"]
    Store["AppStore @Observable<br>+ Family, Money, Security, Refresh"]
    Logic["Logic<br>TransactionDraft, TransactionFilter,<br>PayInvoiceModel, DashboardModel,<br>PeriodSelection, PinLock"]
    Prefs["AppPreferences<br>UserDefaults"]
  end

  subgraph Servicos["Services (APIs do sistema)"]
    Bio["BiometricAuth<br>Face ID"]
    Notif["UserNotifications<br>lembretes"]
    Keychain["KeychainSecrets<br>PIN"]
    WPub["WidgetPublisher<br>App Group"]
    PDF["ReportPDF<br>ImageRenderer"]
    Scan["QRCodeScanner + Vision<br>NFC-e e OCR"]
    Intent["QuickAddIntent<br>Siri"]
  end

  subgraph Core["Core (Swift puro, Decimal, sem UI)"]
    Engines["Motores<br>Balance, Installment, Recurrence,<br>CreditCard, Budget, Summary, CashFlow,<br>Debt, Goal, Family, Splitting,<br>Investments, Reports, Insights"]
    Import["Importing<br>OFX, CSV, Boleto, NFC-e, ReceiptText"]
    Sync["Sync<br>SyncEngine, SyncCoordinator"]
    Repo["Repository<br>JSONFileStore, InMemoryStore"]
  end

  Disk[("data.json<br>Application Support")]

  Features --> Components
  Features --> Router
  Features --> Store
  Store --> Logic
  Store --> Prefs
  Store --> Servicos
  Logic --> Engines
  Store --> Engines
  Store --> Import
  Store --> Repo
  Store -. "desligado" .-> Sync
  Repo --> Disk
```

## 3. Modelo de dados do Core

```mermaid
erDiagram
  HOUSEHOLD ||--o{ FAMILYMEMBER : tem
  HOUSEHOLD ||--o{ ACCOUNT : possui
  ACCOUNT ||--o{ TRANSACTION : movimenta
  CATEGORY ||--o{ TRANSACTION : classifica
  CATEGORY ||--o{ CATEGORY : "subcategoria"
  CATEGORY ||--o{ BUDGET : "orcamento mensal"
  CREDITCARD ||--o{ TRANSACTION : "compra"
  CREDITCARD ||--o{ INVOICE : fatura
  ACCOUNT ||--o{ INVOICE : "paga fatura"
  GOAL ||--o{ GOALCONTRIBUTION : aportes
  FAMILYMEMBER ||--o{ TRANSACTION : "atribuida a"
  FAMILYMEMBER ||--o{ ALLOWANCE : mesada
  FAMILYMEMBER ||--o{ APPROVALREQUEST : pedidos
  EXPENSESPLIT ||--o{ SPLITSETTLEMENT : acerto
  TRANSACTION }o--o{ TAG : "etiquetas"

  ACCOUNT {
    uuid id PK
    string name
    string type
    decimal initialBalance
    string visibility
  }
  TRANSACTION {
    uuid id PK
    string type
    decimal amount
    date date
    string status
    uuid accountId FK
    uuid categoryId FK
    uuid creditCardId FK
    uuid invoiceId FK
    string externalId
  }
  CREDITCARD {
    uuid id PK
    decimal limit
    int closingDay
    int dueDay
  }
  INVOICE {
    uuid id PK
    string month
    date closingDate
    date dueDate
    decimal paidAmount
  }
  BUDGET {
    uuid id PK
    string month
    decimal limit
  }
  GOAL {
    uuid id PK
    decimal targetAmount
    decimal currentAmount
    date deadline
  }
  DEBT {
    uuid id PK
    decimal balance
    decimal monthlyInterestRate
    decimal minimumPayment
  }
  INVESTMENT {
    uuid id PK
    string assetClass
    decimal quantity
    decimal averagePrice
  }
```

## 4. Modelo de dados do banco (Postgres)

```mermaid
erDiagram
  USERS ||--o{ MEMBERSHIPS : participa
  HOUSEHOLDS ||--o{ MEMBERSHIPS : agrupa
  HOUSEHOLDS ||--o{ RECORDS : guarda
  HOUSEHOLDS ||--o{ INVITES : convida
  USERS ||--o{ REFRESH_TOKENS : sessoes
  USERS ||--o{ AUDIT_LOG : "gerou"
  HOUSEHOLDS ||--o{ AUDIT_LOG : registra

  USERS {
    uuid id PK
    string email UK
    string password_hash "argon2id"
  }
  MEMBERSHIPS {
    uuid user_id FK
    uuid household_id FK
    string role "admin, member, dependent"
  }
  RECORDS {
    uuid household_id PK
    string type PK
    uuid id PK
    jsonb data
    timestamptz updated_at
    boolean deleted
    uuid owner_id
    bigint server_seq "token de sincronizacao"
  }
  INVITES {
    uuid household_id FK
    string code_hash
    timestamptz expires_at
  }
  REFRESH_TOKENS {
    uuid user_id FK
    string token_hash
    boolean revoked
  }
  AUDIT_LOG {
    bigint id PK
    string action
    jsonb meta
  }
```

## 5. Sincronização (push e pull)

```mermaid
sequenceDiagram
  autonumber
  participant C as Cliente (iOS ou Web)
  participant A as API Fastify
  participant D as Postgres

  C->>A: POST /api/auth/login
  A->>D: confere argon2id e bloqueio progressivo
  A-->>C: accessToken (15 min) + refreshToken

  C->>A: POST /api/sync (registros alterados)
  A->>D: trava o household e aplica a regra de conflito
  Note over A,D: maior updatedAt vence<br>empate: exclusão vence<br>empate restante: JSON canônico
  D-->>A: aceitos e rejeitados (com serverRecord)
  A-->>C: accepted, rejected, token

  C->>A: GET /api/sync?since=N
  A->>D: server_seq maior que N
  D-->>A: registros novos
  A-->>C: records, token, hasMore
  Note over C: guarda o token do GET<br>para o próximo since
```

## 6. Compra no cartão e pagamento da fatura

```mermaid
flowchart TD
  A["Compra no cartão<br>valor e data"] --> B{"Data é menor que<br>o dia de fechamento?"}
  B -- "sim" --> C["Entra na fatura do mês"]
  B -- "não (no dia ou depois)" --> D["Entra na fatura seguinte"]
  C --> E["Reduz o limite disponível<br>não mexe no saldo da conta"]
  D --> E
  E --> F["Parcelado?<br>divide em centavos<br>1ª parcela absorve o resto"]
  F --> G["Fatura fecha e vence<br>conforme dueDay"]
  G --> H{"Pagamento"}
  H -- "total ou parcial" --> I["Transferência sem destino<br>com invoiceId"]
  I --> J["Reduz o saldo da conta<br>libera limite<br>não conta como despesa"]
```

```mermaid
stateDiagram-v2
  [*] --> Aberta
  Aberta --> Fechada : passa o dia de fechamento
  Fechada --> Paga : pagamento igual ao total
  Fechada --> ParcialmentePaga : pagamento parcial
  ParcialmentePaga --> Paga : quitação do restante
  Fechada --> Vencida : passa o vencimento sem pagar
  ParcialmentePaga --> Vencida : passa o vencimento
  Vencida --> Paga : pagamento
  Paga --> [*]
```

## 7. Implantação com Docker Compose

```mermaid
flowchart LR
  Internet(("Internet"))

  subgraph Host["Mac (Docker Desktop)"]
    subgraph edge["rede edge"]
      cf["tunnel<br>cloudflared"]
      web["web<br>nginx:alpine<br>127.0.0.1:8080"]
      api["api<br>Node 22 + Fastify<br>127.0.0.1:3000"]
    end
    subgraph backend["rede backend"]
      db[("db<br>postgres:16-alpine<br>127.0.0.1:5433")]
    end
    vol[("volume pgdata")]
  end

  Internet -- "HTTPS" --> cf
  cf -- "http://api:3000" --> api
  web -- "proxy /api" --> api
  api -- "5432 interno" --> db
  db --- vol
  Internet -. "bloqueado: sem porta aberta" .-x db
```

## 8. Pipeline de verificação

```mermaid
flowchart LR
  subgraph Swift["iOS e Core (Swift)"]
    T1["test-core.sh<br>259 testes<br>swiftc"]
    T2["test-app.sh<br>126 testes<br>swiftc"]
    T3["typecheck-app.sh<br>SDK macOS e watchOS"]
    T4["xcodebuild<br>Simulador iPhone 12"]
    T5["XCUITest<br>33 testes"]
  end

  subgraph WebT["Web (TypeScript, em Docker)"]
    V1["vitest<br>388 testes"]
    V2["vetores dourados<br>365, gerados do Core Swift"]
    V3["e2e Playwright<br>18 testes"]
  end

  subgraph ApiT["API (Docker + Postgres real)"]
    A1["integração<br>27 testes"]
  end

  Core["FinanceApp/Core"] --> T1
  Core --> T2
  Core --> T3
  T3 --> T4
  T4 --> T5
  Core -- "gera" --> V2
  V2 --> V1
  V1 --> V3
  A1 --> V3
```

## 9. Agente por WhatsApp (planejado)

Ainda não existe. O desenho abaixo é a recomendação para a próxima etapa, depois que o app iOS sincronizar com a API.

```mermaid
flowchart LR
  User(["Você no WhatsApp"]) --> Meta["WhatsApp Cloud API<br>Meta"]
  Meta -- "webhook" --> Srv["Servidor do agente"]
  Srv --> LLM["Modelo Claude<br>com ferramentas"]
  LLM -- "registrar_despesa<br>consultar_saldo<br>resumo_do_mes" --> Tools["Ferramentas<br>(regras do Core)"]
  Tools --> API["API Fastify"]
  API --> DB[("Postgres")]
  Srv -- "confirmação antes de gravar" --> User
  Allow["Lista de números autorizados<br>+ PIN para ações sensíveis"] -.-> Srv
```
