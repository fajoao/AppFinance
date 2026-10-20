# Preparação para a App Store (Fases 2 e 3)

Marcas: **[dono]** depende de você (conta, decisões, arquivos que só você tem). **[repo]** já está no repositório.
**[verificar]** não foi possível confirmar neste ambiente (sem Xcode, Simulador, App Store Connect ou aparelho).

## 1. Itens que dependem do dono

- [ ] **[dono] Conta no Apple Developer Program** (paga, anual). Necessária para aparelho real, TestFlight, App Groups, iCloud e publicação.
- [ ] **[dono] Bundle id definitivo.** Hoje é o placeholder `com.example.financas` (e `.widgets`, `.tests`, `.uitests`). Troque em:
  `project.yml` (todos os alvos), `SharedContainer.appGroupID` (`Core/Widgets.swift`), `CloudKitConfig.containerID`
  (`App/Services/CloudKitSyncService.swift`), serviço do Keychain (`KeychainSecrets`) e os `kind` dos widgets (`Widgets/FinanceWidgets.swift`, opcional).
- [ ] **[dono] Team ID.** `DEVELOPMENT_TEAM` em `project.yml` (linha comentada) ou Signing & Capabilities.
- [ ] **[dono] App Group** `group.<seu bundle id>`: crie no portal (Identifiers > App Groups) e associe ao app e à extensão de widgets.
  Sem ele os widgets mostram "Abra o Finanças para ver seus dados" e nada quebra.
- [ ] **[dono] Ícone do app.** `Assets/Assets.xcassets/AppIcon.appiconset` está vazio (só declara o slot 1024x1024). Entregue um PNG 1024x1024,
  sem transparência e sem cantos arredondados.
- [ ] **[dono] Nome na loja, subtítulo, descrição, palavras-chave, categoria (Finanças), URL de suporte e URL da política de privacidade** (seção 3).
- [ ] **[dono] iCloud/CloudKit**, só se for oferecer sincronização: `docs/cloudkit-setup.md`. A descrição da loja não deve prometer convite de membros.
- [ ] **[dono] Revisão jurídica** do texto de privacidade e dos termos (o texto abaixo é base, não parecer jurídico).
- [ ] **[dono] Contato do encarregado (LGPD)**, se aplicável, e dados do controlador (nome/CNPJ/CPF e e-mail).

## 2. Build e testes antes de enviar

- [ ] **[verificar]** `cd FinanceApp && xcodegen && open FinanceApp.xcodeproj`; compilar o esquema `FinanceApp` para um iPhone com iOS 17+.
  O código SwiftUI só foi checado por tipos contra o SDK do macOS (`scripts/typecheck-app.sh`); trechos `#if os(iOS)` não foram compilados.
- [ ] **[verificar]** Rodar `FinanceAppTests` (lógica, 100+ casos) e `FinanceAppUITests` (fluxos, incluindo Fase 2) no Simulador.
- [ ] **[verificar]** Widgets: adicionar os 3 widgets na tela de início, mudar dados no app e conferir a atualização; testar com "ocultar valores".
- [ ] **[verificar]** Atalho "Adicionar despesa" na Siri e no app Atalhos (pode ser preciso abrir o app uma vez).
- [ ] **[verificar]** PDF: exportar relatório e IR, abrir em Arquivos e conferir paginação. CSV abre no Excel pt-BR (BOM, `;`).
- [ ] **[verificar]** Comprovante: `PhotosPicker` no aparelho; foto some do disco ao excluir o lançamento.
- [ ] **[verificar]** Dynamic Type grande, modo escuro, VoiceOver nas telas novas (gráficos têm rótulo resumido).
- [ ] **[verificar]** Archive em Release, validar no Organizer, enviar ao TestFlight (testadores internos primeiro).

## 3. Política de privacidade (texto-base, pt-BR, LGPD)

> Revise com um profissional antes de publicar. Substitua os trechos entre `[colchetes]`. Publique em uma URL pública e informe no App Store Connect.

**Política de Privacidade do aplicativo Finanças**
Última atualização: [data].

**1. Quem somos.** O Finanças é desenvolvido por [nome ou razão social], [CPF/CNPJ], contato: [e-mail]. Para a Lei Geral de
Proteção de Dados (Lei nº 13.709/2018, "LGPD"), [nome] é o controlador dos dados tratados por este aplicativo, nos limites descritos abaixo.

**2. Quais dados o aplicativo trata.** Os dados que você mesmo cadastra: contas, saldos, lançamentos, categorias, cartões, orçamentos,
metas, dívidas, investimentos, perfis de familiares (nome, papel e, opcionalmente, e-mail), comprovantes (fotos que você anexar) e
preferências do aplicativo. O aplicativo não acessa sua conta bancária, seus contatos nem sua localização.

