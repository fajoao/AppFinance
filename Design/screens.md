# Inventário de telas (MVP e Fase 2)

As telas da Fase 2 (seção "Telas da Fase 2" abaixo) **não estão no protótipo HTML** (fora do escopo); a referência delas é o SwiftUI (`#Preview`) e as capturas do `scripts/render-macos.sh`.

Referência visual do MVP: `Prototype/index.html`. Abra no navegador e escolha a tela no seletor "Tela" no topo da página. Cada tela no protótipo tem `data-screen="<id>"`. Use o mesmo id como prefixo de `accessibilityIdentifier` no SwiftUI (ex.: `transaction.new.save`).

## Navegação

`TabView` com 5 itens: **Início** (`tab.home`), **Lançamentos** (`tab.transactions`), **Novo** (`tab.new`, botão central que abre sheet, não é aba), **Planejar** (`tab.plan`), **Carteira** (`tab.wallet`). Ajustes fica no botão de engrenagem do Início (push). Planejar e Carteira usam `Picker(.segmented)` no topo para alternar as subtelas.
Na Fase 2, Planejar tem 4 segmentos (Orçamento, A pagar, Metas, **Mais**) e Carteira tem 3 (Contas, Cartões, **Investimentos**). "Mais" (`plan.more`) abre por push as telas de dívidas, fluxo de caixa, relatórios, IR, patrimônio, família e categorias. Com um grupo familiar criado, o Início ganha o menu de perfil (`home.profile`).

| Id | Tipo | Onde | Conteúdo principal |
|---|---|---|---|
| `onboarding.welcome` | Tela cheia (passo 1/3) | Primeiro uso | Título, numeral dividido de exemplo, 2 garantias (privacidade, OFX), botão "Começar" |
| `onboarding.account` | Tela cheia (passo 2/3) | Primeiro uso | Nome da conta (obrigatório, erro inline), tipo (segmentado), saldo de hoje (decimal), "Continuar" |
| `onboarding.security` | Tela cheia (passo 3/3) | Primeiro uso | Toggles Face ID e lembretes, "Concluir" |
| `auth.lock` | Cobertura modal | Ao abrir o app / Ajustes > Bloquear agora | "Desbloquear com Face ID", "Usar código" |
| `home.dashboard` | Aba Início | Raiz | Título do mês, ocultar valores, Ajustes; saldo em contas (amountHero, contagem de entrada); resultado do mês; barras Receitas × Despesas com marca de setembro; "Para onde foi" (barras por categoria, delta % vs setembro, marca de setembro); próximos 3 vencimentos |
| `transactions.list` | Aba Lançamentos | Raiz | Busca (nome, categoria, tag, conta); chips Filtros (com contador), período, Despesas, Receitas; resumo "N lançamentos, resultado"; lista agrupada por dia com total do dia; estado vazio com "Limpar busca e filtros" |
| `transactions.filters` | Sheet (grande) | Lançamentos > Filtros | Período, tipo, contas e cartões (multi), categorias (multi), valor mín./máx., tag; "Limpar", "OK", "Mostrar N lançamentos" (contagem ao vivo) |
| `transaction.new` | Sheet (grande) | Botão + | Tipo (Despesa/Receita/Transferência); valor com numeral dividido e cursor; descrição com **sugestão automática de categoria**; chips de categoria; pills Conta/Cartão, Data, Repetir, Tag; teclado numérico próprio (1–9, vírgula, 0, apagar), trocado por painel quando uma pill é aberta; "Salvar despesa/receita/transferência" |
| `transaction.new` painéis | Painel interno | Pills | `acc` (conta ou cartão, mostra disponível do cartão), `to` (destino da transferência), `date` (Hoje/Ontem/Anteontem + data), `repeat` (Não repete, Parcelado com stepper 2–24 e "Nx de R$", Todo mês, Toda semana), `tag` (existentes + nova) |
| `plan.budget` | Planejar > Orçamento | Aba Planejar | Disponível no mês (amountLarge), barra total; linhas por categoria com barra, marca de 80%, badge "Restam", "N% usado" (≥ 80%) ou "Estourou R$" (≥ 100%) |
| `plan.bills` | Planejar > A pagar | Aba Planejar | Calendário do mês (outubro/novembro) com pontos por status; legenda; total a pagar e a receber; lista filtrável pelo dia tocado; ações "Pagar"/"Recebi"; fatura de cartão aparece como conta e abre `wallet.payInvoice` |
| `plan.goals` | Planejar > Metas | Aba Planejar | Bloco por meta: nome, prazo, % (badge), guardado (amountLarge) de alvo, barra, "Guarde por mês", "Guardar dinheiro" |
| `plan.goals.contribute` | Sheet (curta) | Meta > Guardar dinheiro | Valores rápidos (R$ 50/100/200/500), conta de origem, "Guardar R$ X" |
| `wallet.accounts` | Carteira > Contas | Aba Carteira | Patrimônio total; grupos Conta corrente, Poupança, Carteira, Investimento com subtotal; linha com data de conciliação e saldo |
| `wallet.cards` | Carteira > Cartões | Aba Carteira | Bloco por cartão: nome, final, status, fatura atual, fecha/vence, barra de limite usado, limite disponível, parcelas futuras, "Ver fatura", "Pagar fatura" |
| `wallet.cardInvoice` | Push | Ver fatura | Abas de fatura (anterior paga, atual aberta, 2 futuras), total, fecha/vence, "Pagar fatura", compras da fatura (futuras: parcelas e assinaturas previstas) |
| `wallet.payInvoice` | Sheet (grande) | Pagar fatura | Total da fatura; opção total, mínimo (15%, aviso de rotativo) ou outro valor; conta de origem com saldo; aviso de saldo insuficiente; "Pagar R$ X" |
| `settings` | Push | Início > engrenagem | Face ID, bloquear após, bloquear agora; aparência Sistema/Claro/Escuro; lembretes e antecedência; exportar CSV; importar OFX; extrato de exemplo; texto de privacidade/LGPD |

