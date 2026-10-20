# App Finanças (iOS)

App iOS nativo de finanças pessoais e familiares para o Brasil: BRL, pt-BR, cartão com fatura e fechamento, orçamento, contas a pagar, metas, dívidas, investimentos, patrimônio, família, relatórios e IR, importação OFX/CSV. Swift 6, SwiftUI, iOS 17+, dados locais por padrão.

Fase atual: **Fase 3 (v2)** sobre as Fases 1 e 2. Plano completo em `../docs/prds/app-financas-v1.0-prd.md`; design em `../Design/` (tokens, telas do MVP e da Fase 2 em `screens.md`) e protótipo navegável do MVP em `../Prototype/index.html`.

> **Honestidade sobre a verificação.** As Fases 1 e 2 foram escritas sem Xcode. Agora há Xcode 26.4 beta, SDK e Simulador iOS 26.4 neste ambiente, e a Fase 3 foi **compilada com `xcodebuild` e testada no Simulador (iPhone 12)**:
> `BUILD SUCCEEDED` com `project-free.yml` e com `project.yml` (widgets), e **31 XCUITests passando** (veja "Testes").
> **Continua NÃO verificado:** aparelho físico, câmera real (QR) e Vision com fotos reais, WatchConnectivity e o app do relógio rodando (o runtime watchOS não está instalado; só checagem de tipos contra o SDK), widgets/Siri em execução,
> CloudKit, Open Finance com provedor real (não existe), notificações, Face ID, PhotosPicker e PDF no iOS, Dynamic Type/VoiceOver nas telas novas.

## Fase 3 (v2): o que há e o que NÃO foi verificado

| Área | Onde | Estado |
|---|---|---|
| Insights locais (atípicos, previsão do saldo, assinaturas, economia, risco de saldo negativo), sem IA nem servidor | `Core/Insights.swift`, `App/Features/Insights/` (Planejar > Mais > Insights; cartão no Início) | Regras testadas; tela no simulador (UITests) |
| QR da NFC-e (chave de 44 dígitos, DV, UF, CNPJ, valor em contingência) | `Core/NFCe.swift`, `App/Services/QRCodeScanner.swift`, `App/Features/Scan/` | Parser testado; **câmera nunca testada em aparelho** |
| Consulta à SEFAZ | `NFCeLookupService` (só protocolo) | **Não implementada de propósito** (`docs/ocr-nfce.md`) |
| OCR de cupom, PIX e boleto (valor, data, estabelecimento; linha digitável com DV) | `Core/ReceiptText.swift`, `Core/Boleto.swift`, `App/Services/ReceiptTextRecognizer.swift` (Vision) | Texto testado; **Vision com fotos reais não testado** |
| Open Finance | `Core/OpenFinance.swift`, `App/Features/Settings/OpenFinanceView.swift`, `docs/open-finance.md` | Contrato, mapeamento e mock testados; **sem provedor real; desligado por padrão** |
| Apple Watch (saldo, gasto do dia, despesa por ditado, complicação) | `Watch/`, `Core/WatchLink.swift`, `App/Services/WatchConnectivityBridge.swift`, alvos `FinanceWatch*` no `project.yml` | Lógica testada; código checado por tipos no SDK watchOS; **não executado** (sem runtime do watchOS); fora do `project-free.yml` |

Launch arguments novos: `-mockOpenFinance` e `-startScreen insights|scan|settings.openfinance`. Permissão nova: `NSCameraUsageDescription` (só leitura de QR).
Para embutir o relógio no app do iPhone, descomente a dependência `FinanceWatch` em `project.yml` (exige o runtime watchOS no Xcode e App Groups).

## Seletor de mês e ano e atualizar (adicionados depois)

