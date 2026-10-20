# Objetivo
Quero criar um app iOS nativo de gestão financeira pessoal e familiar, que cubra todas as necessidades de controle financeiro em um só lugar. O público é brasileiro (moeda BRL, português do Brasil, PIX, boletos, cartão de crédito com fatura e fechamento).

# Antes de codar
1. Use a skill `requirements-clarity` e me faça no máximo 5 perguntas objetivas sobre pontos que mudam a arquitetura (ex.: sincronização entre membros, Open Finance, monetização).
2. Depois, gere um plano em fases (MVP → v1 → v2) com o escopo de cada fase, usando a skill `gepetto` ou `executing-plans`.
3. Só então comece a implementar, uma fase por vez, e peça minha aprovação ao fim de cada uma.

# Stack sugerida (questione se houver opção melhor)
- Swift + SwiftUI, iOS 17+, arquitetura MVVM ou TCA
- SwiftData (ou Core Data) para persistência local, com CloudKit para sincronização entre dispositivos e membros da família
- Swift Charts para gráficos
- Testes unitários e de UI (XCTest / Swift Testing)
- Acessibilidade (Dynamic Type, VoiceOver), modo escuro, localização pt-BR

# Funcionalidades

## 1. Núcleo (MVP)
- Contas: corrente, poupança, carteira, investimentos, com saldo e conciliação
- Lançamentos: receitas, despesas e transferências entre contas
- Categorias e subcategorias personalizáveis, tags e anexos (foto de comprovante)
- Lançamentos recorrentes, parcelados e agendados
- Dashboard mensal: saldo, receitas × despesas, gastos por categoria, comparação com o mês anterior
- Busca e filtros (período, conta, categoria, valor, tag)

## 2. Cartões de crédito
- Vários cartões, com limite, dia de fechamento e dia de vencimento
- Fatura atual e futuras, compras parceladas, limite disponível
- Pagamento de fatura vinculado a uma conta

## 3. Orçamento e metas
- Orçamento mensal por categoria, com alertas ao se aproximar do limite
- Metas de economia (reserva de emergência, viagem, compra) com progresso e prazo
- Método de orçamento configurável (ex.: 50/30/20 ou envelope)

## 4. Contas a pagar e receber
- Calendário de vencimentos, status (pendente, pago, atrasado)
- Notificações locais de lembrete
- Controle de boletos, com data e valor

## 5. Gestão familiar
- Grupo familiar com convite de membros e papéis (administrador, membro, dependente)
- Contas e categorias compartilhadas e privadas
- Visão consolidada da família e visão individual
- Mesada e metas dos filhos (educação financeira)
- Divisão de despesas entre membros e acerto de contas

## 6. Dívidas, empréstimos e financiamentos
- Cadastro de dívidas com juros e parcelas
- Simulador de quitação (avalanche × bola de neve)

## 7. Investimentos e patrimônio
- Carteira manual: renda fixa, ações, FIIs, cripto
- Patrimônio líquido (ativos − passivos) e evolução no tempo
- Rentabilidade simples e alocação por classe

## 8. Planejamento e relatórios
- Fluxo de caixa projetado (30, 60 e 90 dias)
- Relatórios por período, categoria, membro e conta
- Exportação para CSV e PDF
- Resumo de imposto de renda (rendimentos, despesas dedutíveis como saúde e educação)

## 9. Experiência e segurança
- Face ID / Touch ID e PIN para abrir o app
- Widgets (saldo, gastos do dia, próximo vencimento) e Atalhos da Siri
- Lançamento rápido (poucos toques), com sugestão automática de categoria
- Importação de extratos (OFX/CSV) e backup/restauração
- Privacidade: dados locais e criptografados por padrão, conformidade com a LGPD, sem venda de dados

## 10. Diferenciais (v2)
- Open Finance (conexão bancária automática)
- Leitura de notas fiscais (QR Code NFC-e) e OCR de comprovantes
- Insights com IA: detecção de gastos atípicos, previsão de saldo, sugestões de economia
- Apple Watch e Live Activities