## Regras de comportamento que o protótipo demonstra

- **Pagamento de fatura não é despesa** (`kind = invoice`). As compras já contaram no orçamento quando foram feitas no cartão. Aparece em Lançamentos na cor de transferência.
- **Ciclo do cartão:** compra na data de fechamento ou depois cai na fatura seguinte. Vencimento antes do dia de fechamento cai no mês seguinte ao fechamento.
- **Limite disponível** = limite − fatura aberta não paga − parcelas futuras.
- **Parcelado:** a 1ª parcela recebe o resto da divisão em centavos (`total − parcela × (n − 1)`).
- **Alertas de orçamento:** toast (e notificação local no app) ao cruzar 80% e ao cruzar 100%, uma vez cada.
- **Status de conta a pagar:** Pago, Pendente, Vence hoje/amanhã/em N dias (≤ 3, alerta), Atrasado N dias (perigo), A receber.
- **Ocultar valores:** troca todos os valores por `R$ ••••` e VoiceOver lê "valor oculto".
- **Importação OFX:** deduplica por `FITID`, sugere categoria pelo texto, informa "N importados, M repetidos ignorados".
- **CSV:** `;` como separador, vírgula decimal, BOM UTF-8 (abre direto no Excel em pt-BR).

## Telas da Fase 2

Mesmas convenções: o id é o prefixo dos `accessibilityIdentifier`. "Push" = empurrada na pilha da aba; "Sheet" = modal.