- **Período global:** `AppStore.viewedMonth` (não persistido; volta ao mês de hoje ao reabrir) + componente `MonthPicker` (`App/Design/Components/MonthPicker.swift`: ‹ ›, título que abre a sheet com grade 3x4 de meses e ano, "Hoje", chip "Voltar para hoje"). Regras em `App/Logic/PeriodSelection.swift` (limites 01/2000 a 12/2100, navegação, textos pt-BR). `currentMonth` continua sendo o "agora" (patrimônio, mesada, alertas de orçamento). Segue o mês visualizado: Início, Lançamentos (período padrão), Orçamento (inclui editar/copiar), A pagar, fatura do cartão e Relatórios; a tabela completa está em `../Design/screens.md`. Ids: `period.picker`, `period.prev`, `period.next`, `period.backToToday`, `period.sheet`, `period.today`, `period.month.N`, `period.year`.
- **Atualizar:** `AppStore.refresh()` (`App/Store/AppStore+Refresh.swift`), botão `refresh.button` na barra de Início/Lançamentos/Planejar/Carteira e `.refreshable` nas telas rolável principais.
- Capturas reais do Simulador em `../docs/screenshots/period/` (claro e escuro). Correção do puxar para atualizar (seletor dentro da rolagem; rajadas antes/depois em `../docs/screenshots/refresh-bug/`), com `testRefreshPullKeepsEveryScreenClean` cobrindo as 14 telas.
- **Verificação:** `scripts/test-app.sh` 125 testes, `scripts/test-core.sh` 259, `scripts/typecheck-app.sh` OK, e a suíte XCUITest inteira (31 testes, incluindo 3 do seletor e 2 de atualizar) passou no iPhone 12 (iOS 26.4). **Não verificado:** VoiceOver e Dynamic Type grande no seletor em execução, aparelho físico, `project.yml` (widgets) compilado após estas mudanças (só `project-free.yml`).

## Estrutura

```
FinanceApp/
  Core/        Regras financeiras puras (Decimal): saldos, parcelas, recorrência, fatura de cartão, orçamento,
               metas (edição, histórico, projeção), dívidas, família (papéis, privacidade, aprovação, mesada),
               divisão de despesas e acerto, investimentos e patrimônio, relatórios e IR, sincronização (contrato,
               conflito por updatedAt, coordenador), dados dos widgets e atalho de voz, importação OFX/CSV,
               exportação CSV, persistência (Repository/JSONFileStore). Sem UI.
  CoreTests/   185 testes do Core (runner swiftc, sem Xcode)
  App/
    Logic/     Lógica de tela testável, sem SwiftUI: MoneyDisplay (sinais, máscara, "por extenso"), AmountKeypad,
               TransactionFilter, TransactionDraft (novo e edição), Bills/Lembretes, PayInvoiceModel, DashboardModel,
               LaunchOptions, Forms (dívida, meta, investimento, divisão, mesada), PlanningModels (simulador, fluxo de
               caixa, períodos), PinLock, AttachmentStorage, Formatting, Ports (protocolos de widgets e segredos)
    Store/     AppStore (@Observable) + extensões (Family, Money, Security), preferências, DemoSeed, AppBootstrap, ImportPreview
    Services/  BiometricAuth, UserNotifications, KeychainSecrets, WidgetPublisher (App Group + WidgetKit), ReportPDF
               (ImageRenderer), CloudKitSyncService (#if canImport(CloudKit), desligado), QuickAddIntent (App Intents)
    Design/    Tokens (cores do Asset Catalog, Space, Radius), Platform (shims iOS), Components/ (SplitAmount, ...)
    Features/  Onboarding, Auth, Home, Transactions, Plan (Orçamento/A pagar/Metas/Mais, Dívidas, Fluxo de caixa),
               Wallet (Contas/Cartões), Investments (carteira, patrimônio), Reports (relatórios, IR, categorias),
               Family (grupo, divisão, mesada, aprovações), Settings (PIN, sincronização)
    Preview/   Dados para #Preview
  Widgets/     Extensão WidgetKit (saldo, gastos do dia, próximo vencimento). Lê o resumo gravado no App Group
  AppTests/    Testes de lógica do app (Cases/ + Runner/main.swift p/ swiftc + XCTestBridge p/ Xcode)
  UITests/     XCUITest dos fluxos críticos e da Fase 2 (com capturas de tela anexadas)
  Assets/      Assets.xcassets (31 Color Sets claro/escuro gerados de Design/tokens.json), Info.plist,
               PrivacyInfo.xcprivacy, pt-BR.lproj
  scripts/     test-core.sh, test-app.sh, typecheck-app.sh, gen-colorsets.py, render-macos.sh,
               capture-screenshots.sh, extract-screenshots.sh
  project.yml  XcodeGen (alvos FinanceApp, FinanceWidgets, FinanceAppTests, FinanceAppUITests)
```

`Core` e `App` compilam no mesmo módulo (`FinanceApp`); a extensão `FinanceWidgets` compila `Core` + `Widgets` à parte. `App/Logic` e `App/Store` não importam SwiftUI: é isso que permite testá-los só com `swiftc`.

## Pré-requisitos

