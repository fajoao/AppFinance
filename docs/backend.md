# Backend (Postgres + API)

## Por que o Postgres não fica "exposto" à internet (5 linhas)
1. O app iOS e o app web não falam o protocolo do Postgres; eles falam HTTP. Quem fala com o banco é a API.
2. Embutir usuário/senha do banco no app (ou no JavaScript do site) entrega o banco inteiro a qualquer pessoa que abra o binário.
3. Postgres aberto na internet recebe varredura e força bruta em minutos; a API tem login, JWT, rate limit, bloqueio e isolamento por household.
4. Por isso o Postgres só existe na rede interna do Docker e é publicado apenas em `127.0.0.1:5433` (administração local com `psql`).
5. A internet entra por HTTPS na API (Cloudflare Tunnel, sem abrir portas no roteador). Se precisar de acesso remoto ao banco, use SSH tunnel/VPN, nunca a porta aberta.

## Arquitetura
```
iOS / Web --HTTPS--> Cloudflare Tunnel --> api:3000 --> db:5432 (rede interna "backend")
                                          web:80 (proxy /api -> api:3000)
```
Serviços (`docker-compose.yml`): `db` (postgres:16-alpine, volume `pgdata`), `api` (Node 22 + Fastify, usuário não-root, FS somente leitura), `web` (build de `./Web`, 127.0.0.1:8080), `tunnel` (perfil `tunnel`), `tunnel-named` (perfil `tunnel-named`), `api-test` (perfil `test`).

## Subir (comandos exatos)
```bash
cd "/Users/macbookpro/Documents/App Finance"
cp .env.example .env   # só na primeira vez; troque as senhas: openssl rand -hex 24 / 48
docker compose up -d --build db api          # + web quando Web/ existir:  docker compose up -d --build
curl http://127.0.0.1:3000/api/health         # {"status":"ok","db":"up"}
```
As migrações (`Backend/db/migrations/*.sql`) rodam sozinhas ao subir a API (checksum + advisory lock; migração já aplicada não pode ser editada: crie `004_...sql`).

Acesso pela internet (quick tunnel, sem conta):
```bash
docker compose --profile tunnel up -d tunnel
docker compose logs tunnel | grep trycloudflare.com    # URL https://xxxx.trycloudflare.com
curl https://xxxx.trycloudflare.com/api/health
docker compose --profile tunnel stop tunnel            # desliga o acesso público
```
- A URL do quick tunnel **muda a cada subida** e é **pública** (qualquer pessoa com o link alcança a API; proteção = login + rate limit). Para expor também o site, defina `TUNNEL_TARGET=http://web:80` no `.env` (o Web faz proxy de `/api`).
- Túnel estável com domínio próprio: Cloudflare Zero Trust > Networks > Tunnels > criar túnel, apontar o hostname (ex. `api.seudominio.com`) para `http://api:3000` (ou `http://web:80`), copiar o token para `TUNNEL_TOKEN` no `.env` e rodar `docker compose --profile tunnel-named up -d tunnel-named`. Depois ajuste `CORS_ORIGINS` se o site ficar em outra origem.

Testes de integração (Postgres real, banco `finance_test`):
```bash
docker compose up -d db
docker compose --profile test run --rm --build api-test
```
Backup/restore: `Backend/scripts/backup.sh` (gera `backups/finance-AAAAMMDD-HHMMSS.dump`, modo 600) e `Backend/scripts/restore.sh backups/arquivo.dump` (destrutivo, pede confirmação).

## Modelo de dados e por que JSONB documental
- `users` (e-mail único em minúsculas, senha **argon2id**), `households`, `memberships` (papéis `admin|member|dependent`; um usuário = uma casa), `invites` (código de 8 caracteres, só o hash é guardado, uso único, 48 h), `refresh_tokens` (hash, rotação, detecção de reuso), `login_throttle` (bloqueio progressivo), `audit_log`.
- `records`: uma linha por entidade do Core, PK `(household_id, type, id)`; `type` ∈ Account, Category, Tag, Transaction, CreditCard, Invoice, Budget, Goal, GoalContribution, Debt, Investment, NetWorthSnapshot, Household, FamilyMember, ExpenseSplit, SplitSettlement, Allowance, ApprovalRequest, Tombstone. Colunas: `data jsonb`, `updated_at`, `deleted`, `owner_id`, `server_seq bigint` (sequence global = token de sincronização).
- **Por que JSONB**: o Core já persiste cada entidade como documento Codable (`Repository`) e o `SyncEngine` mescla entidades inteiras por `updatedAt` com tombstones. Um documento por linha espelha isso 1:1, o servidor não precisa conhecer cada campo, mudar o modelo do app não exige migração e push/pull viram upsert/consulta por `server_seq`. Para análise há views tipadas.
- Views (`003_views.sql`), sempre com `WHERE household_id = ...`: `v_transactions` (inclui `signed_amount`), `v_accounts`, `v_categories`, `v_monthly_by_category`, `v_credit_cards`, `v_budgets`, `v_goals`, `v_debts`, `v_investments`, `v_audit`. `app_ts()` converte datas do Core (segundos desde 2001) ou ISO 8601.
- Exemplo para um agente: `SELECT category_name, total FROM v_monthly_by_category WHERE household_id = '...' AND month = '2026-10-01';`

## Sincronização
- `GET /api/sync?since=N` entrega registros com `server_seq > N` e o novo `token` (use-o no próximo `since`; `hasMore` indica paginação). `POST /api/sync` aplica a regra do Core: maior `updatedAt` vence; empate: exclusão vence; empate restante: JSON canônico maior vence (determinístico); reenvio idêntico é idempotente. Delete = `deleted:true`.
- Gravações de um household são serializadas por advisory lock, então o `server_seq` é confirmado em ordem e o token nunca pula registros.
- O envelope usa `updatedAt` ISO 8601; `data` é o documento do Core sem alterações. Contrato completo: `Backend/openapi.yaml`.

## Segurança implementada
argon2id; JWT HS256 de 15 min (segredo só no `.env`, mínimo 32 caracteres, a API não sobe sem ele) e refresh token rotativo de 30 dias; membership e papel lidos do banco a cada requisição; isolamento por `household_id` em toda consulta; zod estrito + limites (500 registros/lote, 64 KB/registro, 2 MB/corpo); rate limit (geral 300/min, login 10/min, cadastro 5/min, sync 120/min por IP); bloqueio progressivo (5 falhas, depois 30 s dobrando até 1 h, por e-mail com hash, inclusive e-mails inexistentes); helmet; CORS desligado por padrão (`CORS_ORIGINS`); logs sem corpo, cabeçalhos, query string nem tokens; auditoria só com metadados.

## Riscos remanescentes
- Quick tunnel: URL pública e efêmera; sem SLA. Use túnel nomeado para uso real.
- Os dados ficam em JSON legível no Postgres (sem criptografia por campo); proteja o disco/volume e os backups (o dump tem tudo). Backup é manual: agende (cron/launchd) e copie para fora da máquina.
- Senha de usuário: política mínima (10+ caracteres e lista curta de óbvias), sem verificação de vazamentos nem 2FA.
- Bloqueio por e-mail permite que alguém trave a conta de outra pessoa de propósito (DoS de login) por até 1 h.
- Rate limit em memória (uma instância). Para várias réplicas, usar Redis.
- Relógios dos dispositivos decidem conflitos (limitação herdada do Core).
- `JWT_SECRET` trocado invalida todas as sessões (esperado). Registro é aberto a qualquer um que alcance a API; para uso privado, desligue o túnel ou restrinja o cadastro depois de criar as contas.