| Id | Tipo | Onde | Conteúdo principal |
|---|---|---|---|
| `plan.goals` (alterado) | Aba Planejar | Metas | Cada meta ganha menu (`plan.goals.menu.N`: Editar, Histórico e projeção) e a linha de projeção "No seu ritmo ... conclui em mês/ano" (`plan.goals.projection.N`); metas de dependentes mostram "Meta de Caio" |
| `plan.goals.edit` / `plan.goals.new` | Sheet | Meta > menu / Nova meta | Nome, valor, prazo (opcional), "Meta de" (eu ou dependente, só ao criar), salvar, excluir (`plan.goals.edit.delete`, com confirmação) |
| `plan.goals.history` | Sheet (grande) | Meta > Histórico e projeção | Ritmo dos últimos 3 meses, conclusão prevista, "No caminho/Atrasada", quanto falta por mês; lista de aportes com desfazer (`plan.goals.history.revert`) |
| `plan.more` | Aba Planejar | Segmento Mais | Lista agrupada: Dívidas (`plan.more.debts`), Fluxo de caixa (`.cashflow`), Relatórios (`.reports`), IR (`.tax`), Patrimônio (`.networth`), Família (`.family`), Categorias (`.categories`) |
| `plan.debts` | Push | Mais > Dívidas | Total devido (`plan.debts.total`), lista (`plan.debts.row.<nome>`) com juros, mínimo e vencimento; "Simular quitação" (`plan.debts.simulate`), "Nova dívida" (`plan.debts.add`); vazio com `plan.debts.add.empty` |
| `plan.debts.form` | Sheet (grande) | Dívidas > Nova/editar | Nome, saldo devedor, juros ao mês (%), mínimo, dia do vencimento; erros inline (`.error`); excluir com confirmação |
| `plan.debts.simulator` | Push | Dívidas > Simular | Campo de orçamento mensal (sugere 120% dos mínimos), resumo, cartões **Avalanche** (`.avalanche`) e **Bola de neve** (`.snowball`) com prazo, data estimada, juros, total pago e ordem de quitação, selo "Menos juros/Recomendada", aviso quando uma estratégia não quita (`.infeasible`), gráfico de linhas do saldo mês a mês (`.chart`, bola de neve tracejada) |
| `plan.cashflow` | Push | Mais > Fluxo de caixa | Seletor 30/60/90 dias (`plan.cashflow.horizon`), saldo previsto, manchete de alerta (`.headline`), gráfico em degraus com linha de zero (`.chart`), totais (entradas, saídas, menor saldo e data) e lista dos lançamentos previstos |
| `reports.main` | Push | Mais > Relatórios | Período (este mês, mês passado, 3 meses, este ano, personalizado), filtros por categoria/membro/conta, resultado, receitas e despesas, gráfico mês a mês, grupos por categoria/membro/conta (`reports.group.*`), exportar PDF (`reports.exportPDF`) e CSV (`reports.exportCSV`) |
| `reports.tax` | Push | Mais > IR | Ano-calendário (`reports.tax.year`), pessoa, total dedutível, rendimentos por categoria, despesas dedutíveis de saúde e educação (limite de educação por pessoa), aviso legal (`reports.tax.disclaimer`), atalho para marcar categorias, exportar PDF/CSV |
| `settings.categories` | Push | Mais > Categorias / Ajustes | Categorias de despesa com menu (`settings.categories.menu.<nome>`): dedutível no IR (Saúde/Educação) e visibilidade privada/compartilhada; "Nova categoria" (`settings.categories.add`) |
| `wallet.investments` | Aba Carteira | Segmento Investimentos | Valor da carteira, rentabilidade simples, atalho Patrimônio (`wallet.investments.networth`), alocação por classe em rosca com legenda (`wallet.investments.allocation`), posições por classe (renda fixa, ações, FIIs, cripto), "Adicionar ativo" |
| `wallet.investments.form` | Sheet (grande) | Investimentos > Adicionar/editar | Classe, nome, código, quantidade, preço médio (ou "valor aplicado" na renda fixa), cotação atual manual |
| `wallet.investments.detail` | Sheet (grande) | Investimentos > ativo | Custo, ganho, rentabilidade, lucro realizado; atualizar cotação, comprar mais, vender, editar, excluir |
| `wallet.networth` | Push | Mais > Patrimônio / Investimentos | Patrimônio líquido, ativos (contas, investimentos), passivos (dívidas, faturas e parcelas, saldo negativo), evolução mensal por snapshots (`wallet.networth.chart`), "Registrar patrimônio agora" |
| `family.home` | Push | Mais > Família / Ajustes | Sem grupo: nome da família e seu nome (`family.setup.*`). Com grupo: perfil ativo (`family.activeProfile`, `family.switchProfile`), visão Família × Individual (`family.scope`), pessoas com gasto no mês (`family.member.<nome>`), adicionar pessoa, ferramentas, contas privadas × compartilhadas (`family.account.menu.<nome>`) |
| `family.member.form` | Sheet | Família > Adicionar pessoa | Nome, papel (administrador, membro, dependente), limite mensal do dependente |
| `family.member.detail` | Sheet | Família > pessoa | Usar este perfil, gasto no mês, mudar papel, limite do dependente, remover |
| `family.settle` | Push | Família > Dividir despesas | Saldo de cada pessoa, transferências mínimas para zerar (`family.settle.paid.N`), despesas divididas, "Dividir uma despesa" (`family.split.add`) |
| `family.split` | Sheet (grande) | Acerto de contas > Dividir | Descrição, valor, quem pagou, quem divide, modo igual/percentual (soma 100%), prévia de cada parte, lançar também como despesa |
| `family.allowance` | Push | Família > Mesada | Mesadas (valor, dia, conta de origem e destino), "Nova mesada" (`family.allowance.form`) |
| `family.approvals` | Push | Família > Aprovações | Gastos de dependentes acima do limite: Aprovar/Recusar (só administrador e membro), histórico de decididos |
| `family.kidsGoals` | Push | Família > Metas dos filhos | Metas por dependente, guardar dinheiro e nova meta (`family.kidsGoals.add.<nome>`) |
| `transaction.edit` | Sheet (grande) | Lançamento > Editar | Mesma tela de `transaction.new` com título "Editar lançamento", sem tipo nem repetição; pills Quem (família) e Comprovante (`PhotosPicker`); "Salvar alterações" |
| `transaction.detail` (alterado) | Sheet | Lançamentos > linha | Novos: Editar (`transaction.detail.edit`), quem lançou, observação, comprovante; excluir parcela pergunta o escopo: só esta, esta e as seguintes, todas |
| `settings.pin` | Push | Ajustes > Segurança | Código próprio opcional de 4 a 6 números (ativar com confirmação, desativar com o código atual) |
| `auth.lock` (alterado) | Cobertura | Bloqueio | Com PIN ativo: campo `auth.lock.pin`, botão `auth.lock.pin.submit`, erro e bloqueio progressivo após 5 erros |
| `settings.sync` | Push | Ajustes > Família e dados | Liga/desliga a sincronização com o iCloud (desligada por padrão), estado, "Sincronizar agora"; avisa quando o build não tem o iCloud configurado |
| Widgets | Tela de início | WidgetKit | **Saldo**, **Gastos do dia** e **Próximo vencimento** (pequeno; retangular na tela de bloqueio); respeitam "Ocultar valores"; estado vazio sem dados |
| Siri / Atalhos | Sistema | App Intents | "Adicionar despesa no Finanças" com valor (texto, ex. 45,90) e descrição; passa pela regra de aprovação de dependentes |