- macOS com **Xcode 16+** (Swift 6, iOS 17 SDK) para compilar e rodar no Simulador.
- `brew install xcodegen`
- Opcional para o VS Code: `brew install xcode-build-server xcbeautify swiftformat` e a extensão SweetPad.

Só com as Command Line Tools (sem Xcode) dá para rodar os testes de lógica, o typecheck e a renderização aproximada no macOS (abaixo). Não dá para compilar o app para iOS.

## Gerar o projeto e rodar

```bash
brew install xcodegen
cd FinanceApp
xcodegen            # cria FinanceApp.xcodeproj (artefato gerado; está no .gitignore)
open FinanceApp.xcodeproj
```

No Xcode, escolha o esquema **FinanceApp**, um iPhone com iOS 17+ e Run (⌘R). Para rodar em aparelho real, defina `DEVELOPMENT_TEAM` em `project.yml` (linha comentada) ou escolha o Team em Signing & Capabilities.

### Pela linha de comando (Simulador)

```bash
# build
xcodebuild -project FinanceApp.xcodeproj -scheme FinanceApp \
  -destination 'platform=iOS Simulator,name=iPhone 16' -derivedDataPath ../build build

# boot, instalar e abrir com dados de demonstração
xcrun simctl boot "iPhone 16" || true; open -a Simulator
xcrun simctl install booted ../build/Build/Products/Debug-iphonesimulator/FinanceApp.app
xcrun simctl launch --terminate-running-process booted com.example.financas -uiTesting -seedDemo -fixedToday 2026-10-19
```

### Launch arguments (testes de UI e capturas)

| Argumento | Efeito |
|---|---|
| `-seedDemo` | Carrega os dados de demonstração (espelham o protótipo, mais dívidas, carteira e histórico de metas) e pula o onboarding |
| `-seedFamily` | Como `-seedDemo`, mais o grupo familiar de demonstração: Ana (admin), Bruno (membro), Caio (dependente, limite R$ 150), conta privada, mesada, divisão de despesa, meta de filho e um pedido de aprovação |
| `-uiTesting` | Armazenamento temporário e vazio, preferências em memória, sem prompt de biometria, sem animação de contagem |
| `-skipOnboarding` | Marca o onboarding como concluído (cria "Conta principal" e as categorias padrão) |
| `-fixedToday yyyy-MM-dd` | Congela "hoje" (capturas e testes determinísticos) |
| `-appearance light\|dark\|system` | Força a aparência |
| `-hideValues` | Começa com valores ocultos |
| `-lockOnLaunch` | Começa na tela de bloqueio (`auth.lock`) |
| `-startScreen <id>` | Abre direto em `home`, `transactions`, `new`, `plan.budget`, `plan.bills`, `plan.goals`, `plan.more`, `plan.debts`, `plan.debts.simulator`, `plan.cashflow`, `reports`, `tax`, `wallet.networth`, `family`, `settings.categories`, `wallet.accounts`, `wallet.cards` ou `wallet.investments` |

Sem `-uiTesting`, os dados ficam em `Application Support/FinanceApp/data.json` (JSON atômico via `JSONFileStore` do Core) e as preferências em `UserDefaults`.

## Testes

| O quê | Como | Precisa de Xcode? |
|---|---|---|
| Core (259 testes) | `scripts/test-core.sh` | Não |
| Lógica do app (109 testes): formatação, teclado, filtros, rascunho de lançamento (novo e edição), contas a pagar, fatura, AppStore, seed, importação, exportação, formulários, simulador de dívidas, família, aprovação, mesada, investimentos, patrimônio, relatórios, IR, PIN, comprovantes, widgets, sincronização | `scripts/test-app.sh` | Não |
| Typecheck de todo o código SwiftUI, a extensão de widgets (WidgetKit), App Intents e CloudKit com o SDK do macOS | `scripts/typecheck-app.sh` | Não |
| Testes de lógica dentro do Xcode (mesmos casos, via `XCTestBridge`) | `xcodebuild test -scheme FinanceApp ...` | Sim |
| **XCUITest** (26 testes, **todos passaram** no Simulador iPhone 12, iOS 26.4): onboarding, novo lançamento, pagar fatura, criar orçamento, bloqueio, e da Fase 2: simulador de dívidas, criar dívida, editar lançamento, excluir parcelas em grupo, família e acerto, aprovação de dependente, investimentos e patrimônio, fluxo de caixa/relatórios/IR, editar meta e histórico, PIN (+ "tour" de capturas claro/escuro). Rodados com `xcodebuild test` (veja abaixo como evitar os problemas do simulador) | `xcodebuild test` (alvo `FinanceAppUITests`) | Sim, e Simulador |

