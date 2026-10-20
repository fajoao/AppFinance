# C4 nível 2: contêineres

Mostra o que é implantável ou executável dentro do App Finanças e como as partes se falam. O núcleo financeiro (`Core`) é uma biblioteca compilada dentro do app iOS, então aparece no nível de componentes, não aqui.

**Estado:** a linha do app iOS para a API ainda não está ligada. Hoje o app iOS guarda os dados só no aparelho.

```mermaid
C4Container
  title Contêineres: App Finanças

  Person(usuario, "Usuário ou família", "Controla as finanças")
  System_Ext(cloudflare, "Cloudflare Tunnel", "Acesso público por HTTPS")

  System_Boundary(appFinancas, "App Finanças") {
    Container(ios, "App iOS", "Swift 6, SwiftUI", "App principal, funciona sem servidor")
    ContainerDb(arquivoLocal, "data.json", "JSON atômico", "Dados locais do aparelho")
    Container(widgets, "Widgets", "WidgetKit", "Saldo, gasto do dia, vencimento")
    Container(relogio, "App do relógio", "watchOS", "Saldo e despesa por ditado")

    Container(web, "Versão web", "React, TypeScript", "Mesmas telas do MVP no navegador")
    ContainerDb(indexedDb, "IndexedDB", "Navegador", "Dados offline e fila de sync")
    Container(nginx, "Servidor web", "nginx", "Entrega a SPA e encaminha /api")

    Container(api, "API", "Node 22, Fastify", "Autenticação e sincronização")
    ContainerDb(banco, "Banco de dados", "Postgres 16, JSONB", "Registros por household")
  }

  Rel(usuario, ios, "Usa")
  Rel(usuario, web, "Usa", "HTTPS")
  Rel(ios, arquivoLocal, "Lê e grava", "JSON")
  Rel(ios, widgets, "Publica resumo para", "App Group")
  Rel(ios, relogio, "Envia resumo para", "WatchConnectivity")
  Rel(web, indexedDb, "Lê e grava", "IndexedDB")
  Rel(web, nginx, "Carrega a SPA e chama /api", "HTTPS")
  Rel(nginx, api, "Encaminha /api para", "HTTP")
  Rel(cloudflare, api, "Entrega requisições à", "HTTP")
  Rel(api, banco, "Lê e grava registros em", "SQL")
  Rel(ios, api, "Sincronizará com (planejado)", "HTTPS e JWT")

  UpdateRelStyle(ios, api, $textColor="orange", $lineColor="orange")
  UpdateLayoutConfig($c4ShapeInRow="3", $c4BoundaryInRow="1")
```