# Design
- Use as skills `frontend-design` e `design-system-starter` para definir tokens (cores, tipografia, espaçamento) antes das telas.
- Visual limpo, moderno e confiável, com foco em clareza dos números. Evite aparência genérica.
- Gere mockups ASCII das telas principais com o agente `ascii-ui-mockup-generator` para eu aprovar antes de implementar.
- Fluxos principais: onboarding, dashboard, novo lançamento, fatura do cartão, orçamento, visão familiar.

# Como testar a interface (obrigatório em cada fase)

O ambiente é um Mac com VS Code e Xcode instalados. Cada tela entregue precisa ser verificada visualmente, sem depender só de mim.

## 1. Simulador iOS controlado pelo terminal (principal)
- Compile e rode no Simulador com `xcodebuild` e `xcrun simctl` (boot do dispositivo, instalar, abrir o app).
- Tire capturas de tela com `xcrun simctl io booted screenshot <arquivo>.png`, abra as imagens e confira layout, textos cortados, contraste e modo escuro.
- Faça capturas nos tamanhos iPhone SE, iPhone 16 e iPhone 16 Pro Max, com Dynamic Type normal e no maior tamanho.
- Use a skill `run` para lançar e acompanhar o app.

## 2. Integração com o VS Code
- Configure a extensão **SweetPad** (ou Swift + CodeLLDB) para compilar, rodar no Simulador e depurar sem abrir o Xcode.
- Crie tarefas em `.vscode/tasks.json` para: build, rodar testes, abrir o Simulador e gerar capturas de tela.

## 3. Testes automatizados de interface
- Escreva testes com XCUITest para os fluxos críticos: onboarding, novo lançamento, pagar fatura, criar orçamento, convidar membro da família.
- Use identificadores de acessibilidade (`accessibilityIdentifier`) em todos os elementos interativos.
- Salve capturas de tela em cada passo do teste (anexos do `.xcresult`) e extraia as imagens para `Docs/screenshots/`.
- Use testes de snapshot (ex.: `swift-snapshot-testing`) para detectar mudanças visuais não intencionais.

## 4. Pré-visualização rápida
- Todo componente SwiftUI deve ter `#Preview` com dados fictícios (casos: lista vazia, valores grandes, valores negativos, texto longo, modo escuro).
- Mantenha uma tela "Galeria de componentes" dentro do app (somente em build de debug) para ver todos os componentes juntos.

## 5. Protótipo navegável fora do Xcode (alternativa)
- Antes de implementar cada fase em Swift, gere um protótipo clicável em HTML/CSS/JS (use a skill `frontend-design` e publique como Artifact) simulando o frame de um iPhone (390×844).
- Eu valido o protótipo no navegador e só então você implementa a versão em SwiftUI.
- Opcional: se eu enviar um link do Figma, use o MCP do Figma para comparar o design com o app implementado.

## 6. Dispositivo real
- Explique como instalar no meu iPhone via cabo ou TestFlight, para eu validar toque, Face ID, widgets e notificações, que o Simulador não reproduz bem.

## Critério de aceite visual
Uma fase só termina quando você me entregar:
1. Capturas das telas principais (claro e escuro, 3 tamanhos de iPhone)
2. Os resultados dos testes de UI (passou/falhou)
3. Uma lista do que não foi possível verificar no Simulador e que eu preciso testar no aparelho

# Entregáveis por fase
- Estrutura do projeto Xcode e modelo de dados (use `database-schema-designer`, com diagrama ER em Mermaid)
- Código SwiftUI organizado em módulos (Models, Views, ViewModels, Services)
- Testes dos cálculos financeiros (faturas, parcelas, recorrências, saldos)
- README com instruções para rodar, e CLAUDE.md com as convenções do projeto

# Regras de trabalho
- Valores monetários sempre em `Decimal`, nunca em `Double`.
- Use TDD (`test-driven-development`) para a lógica financeira.
- Antes de dizer que algo está pronto, rode build, testes unitários e testes de UI, e me mostre as capturas de tela (`verification-before-completion`).
- Mantenha commits pequenos e claros (`commit-work`).
- Quando houver decisão importante (sincronização, modelo de dados), apresente 2 opções com uma recomendação e espere minha escolha.

# Comece por
Faça as perguntas de esclarecimento e depois proponha o plano de fases com o escopo do MVP.