```bash
xcodebuild test -project FinanceApp.xcodeproj -scheme FinanceApp \
  -destination 'platform=iOS Simulator,name=iPhone 16' -derivedDataPath ../build \
  -resultBundlePath ../build/Test.xcresult
scripts/extract-screenshots.sh ../build/Test.xcresult ../Docs/screenshots/ui-tests   # extrai os anexos
```

Cada passo dos testes de UI anexa uma captura de tela ao `.xcresult` (`XCTAttachment`, `lifetime = .keepAlways`).

### Conferência visual sem Xcode (aproximada)

`scripts/render-macos.sh` compila as telas com `swiftc` no macOS e renderiza PNGs com `ImageRenderer` em `build/macos-preview/`. Serve para checar layout, cores dos tokens e valores extremos. **Não é o iOS**: ScrollView e List viram pilhas, Picker segmentado/Toggle/DatePicker não são desenhados, Dynamic Type não é aplicado.

### Notas dos testes de UI no Simulador

- Os campos de texto precisam do teclado de software: `defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false` com o Simulador fechado.
- O app foi corrigido onde os testes revelaram bugs reais: o toque fora do campo fechava o teclado logo após focar (iOS 26); o toast sumia ao fechar uma sheet; o espaço vazio de uma linha de lista não ativava o link; o PIN derrubava o app com SIGSEGV em `AddGestureModifier`.
- `xcodebuild test -project FinanceApp.xcodeproj -scheme FinanceApp -destination 'platform=iOS Simulator,id=<UDID>' CODE_SIGNING_ALLOWED=NO -only-testing:FinanceAppUITests` (~18 min).
- Capturas por `simctl io screenshot` exigem a janela do Simulador (framebuffer); sem ela, use as capturas anexadas pelo XCUITest (`scripts/extract-screenshots.sh`).

## Capturas de tela (critério de aceite visual)

```bash
scripts/capture-screenshots.sh            # 3 iPhones x claro/escuro x texto normal/grande x 8 telas -> ../Docs/screenshots
```

Manualmente, com um Simulador aberto:

```bash
xcrun simctl ui booted appearance dark                                   # claro/escuro
xcrun simctl ui booted content_size accessibility-extra-extra-extra-large # Dynamic Type no máximo (volte com "large")
xcrun simctl launch --terminate-running-process booted com.example.financas -uiTesting -seedDemo -startScreen plan.bills
xcrun simctl io booted screenshot ../Docs/screenshots/plan-bills.png
```

Tamanhos exigidos: iPhone SE (3rd generation), iPhone 16 e iPhone 16 Pro Max.

## VS Code e SweetPad

1. Instale a extensão **SweetPad** (`sweetpad.sweetpad`) e `brew install xcode-build-server xcbeautify`.
2. Gere o projeto (`xcodegen`) e rode **SweetPad: Generate Build Server Config** (cria `buildServer.json` para o SourceKit-LSP).
3. Na barra do SweetPad escolha o esquema `FinanceApp` e o Simulador; use **Build & Run** (⌘⇧B, ou o comando "SweetPad: Build & Run (Launch)"). Depuração: configuração de launch do SweetPad (CodeLLDB).
4. `../.vscode/tasks.json` traz tarefas (Terminal > Run Task): gerar projeto, testes do Core e do App, typecheck, build iOS, testes de UI, abrir Simulador, aparência, Dynamic Type, captura de tela e capturas completas.

## Dispositivo real (o que o Simulador não reproduz bem)

- **Cabo:** conecte o iPhone, ative o Modo Desenvolvedor (Ajustes > Privacidade e Segurança), escolha o aparelho no Xcode, defina o Team e rode.
- **TestFlight:** Product > Archive > Distribute App > App Store Connect (exige conta de desenvolvedor e bundle id próprio; troque `com.example.financas` em `project.yml`).
- Teste no aparelho: Face ID e "Usar código", notificações de vencimento (9h, X dias antes), compartilhar/salvar o CSV, importar OFX/CSV real do seu banco pelo app Arquivos, toque e háptica, desempenho com muitos lançamentos.

## Arquitetura em 30 segundos

