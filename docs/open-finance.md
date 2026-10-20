# Open Finance: desenho recomendado

> **Estado: NÃO integrado.** O app define o contrato (`BankConnectionProvider`), o mapeamento testado de transações e um
> `MockBankProvider` com dados FICTÍCIOS. Nenhum provedor real está ligado, e a funcionalidade vem **desligada por padrão**
> (tela Ajustes > Open Finance, com o consentimento explicado). Nada aqui foi testado contra um banco ou provedor real.

## O que existe no código

| Peça | Onde | Verificado |
|---|---|---|
| Protocolo `BankConnectionProvider` (instituições, iniciar consentimento, consultar conexão, contas, transações, revogar) | `FinanceApp/Core/OpenFinance.swift` | Compila; contrato exercitado só pelo mock |
| `BankTransactionMapper`: transação do provedor -> `Transaction`, valor em `Decimal`, saída negativa vira despesa, datas no fuso de Brasília, ignora pendentes, outra moeda, valor zero e id vazio | idem | Testado (`OpenFinanceTests`) |
| Deduplicação: `externalId = "of:<provedor>:<id>"`; repetidos no lote e já importados são descartados; igual a um lançamento manual (mesmo dia, valor e descrição parecida) vira "provável duplicata" e **não** é importado | idem | Testado |
| `BankSyncService`: bloqueia consentimento pendente, revogado, expirado, sem escopo de transações | idem | Testado com o mock |
| `MockBankProvider` (actor): dois bancos fictícios, duas contas, transações com USD, pendente e id repetido; falha injetável | idem | Testado |
| `OpenFinanceModel` + tela de consentimento | `App/Store/OpenFinanceModel.swift`, `App/Features/Settings/OpenFinanceView.swift` | Lógica testada; tela só no simulador |

Sem provedor, a tela mostra o consentimento e o aviso de indisponibilidade, e o botão fica desabilitado. O mock só aparece com o
launch argument `-mockOpenFinance` (testes e capturas); **nunca** é ligado em produção.

## Arquitetura recomendada para um provedor real

```
App iOS  <--HTTPS (token do SEU backend)-->  Backend próprio  <--mTLS / OAuth2-->  Provedor Open Finance  <-->  Bancos
```

1. **Backend intermediário é obrigatório.** O `client_id`/`client_secret`, os certificados (Open Finance usa mTLS e FAPI) e os
   tokens de acesso e de atualização dos bancos ficam **só no servidor**. Um segredo embutido num app iOS é extraível; um token
   de cliente no aparelho dá acesso aos dados bancários de quem o roubar.
2. O app fala com o backend por uma API sua (autenticada por sessão do usuário, por exemplo Sign in with Apple), que implementa as
   mesmas operações de `BankConnectionProvider`. Uma implementação concreta no app seria um `URLSession` fino sobre essa API.
3. **Consentimento:** o backend inicia o consentimento no provedor e devolve a `authorizationURL`; o app abre
   `ASWebAuthenticationSession`, o usuário autentica **no ambiente do banco** (o app nunca vê a senha) e volta por um Universal Link.
   O app então consulta `connection(id:)` até ficar `.active`.
4. **Sincronização:** o backend busca e guarda o mínimo necessário e responde `transactions(...)`; o app grava só `Transaction`s
   (já deduplicadas). Para atualizações em segundo plano, o backend pode mandar uma notificação silenciosa.
5. **Revogação:** `revokeConsent` chama o backend, que revoga no provedor e **apaga** tokens e dados em cache. O usuário também pode
   revogar no app do banco ou no portal do Open Finance; `connection(id:)` deve refletir isso (`.revoked`).
6. **Expiração:** consentimento vale no máximo 12 meses (o padrão do app é 90 dias). `.expired` pede nova autorização.

## LGPD e privacidade

- **Base legal:** consentimento específico, destacado e revogável (art. 7º, I e art. 8º). A tela de consentimento lista os escopos
  (contas, saldos, transações), a finalidade e a validade, e começa desligada.
- **Minimização:** peça só os escopos usados (o mock respeita isso: sem escopo de saldo, a conta vem sem saldo).
- **Papéis:** com backend próprio, você é **controlador** (e o provedor, operador ou controlador conjunto, conforme o contrato).
  Isso exige política de privacidade atualizada, registro das operações, canal do titular, prazo de retenção e plano de incidentes.
  Revise com assessoria jurídica; este documento não é parecer.
- **Local por padrão:** hoje o app não envia nada a servidores. Ligar o Open Finance muda isso (o backend passa a tratar dados
  bancários) e obriga a atualizar `docs/app-store-checklist.md` (rótulo de privacidade: "Dados financeiros", vinculados ao usuário)
  e o `PrivacyInfo.xcprivacy`.
- **Direitos do titular:** exportar (CSV já existe), apagar (Ajustes > Apagar todos os dados + exclusão no backend), revogar.

## Custos e requisitos (estimativa de ordem de grandeza; confirme com os provedores)

- **Regulatório:** só instituições autorizadas pelo Banco Central participam como receptoras de dados. Um app de finanças pessoais
  normalmente entra via **agregador/iniciador** já regulado, que cobra por conexão ou por consulta (planilha de preços sob contrato).
- **Técnico:** contrato e homologação com o provedor, certificados, backend com banco de dados criptografado, monitoramento,
  tratamento de falhas dos bancos (cada um tem janelas e limites próprios) e suporte.
- **Operacional:** custo por usuário ativo e por sincronização; planeje cobrar (plano pago) ou limitar a frequência.
- **App Store:** a revisão pede justificativa de dados financeiros e política de privacidade pública e correta.

## Para implementar de verdade (resumo)

1. Escolher o provedor e assinar contrato; obter ambiente de sandbox.
2. Construir o backend (OAuth2/FAPI, mTLS, armazenamento criptografado, webhooks).
3. Criar `BackendBankProvider: BankConnectionProvider` no app apontando para a API do backend (sem segredos no app).
4. Trocar o `provider` do `OpenFinanceModel` em `Production.makeStore`, mantendo o `nil` como padrão enquanto o toggle estiver desligado.
5. Testar ponta a ponta no sandbox; só então atualizar o rótulo de privacidade e liberar a tela.
