# Versão web (React + TypeScript + Vite)

Cliente web do App Finanças, com paridade do MVP e da Fase 2 do app iOS, mesma identidade visual "Cédula" (claro/escuro), responsivo (desktop com barra lateral, celular com barra de abas e botão "+") e acessível (rótulos, `aria-live`, foco visível, alvos de 44 px, valores lidos por extenso).

Código em `Web/`. Não há CDN em runtime: tudo é servido pela mesma origem.

## Como rodar (sem npm local: tudo em Docker)

```bash
cd "/Users/macbookpro/Documents/App Finance"
Web/scripts/dc.sh npm install          # volume nomeado financeweb_node_modules
Web/scripts/dc.sh npm test             # vitest (golden + codec + lógica + sincronização/atualizar)
Web/scripts/dc.sh npm run build        # tsc + vite build
Web/scripts/dc.sh npm run dev          # http://localhost:5173, /api -> API_URL (padrão http://localhost:8080)

docker compose up -d --build           # db + api + web (http://localhost:8080; /api via nginx -> api:3000)
Web/e2e/run.sh                         # E2E com Playwright em container contra o stack real
Web/tools/golden-gen/build.sh          # regenera os vetores dourados a partir do Core Swift (precisa de swiftc)
```

## Arquitetura

| Pasta | Conteúdo |
|---|---|
| `src/core` | Porte fiel de `FinanceApp/Core` (decimal.js, dia civil em UTC 12:00): saldos, parcelas, recorrência, fatura de cartão, orçamento, resumo, fluxo de caixa, dívidas (avalanche × bola de neve), metas, investimentos, patrimônio, divisão e acerto, família, relatórios, IR, importação OFX/CSV, exportação CSV, sugestão de categoria e regra de conflito de sincronização. Dinheiro nunca é `number`. |
| `src/core/codec.ts` | Converte o JSON Codable do Swift (datas = segundos desde 2001-01-01, `Decimal` = número JSON, UUID maiúsculo, campos nulos ausentes) para o domínio e de volta. É o que faz web e iOS trocarem os mesmos documentos. |
| `src/app` | Estado (zustand), IndexedDB (`db.ts`), cliente da API (`api.ts`), sincronização (`syncClient.ts`), botão Atualizar (`refresh.ts`), regras de tela (`logic.ts`), operações de negócio (`actions.ts`), dados de exemplo (`seed.ts`). |
| `src/ui`, `src/screens` | Componentes, gráficos SVG próprios e as telas. |
| `test/` | vitest. `test/golden/*.json`: vetores gerados pelo Core Swift real. |
| `tools/golden-gen` | Executável Swift (compilado com `swiftc` junto de `Core/*.swift`) que imprime os vetores. |
| `e2e/` | Playwright (container) contra o stack real. |
| `Dockerfile`, `nginx.conf` | Build em `node:22`, servido por `nginx:alpine` (porta 80, gzip, CSP e cabeçalhos de segurança, fallback SPA, `location /api/ { proxy_pass http://api:3000; }`). O `docker-compose.yml` da raiz referencia `./Web`. |

## Telas

Login/cadastro (ou uso sem conta), onboarding, Início, Lançamentos (busca, filtros, agrupado por dia, detalhe, edição, exclusão de parcelas por escopo), Novo/editar lançamento (parcelas, recorrência, tags, cartão, sugestão de categoria, aprovação de dependente), Contas (conciliação), Cartões (fatura, limite, pagar fatura total/mínimo/outro valor), Orçamento (alertas 80%/100%), Contas a pagar (calendário), Metas (aportes, histórico, projeção), Dívidas (simulador), Investimentos e Patrimônio, Fluxo de caixa 30/60/90, Relatórios (CSV), Imposto de Renda, Importação OFX/CSV com deduplicação, Categorias, Família (pessoas, privacidade, divisão e acerto, mesada, aprovações, convites da conta) e Configurações (tema, ocultar valores, backup JSON, exportar CSV, dados de exemplo).

## Offline-first e sincronização

- Tudo é gravado primeiro no IndexedDB (`entities`) e enfileirado (`queue`). Funciona sem rede.
- Contrato (`Backend/openapi.yaml`): `POST /api/sync` envia a fila em lotes de 200 (`updatedAt` do envelope em ISO 8601; `data` = documento do Core sem alteração); `GET /api/sync?since=<token>` traz o que mudou (guarda-se o token do GET; `hasMore` repete). Exclusão = `deleted: true` (e também um `Tombstone`, como no Core).
- Conflito: vence o maior `updatedAt` (empate: exclusão vence, depois JSON canônico). `rejected` com `serverRecord` é aplicado localmente.
- Edição durante o envio não perde alteração: só sai da fila o que tem o mesmo `updatedAt` enviado.
- Tokens: access token (15 min) renovado com o refresh token (rotativo); sessão em IndexedDB. Dados de outro usuário nunca se misturam (troca de usuário limpa os dados locais).
- IDs são gerados em maiúsculas (como o Swift); há fallback quando `crypto.randomUUID` não existe (http fora de localhost).

## Botão "Atualizar"

No cabeçalho de todas as telas (ícone de setas circulares, rótulo acessível "Atualizar", dica "R"):

- força `syncNow()` (push da fila + pull desde o último token) e relê os dados do IndexedDB (`src/app/refresh.ts`);
- gira enquanto executa e fica desabilitado: cliques repetidos compartilham a mesma execução (sem requisições paralelas);
- resultado em região `aria-live`: "Atualizado às HH:MM", ou erro em português; offline mostra "Sem conexão... as alterações serão enviadas quando a rede voltar" e os dados locais continuam; sem conta, apenas recarrega os dados locais;
- atalho de teclado **R** (ignorado dentro de campos de texto e com diálogo aberto);
- celular: gesto de **puxar para atualizar** no topo da página (alternativa ao botão, que continua sendo o caminho acessível), com a mensagem também como aviso visual;
- respeita "reduzir movimento" (sem animação de giro).

## Verificação real (20/10/2026)

- `npm test` (Docker): vitest, 388 testes, dos quais 365 vetores dourados gerados pelo Core Swift real (mais 1 teste de cobertura), codec, lógica de tela e sincronização/Atualizar com IndexedDB falso e `fetch` simulado.
- Build (`tsc` + `vite build`) e `docker compose up -d --build web` ok; `GET /` e `/api/health` pelo nginx (8080).
- E2E (`Web/e2e/run.sh`, Playwright/Chromium em container, contra API + Postgres reais): cadastro, onboarding, lançamento, dashboard, busca, Atualizar (cliques, atalho R, offline, reconexão), conferência do registro no servidor (valor, data em segundos desde 2001, `updatedAt` ISO), segundo dispositivo, puxar para atualizar por toque, exportação CSV e simulador. Capturas em `docs/web-screenshots/` (desktop 1440 e celular 390, claro e escuro).

## Limitações conhecidas

- Fase 3 do iOS (insights, QR de NFC-e, OCR, Open Finance, Apple Watch, widgets) não foi portada.
- Sem bloqueio por PIN/biometria, notificações de vencimento nem anexos/comprovantes.
- Decimais trafegam como número JSON (como no Core): valores acima de ~1e15 perdem precisão.
- O tie-break de conflitos com `updatedAt` idêntico usa JSON canônico próprio; só coincide byte a byte com o do Swift/servidor quando os dois escolhem o mesmo vencedor (raro).
- A CSP usa `style-src 'unsafe-inline'` por causa de estilos dinâmicos (largura de barras, cores de categoria).