- **Regras no Core.** A UI nunca recalcula saldo, fatura, parcela, orçamento, meta, dívida, divisão, patrimônio ou imposto; chama `BalanceEngine`, `CreditCardEngine`, `InstallmentEngine`, `RecurrenceEngine`, `BudgetEngine`, `SummaryEngine`, `GoalEngine`, `DebtEngine`, `CashFlowEngine`, `FamilyEngine`, `ApprovalEngine`, `AllowanceEngine`, `SplitEngine`, `SettlementEngine`, `InvestmentEngine`, `NetWorthEngine`, `ReportEngine`, `TaxEngine`, `SyncEngine`, `WidgetDataBuilder`, `CSVExporter`, `OFXParser`, `DuplicateDetector`, `CategorySuggester`.
- **`AppStore`** (`@MainActor @Observable`) guarda cópias em memória das entidades, persiste via `Repository` e expõe consultas derivadas e comandos. Views só leem; mutações passam por comandos (`save(_:)`, `payInvoice`, `setBudget`, `contribute`, `commitImport`...) que lançam erros tipados e atualizam tudo com `reload()`.
- **Dinheiro sempre `Decimal`.** `Double` só aparece para desenhar barras de gráfico e para a animação de contagem (nunca em cálculo).
- **Datas** são dias civis (UTC 12:00, `FinanceCalendar`); textos de data em pt-BR vêm de `DateText` (sem `DateFormatter`).
- **Tokens:** cores só por `Color.<token>` (Asset Catalog); espaçamentos e raios por `Space`/`Radius`; valores de destaque por `SplitAmount`; valores em linha por `AmountText` (sinal e cor pela regra dos tokens, VoiceOver por extenso, máscara "R$ ••••").
- **Acessibilidade:** `accessibilityIdentifier` com os ids de `Design/screens.md`; Dynamic Type em todos os textos; linhas viram coluna em tamanhos de acessibilidade.
- Todo componente e tela tem `#Preview` (vazio, valores grandes, negativos, texto longo, escuro). Em builds de debug, Ajustes > "Galeria de componentes".

## Decisões e limitações herdadas da Fase 1 (e o que mudou na Fase 2)

- Persistência em JSON (Core `JSONFileStore`), não SwiftData: o ambiente de desenvolvimento não tinha macros do SwiftData. O `Repository` é um protocolo; trocar o armazenamento não muda as Views.
- "PIN" do bloqueio = código do aparelho (LocalAuthentication `.deviceOwnerAuthentication`). **Fase 2:** há também um PIN próprio opcional (4 a 6 números, hash salgado e iterado no Keychain, bloqueio progressivo após 5 erros). Esquecer o PIN exige apagar os dados do app.
- Guardar dinheiro em uma meta cria uma transferência sem destino na conta de origem (reduz o saldo, não conta como despesa).
- Lançamento com data futura vira pendente e aparece em "A pagar"; recorrências geram ocorrências pendentes até ~4 meses à frente.
- **Fase 2:** lançamentos podem ser editados e parcelas excluídas em grupo. Pagamentos de fatura continuam sem edição nem exclusão.
- Comprovantes são gravados com `completeFileProtection`; o JSON de dados usa a proteção padrão do iOS (habilitar a capability Data Protection no Xcode é um próximo passo). Entitlements agora existem (App Group, e iCloud se você habilitar).

## Fase 2: o que está pronto, o que não foi verificado

### Funcionalidades

| Área | Onde | Estado |
|---|---|---|
| Dívidas e simulador avalanche × bola de neve (gráfico, prazo, juros, ordem de quitação, aviso quando uma estratégia não quita) | `Planejar > Mais > Dívidas` | Regras testadas; UI checada por tipos e render |
| Metas: editar, histórico de aportes (com desfazer), projeção pelo ritmo dos últimos 3 meses | `Planejar > Metas` | idem |
| Família local: grupo, papéis (admin/membro/dependente), perfil ativo, contas e categorias privadas × compartilhadas, lançamento atribuído a membro, visão família × individual | `Planejar > Mais > Família`, menu de perfil no Início | idem |
| Divisão de despesas (igual/percentual) e acerto com o menor número de transferências | `Família > Dividir despesas` | idem |
| Mesada, limite de dependente com aprovação, metas de filhos | `Família` | idem |
| Investimentos manuais (renda fixa, ações, FIIs, cripto), alocação, rentabilidade simples, patrimônio líquido e evolução mensal | `Carteira > Investimentos`, `Mais > Patrimônio` | idem |
| Fluxo de caixa 30/60/90 dias | `Mais > Fluxo de caixa` | idem |
| Relatórios por período/categoria/membro/conta; PDF (ImageRenderer) e CSV; resumo do IR (saúde e educação dedutíveis) | `Mais > Relatórios`, `Mais > IR` | PDF nunca gerado no iOS |
| Edição de lançamento, exclusão de parcelas (só esta / esta e seguintes / todas), comprovante (PhotosPicker), PIN próprio opcional | Lançamentos, Ajustes | Lógica testada; PhotosPicker/Keychain não executados |
| Sincronização: contrato, conflito por `updatedAt`, coordenador, CloudKit, convite por CKShare | Ajustes > Sincronização | Contrato e conflito testados; **CloudKit não testado; convite só esboçado; desligado por padrão** |
| Widgets (saldo, gastos do dia, próximo vencimento) e atalho "Adicionar despesa" | `Widgets/`, `App/Services/QuickAddIntent.swift` | Dados testados; **WidgetKit e Siri não executados** |

