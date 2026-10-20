# App Finanças (iOS) - PRD e Plano de Fases

## Decisões de esclarecimento
| Tema | Decisão |
|---|---|
| Sincronização | Só local no início. Modelo de dados já preparado para CloudKit e multi-usuário depois (IDs UUID, `updatedAt`, campo `ownerId`). |
| Distribuição | App Store gratuito. Exige conta de desenvolvedor, política de privacidade, LGPD e privacy manifest. |
| Entrada de dados | Manual + importação OFX/CSV. Open Finance fica na v2. |
| Prioridade do MVP | Núcleo individual sólido. Família entra na v1. |

## Stack
Swift 6, SwiftUI, iOS 17+, SwiftData (com `ModelConfiguration` compatível com CloudKit), Swift Charts, MVVM com `@Observable`, Swift Testing + XCUITest. Valores monetários em `Decimal`.

## Fases

### Fase 0 - Fundação (aprovar antes de codar)
- [ ] Tokens de design (cores, tipografia, espaçamento) com `design-system-starter` e `frontend-design`
- [ ] Mockups ASCII das telas do MVP (`ascii-ui-mockup-generator`)
- [ ] Modelo de dados + diagrama ER Mermaid (`database-schema-designer`)
- [ ] Projeto Xcode, estrutura de módulos, `.vscode/tasks.json`, CLAUDE.md, README
- [ ] Protótipo HTML navegável (390x844) das telas principais
- **Entrega:** mockups, ER, protótipo e projeto compilando vazio

### Fase 1 - MVP (núcleo individual)
- [ ] Contas (corrente, poupança, carteira, investimento) e saldo
- [ ] Lançamentos: receita, despesa, transferência; categorias, subcategorias, tags, anexo de foto
- [ ] Recorrentes, parcelados e agendados (com testes de cálculo)
- [ ] Cartões de crédito: fechamento, vencimento, fatura, limite, pagamento de fatura
- [ ] Orçamento mensal por categoria com alertas
- [ ] Contas a pagar/receber com calendário e notificações locais
- [ ] Dashboard mensal (Swift Charts), busca e filtros
- [ ] Importação OFX/CSV, exportação CSV
- [ ] Face ID/PIN, modo escuro, Dynamic Type, pt-BR
- **Critério de aceite:** testes unitários e de UI passando; capturas em 3 iPhones (claro/escuro); lista do que exige aparelho real

### Fase 2 - v1 (metas, família e planejamento)
Status do código: regras do Core e lógica do app testadas com swiftc; UI checada por tipos no SDK do macOS e renderizada no macOS.
**Nada foi compilado para iOS nem executado no Simulador, WidgetKit ou CloudKit reais** (ver `FinanceApp/README.md`).
- [x] Metas de economia (edição, histórico de aportes, projeção), dívidas e simulador de quitação (avalanche × bola de neve)
- [x] Grupo familiar local (perfis, papéis, contas e categorias privadas/compartilhadas, visão família × individual, divisão de despesas com acerto de contas, mesada, limite e aprovação de dependentes)
- [~] Sincronização via CloudKit e convite de membros: protocolo, regra de conflito e coordenador prontos e testados; `CloudKitSyncService` escrito e checado por tipos, **não testado**; convite por CKShare só esboçado; desligado por padrão (`docs/cloudkit-setup.md`)
- [x] Fluxo de caixa projetado 30/60/90, relatórios por período/categoria/membro/conta, PDF e CSV, resumo para o IR
- [x] Investimentos manuais, alocação, rentabilidade simples e patrimônio líquido com evolução mensal
- [~] Widgets (saldo, gastos do dia, próximo vencimento) e Atalho da Siri "adicionar despesa": código e alvo no `project.yml`; **não executados**
- [~] Preparação App Store (privacidade, LGPD, TestFlight): `docs/app-store-checklist.md`; depende de conta, bundle id, ícone e revisão jurídica
- [x] Edição de lançamento, exclusão de parcelas em grupo, comprovante (PhotosPicker) e PIN próprio opcional

### Fase 3 - v2 (diferenciais)
Status do código: regras do Core e lógica do app testadas com `swiftc` (Core 259, App 109 testes); o app compila para o Simulador iOS (`xcodebuild`, iPhone 12, iOS 26.4) com o `project.yml` e o `project-free.yml`; o relógio foi checado por tipos contra o SDK do watchOS Simulator (não há runtime watchOS instalado). **Câmera, Vision, WatchConnectivity e Open Finance nunca rodaram em aparelho ou com serviços reais.** Detalhes em `docs/ocr-nfce.md` e `docs/open-finance.md`.
- [x] Insights locais e explicáveis (sem IA nem servidor): gastos atípicos por categoria (mediana + MAD) e por compra, previsão do saldo no fim do mês, assinaturas/recorrências detectadas (com alta de preço), sugestões de economia com o cálculo mostrado, alerta de risco de saldo negativo. Tela `Planejar > Mais > Insights` e cartão no Início
- [~] NFC-e: leitura do QR (chave de 44 dígitos validada: UF, CNPJ, DV; valor só em contingência) e leitor AVFoundation; abre o Novo lançamento pré-preenchido. **Consulta à SEFAZ não implementada de propósito** (`NFCeLookupService` é só um protocolo). Leitor de câmera não executado
- [~] OCR de comprovantes: extrator de valor/data/estabelecimento testado com textos pt-BR de cupom, PIX e boleto (linha digitável de 47/48 dígitos com DV, valor e vencimento); wrapper Vision. Vision/câmera não testados com fotos reais
- [~] Open Finance: protocolo `BankConnectionProvider`, mapeamento testado com deduplicação por `externalId`, `MockBankProvider` (dados fictícios), tela de consentimento, desligado por padrão. **Nenhum provedor real**: exige contrato, credenciais e backend (`docs/open-finance.md`)
- [~] Apple Watch: app (saldo, gasto do dia, despesa por ditado) e complicação, lendo o `WidgetSnapshot` por WatchConnectivity; lógica testada no Core. **Não executado** (sem runtime/aparelho do relógio); alvo só no `project.yml`, embutir no app do iPhone é manual
- [x] Resumo de IR (já entregue na Fase 2)

## Riscos
- Migrar de local para CloudKit: mitigado com IDs UUID e modelo compatível desde a Fase 0.
- Regras de fatura (fechamento, parcelas): cobertas por TDD com `Decimal`.
- Aprovação na App Store: política de privacidade e LGPD planejadas desde a Fase 2.