**3. Onde os dados ficam.** Por padrão, **somente no seu aparelho**. Não enviamos seus dados a servidores do desenvolvedor, não usamos
ferramentas de rastreamento, publicidade ou análise de terceiros e não vendemos nem compartilhamos dados.
O código do aplicativo (PIN) é guardado no Keychain do aparelho, nunca em texto aberto.

**4. Sincronização opcional com o iCloud.** Se você ligar a sincronização em Ajustes, seus dados passam a ser gravados no **seu banco
privado do iCloud**, operado pela Apple, sob os termos da Apple e com a sua conta. Nós não temos acesso a esse conteúdo. Você pode desligar
a sincronização a qualquer momento; os dados já enviados permanecem no iCloud até você removê-los nas configurações do iCloud.

**5. Finalidades e bases legais.** Tratamos os dados exclusivamente para fornecer as funções que você usa (controle financeiro pessoal e
familiar, relatórios, lembretes, widgets e atalhos), com base na execução do contrato de uso do aplicativo (art. 7º, V, LGPD) e, quando
aplicável, no seu consentimento (art. 7º, I), por exemplo ao ligar a sincronização ou criar perfis de familiares.

**6. Crianças e adolescentes.** O aplicativo não é direcionado a crianças. O recurso de "dependente" é gerenciado por um responsável adulto,
que decide quais dados do menor cadastrar (art. 14, LGPD). Responsáveis devem ter o consentimento adequado para tratar dados do menor.

**7. Compartilhamento.** Não compartilhamos dados com terceiros. Ao exportar PDF ou CSV, ou usar a folha de compartilhamento do iOS, os arquivos
vão para onde você escolher, por sua conta e responsabilidade.

**8. Seus direitos (art. 18, LGPD).** Você pode confirmar o tratamento, acessar, corrigir, exportar (Ajustes > Exportar CSV; relatórios em PDF e CSV),
eliminar (Ajustes > Apagar todos os dados), revogar consentimento e pedir informações sobre compartilhamento. Como os dados ficam com você,
a maior parte pode ser exercida diretamente no aplicativo. Para outras solicitações: [e-mail do encarregado/contato].

**9. Retenção.** Os dados ficam enquanto o aplicativo estiver instalado ou até você apagá-los. Desinstalar o aplicativo remove os dados locais;
cópias no iCloud ou em backups do aparelho seguem as regras da Apple.

**10. Segurança.** Bloqueio por Face ID/Touch ID, código do aparelho e PIN próprio opcional; dados em arquivo protegido pelo iOS; valores
podem ser ocultados na tela e no widget. Nenhuma medida elimina todo o risco; mantenha seu aparelho atualizado e protegido.

**11. Alterações.** Podemos atualizar esta política; a data no topo indica a versão vigente.

**12. Contato e reclamações.** [e-mail]. Você também pode contatar a Autoridade Nacional de Proteção de Dados (ANPD).

## 4. Privacy manifest (`Assets/PrivacyInfo.xcprivacy`): revisão da Fase 2

Revisão feita por busca no código (não substitui a verificação do Xcode, que gera o "Privacy Report" ao arquivar):

| API de "razão obrigatória" | Usada? | Entrada no manifesto |
|---|---|---|
| UserDefaults (preferências em `UserDefaultsPreferences`) | Sim | `NSPrivacyAccessedAPICategoryUserDefaults`, motivo `CA92.1` (já presente) |
| Timestamps de arquivo (`creationDate`, `attributesOfItem`...) | Não | Nenhuma |
| Tempo de atividade do sistema (`systemUptime`, `mach_absolute_time`) | Não | Nenhuma |
| Espaço em disco | Não | Nenhuma |
| Teclado ativo | Não | Nenhuma |

Outros pontos:

- `NSPrivacyTracking = false`, sem domínios de rastreamento, **`NSPrivacyCollectedDataTypes` vazio**: o app não coleta dados no sentido da Apple
  (nada vai para servidores do desenvolvedor). **[verificar]** Com a sincronização por CloudKit ligada, a orientação da Apple é que dados no banco
  privado do usuário não contam como coletados pelo desenvolvedor; confirme ao preencher o questionário.
- Extensão de widgets: lê só um arquivo JSON do App Group, sem APIs de razão obrigatória; não precisa de manifesto próprio. **[verificar]** no Privacy Report.
- Frameworks de terceiros: nenhum (nem SPM, nem CocoaPods).
- PhotosPicker roda fora do processo e não exige `NSPhotoLibraryUsageDescription`. Face ID: `NSFaceIDUsageDescription` já está no `Info.plist`.
- Criptografia: `ITSAppUsesNonExemptEncryption = false`. O app usa SHA-256 (CryptoKit) apenas para derivar o hash do PIN e HTTPS/iCloud é da Apple.
  **[verificar]** a resposta de conformidade de exportação ao enviar a build.