### Verificações executadas (neste ambiente)

```bash
scripts/test-core.sh        # 259 passaram, 0 falharam
scripts/test-app.sh         # 109 passaram, 0 falharam
scripts/typecheck-app.sh    # OK: 85 arquivos (Core + App) e 15 (Core + Widgets), SDK do macOS, Swift 6, -warnings-as-errors
scripts/render-macos.sh     # renderiza as telas novas em build/macos-preview/ (aproximado, ver limites acima)
```

### O que NÃO foi verificado

- Compilação para iOS (trechos `#if os(iOS)`, UIKit, `keyboardType`, `PhotosPicker` em UIKit etc.) e execução no Simulador ou aparelho.
- `xcodegen`: o `project.yml` (alvo de widgets, entitlements, dependência embutida) foi lido por um parser YAML, mas o projeto não foi gerado.
- XCUITest da Fase 2 (só `swiftc -parse`). WidgetKit, App Groups, App Intents/Siri/Atalhos, Keychain, PhotosPicker, `ImageRenderer` em PDF no iOS.
- CloudKit real (conta, container, esquema, `CKShare`). Veja `../docs/cloudkit-setup.md`.
- Dynamic Type, VoiceOver e contraste das telas novas no aparelho.

### O que você precisa fazer no Xcode

1. `brew install xcodegen && cd FinanceApp && xcodegen && open FinanceApp.xcodeproj`. Corrija o que o primeiro build do iOS apontar.
2. **Bundle id e Team:** troque `com.example.financas` (`project.yml`, `SharedContainer.appGroupID`, `CloudKitConfig.containerID`) e defina o `DEVELOPMENT_TEAM`.
3. **App Groups:** crie `group.<bundle id>` no portal e associe ao app e à extensão `FinanceWidgets` (o `project.yml` já gera os entitlements). Sem isso os widgets ficam vazios.
4. **iCloud/CloudKit (opcional):** siga `../docs/cloudkit-setup.md` (capability, container, entitlements e a flag `CLOUDKIT_ENABLED`). Deixe desligado até testar com duas contas/aparelhos.
5. **Ícone:** adicione o PNG 1024x1024 em `Assets/Assets.xcassets/AppIcon.appiconset`.
6. Rode `FinanceAppTests` e `FinanceAppUITests`, adicione os widgets à tela de início, teste "Adicionar despesa" na Siri e exporte um PDF.
7. App Store: `../docs/app-store-checklist.md` (política de privacidade base LGPD, privacy manifest, classificação etária, capturas, itens do dono).

### Decisões de projeto da Fase 2 que valem saber

- **Privacidade entre membros é regra do app, não criptografia.** Todos os perfis vivem no mesmo arquivo local; "privada" esconde da UI, inclusive do administrador. Com CloudKit compartilhado seria preciso separar zonas (ver `cloudkit-setup.md`).
- **Widget e bloqueio:** o widget lê um resumo em texto simples no App Group e só respeita "Ocultar valores". Com saldo visível, ele aparece mesmo com o app bloqueado.
- **Patrimônio** conta o limite usado dos cartões (inclui parcelas futuras) como passivo; contas com saldo negativo viram passivo.
- **IR:** o limite anual de educação (R$ 3.561,50 por pessoa) está em `TaxRules` e muda por lei; é auxiliar, não declaração.
- **Siri:** o valor é um texto ("45,90") para nunca passar por `Double`.