## Regras de comportamento da Fase 2

- **Visibilidade:** conta ou categoria privada só aparece para o dono, em qualquer visão (nem o administrador a vê). A visão Família soma só o compartilhado; a Individual mostra o que é do membro, inclusive o privado dele. Dependentes só têm a visão individual.
- **Atribuição:** todo lançamento novo é atribuído ao perfil ativo (pill "Quem" para administrador e membro). Lançamento sem membro pertence ao dono da conta.
- **Dependente:** gasto que ultrapassa o limite mensal não vira lançamento: vira pedido de aprovação, sem alterar saldos até um responsável aprovar.
- **Divisão:** igual (última parte absorve os centavos) ou percentual (precisa somar 100%). O acerto casa sempre o maior devedor com o maior credor: no máximo (pessoas - 1) transferências.
- **Mesada:** transferência da conta do responsável para a do dependente no dia combinado; meses perdidos são recuperados (até 12) e nunca paga duas vezes.
- **Dívidas:** se uma estratégia não quita (juros maiores que o pagamento), ela é marcada "Não quita" e só a outra pode ser recomendada.
- **Patrimônio:** ativos (contas positivas + investimentos) menos passivos (dívidas + faturas e parcelas não pagas + saldo negativo). Um registro por mês.
- **IR:** saúde sem limite; educação limitada por pessoa (valor configurável em `TaxRules`, padrão R$ 3.561,50, confirme a tabela vigente).
- **Sincronização:** desligada por padrão; em conflito vale o `updatedAt` mais recente; exclusões propagam por tombstone.

---

# Fase 3 (v2): insights, leitura de notas, Open Finance e Apple Watch

Identificadores (`accessibilityIdentifier`) e comportamento. Tudo local e determinístico, exceto o Open Finance (desligado, sem provedor real).

