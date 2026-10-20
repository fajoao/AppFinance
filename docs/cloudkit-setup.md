# Sincronização com o iCloud (CloudKit): o que configurar no Xcode

**Estado atual: a sincronização está DESLIGADA por padrão e NÃO foi testada contra um container real.**
O ambiente em que o código foi escrito não tem Xcode, SDK do iOS, conta de desenvolvedor nem iCloud. O que existe:

| Peça | Onde | Estado |
|---|---|---|
| Contrato `SyncService`, token, estado, erros | `FinanceApp/Core/Sync.swift` | Pronto e testado (swiftc) |
| Regra de conflito por `updatedAt` + tombstones de exclusão (`SyncEngine.merge`) | `Core/Sync.swift`, `CoreTests/SyncTests.swift` | Pronto e testado com servidor em memória (`InMemorySyncService`) |
| Coordenador (`SyncCoordinator`): pull, merge, restore, push; falha não altera os dados | `Core/Sync.swift` | Pronto e testado |
| `CloudKitSyncService` (zona privada `FinanceZone`, um `CKRecord` por entidade com JSON em `payload`) | `App/Services/CloudKitSyncService.swift` | **Compila (typecheck no SDK do macOS). Nunca executado.** |
| Convite de membros por `CKShare` (`makeHouseholdShare`) | mesmo arquivo | **Apenas esboço.** Falta aceitar o convite e ler/escrever pelo `sharedCloudDatabase` |
| Tela Ajustes > Sincronização | `App/Features/Settings/SyncSettingsView.swift` | Pronta; o botão fica desabilitado sem serviço configurado |

Por que o `CloudKitSyncService` não é instanciado por padrão: criar um `CKContainer` sem o entitlement derruba o app.
A fábrica `makeSyncService()` só devolve o serviço se o projeto for compilado com a condição `CLOUDKIT_ENABLED`.

## Passo a passo (uma vez, no Xcode, com a conta de desenvolvedor)

1. **Bundle id e Team.** Troque `com.example.financas` pelo seu bundle id em `project.yml` (app, widgets, testes) e defina
   `DEVELOPMENT_TEAM`. Rode `xcodegen`.
2. **Container do iCloud.** Escolha o id do container, por exemplo `iCloud.br.com.seudominio.financas`.
   - Altere `CloudKitConfig.containerID` em `App/Services/CloudKitSyncService.swift`.
3. **Capability iCloud.** Alvo `FinanceApp` > Signing & Capabilities > `+ Capability` > **iCloud** > marque **CloudKit** e
   adicione o container acima.
   - Equivale a descomentar em `project.yml`, no alvo `FinanceApp`, as chaves de entitlements:
     ```yaml
     com.apple.developer.icloud-container-identifiers: [iCloud.br.com.seudominio.financas]
     com.apple.developer.icloud-services: [CloudKit]
     ```
     (e rodar `xcodegen` de novo). O arquivo gerado é `Assets/FinanceApp.entitlements`.
4. **Notificações silenciosas (opcional, recomendado).** Capability **Background Modes** > **Remote notifications**, para o app
   receber avisos de mudança do CloudKit. Sem isso a sincronização acontece ao abrir o app e pelo botão "Sincronizar agora".
5. **Habilitar o código.** Em `project.yml`, no alvo `FinanceApp`, descomente
   `SWIFT_ACTIVE_COMPILATION_CONDITIONS: "$(inherited) CLOUDKIT_ENABLED"` (ou adicione `CLOUDKIT_ENABLED` em Build Settings >
   Swift Compiler - Custom Flags). Compile e rode em um aparelho com uma conta iCloud logada.
6. **CloudKit Dashboard** (https://icloud.developer.apple.com). Abra o container:
   - Rode o app uma vez em **Development**: o tipo de registro de cada entidade (`Account`, `Transaction`, ...) é criado
     automaticamente no ambiente de desenvolvimento ao primeiro envio. Os campos usados são `payload` (Bytes) e `updatedAt` (Date/Time).
   - Antes de publicar na App Store, faça **Deploy Schema to Production**. Sem isso, a versão de produção não sincroniza.
7. **Ligue em Ajustes > Sincronização.** Teste com dois aparelhos (ou aparelho + Simulador logado na mesma conta).

## Convite de membros (CKShare): o que falta

O esboço cria um `CKShare` da zona inteira (`CKShare(recordZoneID:)`). Para funcionar de ponta a ponta é preciso:

1. Apresentar `UICloudSharingController(share:container:)` com o retorno de `makeHouseholdShare(title:)`.
2. Declarar `CKSharingSupported = YES` no Info.plist e tratar o aceite (`windowScene(_:userDidAcceptCloudKitShareWith:)`),
   rodando `CKAcceptSharesOperation`.
3. Fazer a pessoa convidada ler e gravar pelo `container.sharedCloudDatabase` (hoje o serviço usa só o `privateCloudDatabase`).
4. Mapear o `FamilyMember` ao participante do share e aplicar papéis (admin/membro/dependente) também no servidor: hoje os papéis
   são regras do app, não permissões do CloudKit. **Um membro com acesso ao share consegue ler tudo que está na zona**, inclusive
   contas marcadas como privadas. Para privacidade real entre membros é preciso separar as zonas (uma compartilhada e uma privada por pessoa).

Enquanto isso não estiver feito, não prometa "convite de membros" na descrição da loja.

## Riscos e limites conhecidos

- A resolução de conflito depende do relógio dos aparelhos (`updatedAt`). Relógio errado pode fazer uma edição antiga vencer.
- Empate de `updatedAt` com conteúdo diferente: o desempate é determinístico (JSON maior vence) para os dois aparelhos convergirem.
- Exclusões são propagadas por tombstones (`Tombstone`), que hoje nunca são podados.
- O envio manda os registros alterados desde a última sincronização (por `updatedAt` local); a primeira sincronização envia tudo.
- Limite do CloudKit: 400 registros por operação (o código envia em lotes de 300) e 1 MB por registro.
- `.ifServerRecordUnchanged`: se outro aparelho gravar entre o `pull` e o `push`, o registro é ignorado e reconciliado na próxima rodada.
