-- 002: armazenamento documental (JSONB) das entidades do Core + auditoria.
--
-- Por que JSONB documental? O Core do app (Models.swift / Repository) já persiste cada entidade como documento
-- Codable, e a sincronização (Sync.swift) trabalha por entidade inteira: "o maior updatedAt vence" + tombstones.
-- Uma linha por entidade em `records` espelha isso 1:1: o servidor não precisa conhecer cada campo, o contrato do
-- app evolui sem migração, e o push/pull é um simples upsert/consulta por server_seq. Consultas analíticas usam as
-- views v_* (003), que projetam o JSONB em colunas tipadas.

CREATE SEQUENCE records_server_seq_seq;

CREATE TABLE records (
    household_id uuid        NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    type         text        NOT NULL CHECK (type IN (
        'Account','Category','Tag','Transaction','CreditCard','Invoice','Budget','Goal','GoalContribution',
        'Debt','Investment','NetWorthSnapshot','Household','FamilyMember','ExpenseSplit','SplitSettlement',
        'Allowance','ApprovalRequest','Tombstone')),
    id           uuid        NOT NULL,
    data         jsonb       NOT NULL CHECK (jsonb_typeof(data) = 'object'),
    updated_at   timestamptz NOT NULL,                      -- relógio do cliente: base da regra de conflito
    deleted      boolean     NOT NULL DEFAULT false,        -- tombstone: a linha fica, marcada como apagada
    owner_id     uuid        REFERENCES users(id) ON DELETE SET NULL,   -- quem gravou por último
    server_seq   bigint      NOT NULL DEFAULT nextval('records_server_seq_seq'),  -- token de sincronização
    PRIMARY KEY (household_id, type, id)
);
ALTER SEQUENCE records_server_seq_seq OWNED BY records.server_seq;
-- pull incremental: WHERE household_id = ? AND server_seq > ? ORDER BY server_seq
CREATE UNIQUE INDEX records_seq_uq        ON records (server_seq);
CREATE INDEX        records_household_seq ON records (household_id, server_seq);
-- consultas por tipo (views/agentes), ignorando apagados
CREATE INDEX        records_live_type_idx ON records (household_id, type) WHERE NOT deleted;
CREATE INDEX        records_owner_idx     ON records (owner_id);

-- Auditoria: quem gravou o quê. NÃO guarda dados financeiros (nem o conteúdo do documento), só metadados.
CREATE TABLE audit_log (
    id           bigserial   PRIMARY KEY,
    at           timestamptz NOT NULL DEFAULT now(),
    household_id uuid,
    user_id      uuid,
    action       text        NOT NULL,   -- auth.register, auth.login, auth.login_failed, record.upsert, record.delete, invite.create, household.join ...
    entity_type  text,
    entity_id    uuid,
    detail       jsonb       NOT NULL DEFAULT '{}'::jsonb,
    ip           text
);
CREATE INDEX audit_household_at_idx ON audit_log (household_id, at DESC);
CREATE INDEX audit_user_at_idx      ON audit_log (user_id, at DESC);