| Id | Tipo | Onde | Conteúdo |
|---|---|---|---|
| `insights` | Push | Planejar > Mais > Insights (`plan.more.insights`); Início > Insights > Ver todos (`home.insights.seeAll`) | Saldo previsto do fim do mês (`insights.forecast`, `insights.forecast.amount`) com selo de confiança; **Atenção** (`insights.alerts`): risco de saldo negativo, gastos atípicos; **Assinaturas e recorrências** (`insights.subscriptions`); **Sugestões de economia** (`insights.savings`); aviso de poucos dados (`insights.fewData`); vazio (`insights.empty`); rodapé (`insights.disclaimer`) |
| `insights.item.<id>` | Card | Insights | Título, mensagem e botão "Como calculamos" (`insights.explain.<id>`) que abre o cálculo passo a passo (`insights.explanation.<id>`). Ids fixos: `risk`, `forecast`, `subscriptions`; os demais levam categoria/mês |
| `home.insights` | Cartão | Início | Os 2 insights mais graves e "Ver todos" |
| `scan` | Sheet (grande) | Novo lançamento > ícone de documento (`transaction.new.scan`) | Opções: Ler QR da nota (`scan.qr`, só iPhone com câmera), Foto de cupom/PIX/boleto (`scan.photo`), Digitar ou colar o texto (`scan.paste`, `scan.text`, `scan.interpret`); aviso (`scan.disclaimer`); erro (`scan.error`) |
| `scan.result` | Bloco | Scan | Título (`scan.result.title`), campos (`scan.result.amount`, `.date`, `.merchant`, `.uf`, `.cnpj`, `.key`, `.line`, `.type`), avisos (`scan.result.warning`), "Usar no lançamento" (`scan.use`), "Ler outro" (`scan.again`) |
| `settings.openfinance` | Push | Ajustes > Família e dados > Open Finance (`settings.openfinance.link`) | Explicação, escopos autorizados, termos (`openfinance.terms`), interruptor de consentimento **desligado por padrão** (`openfinance.toggle`, desabilitado sem provedor), aviso de indisponibilidade (`openfinance.unavailable`) ou de modo demonstração (`openfinance.mockBanner`); com provedor: buscar bancos (`openfinance.load`), conectar (`openfinance.institution.<id>`), estado (`openfinance.status`), importar (`openfinance.sync`), revogar (`openfinance.revoke`), resultado (`openfinance.result`) |
| Relógio: `watch.home` | Apple Watch | App do relógio | Saldo (`watch.balance`), gasto de hoje (`watch.todaySpent`), próximo vencimento (`watch.nextDue`), frescor do dado (`watch.freshness`), "Nova despesa" (`watch.add`) |
| Relógio: `watch.add` | Push | Relógio | Campo com ditado (`watch.add.text`), prévia (`watch.add.preview`), enviar (`watch.add.send`), confirmação/erro (`watch.add.queued`, `watch.add.error`) |
| Complicação | Mostrador | WidgetKit (watchOS) | Circular, retangular e em linha: saldo e gasto do dia; respeita "Ocultar valores" |

`-startScreen` novos: `insights`, `scan` (abre Novo lançamento com a leitura), `settings.openfinance`. `-mockOpenFinance` liga o provedor fictício.

## Regras de comportamento da Fase 3

- **Insights são estatística local**, sem IA nem servidor. Gasto atípico: mês corrente acima da mediana dos até 6 meses anteriores com escore z modificado ≥ 3,5 e aumento ≥ R$ 50 (mínimo 3 meses de histórico). Previsão: saldo + entradas e saídas já previstas (pendentes, recorrências, faturas) − média diária de gastos variáveis dos últimos 60 dias. Cada card mostra o cálculo. "Ocultar valores" mascara os reais nos textos.
- **QR da NFC-e** traz UF, CNPJ e chave; o valor só existe em notas de contingência. Sem consulta à SEFAZ. O mesmo documento lido duas vezes avisa que já foi lançado.
- **Boleto com linha digitável inválida** não preenche valor nem data a partir dos dígitos e avisa.
- **Open Finance**: desligado por padrão; sem provedor real; consentimento explicado; revogação sempre disponível; transações deduplicadas por `externalId`.
- **Relógio**: lê o resumo enviado pelo iPhone; a despesa ditada é idempotente (`externalId` `watch:<id>`).

# Seletor global de período e atualizar

## Seletor de mês e ano (`MonthPicker`)

Componente no topo de Início, Lançamentos, Planejar > Orçamento, Planejar > A pagar, fatura do cartão (`wallet.cardInvoice`) e Relatórios. O estado é um só (`AppStore.viewedMonth`, não persistido: ao reabrir volta para o mês de hoje), então trocar o mês numa tela vale para as outras.