## 5. App Privacy ("rótulo de nutrição") no App Store Connect

- Coleta de dados: **Dados não coletados** (condição: nenhuma análise, anúncio ou SDK de terceiros; ver ressalva do CloudKit na seção 4).
- Rastreamento: **não**.
- URL da política de privacidade: obrigatória.

## 6. Classificação etária

O app não tem conteúdo violento, sexual, apostas, acesso irrestrito à web, conteúdo gerado por usuários compartilhado entre pessoas nem compras
dentro do app. Resposta esperada ao questionário: **todas as perguntas "Nenhum"**, resultando em **4+**.
**Não** marque a "Categoria Crianças": o app serve a adultos e apenas permite perfis de dependentes administrados por um responsável.
**[verificar]** O questionário muda com frequência; confirme no App Store Connect.

## 7. Capturas de tela necessárias

O app é só iPhone (`TARGETED_DEVICE_FAMILY: 1`), então **não há capturas de iPad**.
**[verificar]** Os tamanhos exigidos mudam; em geral basta o conjunto de **6,9"** (por exemplo 1320 x 2868, iPhone 16/17 Pro Max) e opcionalmente 6,5"/6,3".
Capture em **pt-BR**, com dados de demonstração (`-seedDemo`, `-seedFamily`, `-fixedToday 2026-10-19`), claro e escuro.

Telas sugeridas (5 a 10, nesta ordem), todas geradas por `testScreenshotTourLight/Dark` e pelos testes da Fase 2 (`scripts/capture-screenshots.sh`):

1. Início (saldo e para onde foi o dinheiro) - `home.dashboard`
2. Novo lançamento com categoria sugerida - `transaction.new`
3. Orçamento com alerta - `plan.budget`
4. Simulador de quitação de dívidas - `plan.debts.simulator`
5. Fluxo de caixa 90 dias - `plan.cashflow`
6. Família: acerto de contas - `family.settle`
7. Investimentos e alocação - `wallet.investments`
8. Patrimônio líquido - `wallet.networth`
9. Relatório / resumo do IR - `reports.main`, `reports.tax`
10. Widgets na tela de início (captura manual no Simulador)

## 8. Texto de revisão da App Store ("Notas para o revisor")

- Não há login. O app funciona offline e guarda tudo no aparelho.
- Para ver todas as telas com dados de exemplo, abra o app e conclua o onboarding; em Ajustes > Dados use "Usar extrato de exemplo".
  (Os dados de demonstração completos só existem nos argumentos de build de teste.)
- Face ID/PIN são opcionais.
- Sincronização com iCloud: [liga/desliga conforme a versão enviada].

## 9. TestFlight

1. Archive (Release) > Distribute > App Store Connect > Upload.
2. Grupo interno (até 100 pessoas da equipe) sem revisão; externo exige revisão da Beta App Review e "Informações do teste".
3. Colete: travamentos (Xcode Organizer), feedback de acessibilidade, comportamento dos widgets e da Siri em aparelhos reais.
4. Só depois: enviar para revisão com a política de privacidade publicada e as capturas.

## 10. Fase 3: permissões e privacidade

| Item | Estado |
|---|---|
| `NSCameraUsageDescription` (leitura do QR Code da NFC-e) | Já no `project.yml` e `project-free.yml`. Texto: "O Finanças usa a câmera só para ler o QR Code da nota fiscal (NFC-e). A imagem não é gravada nem enviada." O pedido de permissão só aparece quando a pessoa toca em "Ler QR Code". |
| Fotos (OCR de comprovante) | `PhotosPicker` fora do processo: não exige `NSPhotoLibraryUsageDescription`. |
| Microfone no Apple Watch (`NSMicrophoneUsageDescription`) | Declarado no alvo do relógio (`FinanceWatch`). O ditado é feito pelo sistema. |
| Reconhecimento de texto (Vision) e QR | 100% no aparelho; nada é enviado. |
| Open Finance | **Desligado e sem provedor.** Se um dia for integrado: atualizar o rótulo de privacidade ("Dados financeiros" vinculados ao usuário, coletados pelo seu backend), a política de privacidade e o `PrivacyInfo.xcprivacy`; ver `docs/open-finance.md`. Hoje o app continua sem coletar dados. |
| Insights | Estatística local; não há IA nem envio de dados. Texto do app deixa claro que não é recomendação financeira. |
| Apple Watch | Exige App ID próprio do relógio e App Groups (conta paga). Conta gratuita: o alvo do relógio não está no `project-free.yml`. |
| Notas para o revisor | Informar que a câmera só lê QR Code de nota fiscal e que o Open Finance está desativado neste build. |