| Id | Tipo | Conteúdo |
|---|---|---|
| `period.picker` | Botão (título) | "Outubro de 2026" com seta para baixo; VoiceOver lê "Outubro de 2026, selecionar mês"; abre a sheet |
| `period.prev` / `period.next` | Botões ‹ › (44 pt) | Mês anterior/seguinte; desabilitados em 01/2000 e 12/2100 |
| `period.backToToday` | Chip | "Voltar para hoje"; só aparece quando o mês visualizado não é o atual |
| `period.sheet` | Sheet (média/grande) | "Selecionar mês", botão `period.today` ("Hoje"), ano com setas (`period.year.prev`, `period.year`, `period.year.next`; o ano também ajusta por VoiceOver) e grade 3x4 de meses `period.month.1` a `period.month.12` (mês selecionado com realce, mês atual com contorno). Tocar num mês aplica e fecha |

Quais telas seguem o mês visualizado e quais continuam no "agora":

| Segue `viewedMonth` | Continua no mês real (`currentMonth`/hoje) |
|---|---|
| Início: resultado do mês, receitas × despesas, "Para onde foi" e comparação com o mês anterior (estado vazio `home.month.empty` em mês sem dados; cartão de Insights só no mês atual) | Saldo em contas, "Próximos vencimentos" e Insights (previsões partem de hoje) |
| Lançamentos: o período padrão ("Este mês") é o mês visualizado; "Mês passado" e "Este ano" são relativos a ele; os filtros avançados continuam por cima | "Últimos 30 dias" conta a partir de hoje |
| Orçamento: limites, gastos, novo/editar orçamento e "Copiar do mês anterior" (do mês anterior ao visualizado para o visualizado) | Alertas de 80%/100% (`evaluateBudgetAlerts`) |
| A pagar: calendário e totais do mês (sem botões próprios de mês) | Status "atrasada/vence logo" (relativo a hoje) |
| Fatura do cartão: a aba do meio é a fatura do mês visualizado (no mês atual, a fatura vigente do cartão) | Lista de cartões em Carteira (fatura atual) |
| Relatórios: "Este mês", "Mês passado", "3 meses" e "Este ano" relativos ao mês visualizado | Período "Personalizado" |
| | Snapshot de patrimônio, início da mesada, fluxo de caixa, metas, dívidas |

Meses futuros mostram o que o Core já projeta (recorrências, parcelas, faturas); nada é inventado.

## Atualizar

- Botão `refresh.button` (ícone `arrow.clockwise`, rótulo "Atualizar") na barra de Início, Lançamentos, Planejar e Carteira. Gira enquanto atualiza e fica desabilitado; o valor de acessibilidade é "Atualizando" ou "Atualizado às HH:mm:ss".
- Puxar para baixo (`.refreshable`) em Início, Lançamentos (lista e estado vazio), Orçamento, A pagar, Metas, Mais, Contas, Cartões, Investimentos, Fatura do cartão, Insights, Relatórios, Patrimônio e Família. Não existe em sheets nem no Novo lançamento. Háptico leve ao concluir (iOS).
- `AppStore.refresh()`: recarrega do Repository (e republica os widgets), roda as tarefas idempotentes de abertura, reagenda lembretes e, com sincronização ligada e configurada (desligada por padrão), sincroniza. Não roda em paralelo nem com o app bloqueado. Toast "Atualizado" no máximo a cada 3 s; erro vira toast de aviso "Não foi possível atualizar. Tente de novo.".

### Correção: puxar para atualizar sem sobreposição

Causa raiz (reproduzida no Simulador com rajada de capturas, `docs/screenshots/refresh-bug/antes/`): o `MonthPicker` ficava fora da rolagem (`VStack { MonthPicker; ScrollView }`). No Início o título grande da navegação acompanha a rolagem e o seletor não, então ao puxar o título "Início" descia e passava por cima das setas e do mês do seletor; nas demais telas o conteúdo se descolava do seletor fixo. Correção: o seletor é o primeiro item de dentro do `ScrollView` (Início, Orçamento, A pagar, Relatórios, Fatura), então tudo acompanha o gesto; em Lançamentos ele continua no cabeçalho fixo junto da busca (lista com título inline), sem sobreposição. Além disso, o toast "Atualizado" não aparece mais no puxar para atualizar (o indicador e o háptico são o retorno), pois cobriria a barra de navegação no meio do movimento; no botão ele continua. Ids de linhas verificados estáveis (BillItem, Insight, DayGroup, transações por UUID). Evidência depois: `docs/screenshots/refresh-bug/depois/`.
