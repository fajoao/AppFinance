-- 003: views de leitura para consultas/agentes. Sempre filtre por household_id (as views não aplicam isolamento).
--
-- Datas: o Core codifica Date como número (segundos desde 2001-01-01 UTC, JSONEncoder.deferredToDate).
-- Clientes web podem enviar ISO 8601 (string). app_ts() aceita os dois formatos.

CREATE FUNCTION app_ts(v jsonb) RETURNS timestamptz LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE jsonb_typeof(v)
        WHEN 'number' THEN timestamptz '2001-01-01 00:00:00+00' + ((v #>> '{}')::double precision) * interval '1 second'
        WHEN 'string' THEN (v #>> '{}')::timestamptz
    END
$$;

CREATE FUNCTION app_uuid(v jsonb) RETURNS uuid LANGUAGE sql IMMUTABLE AS $$
    SELECT CASE WHEN jsonb_typeof(v) = 'string' THEN (v #>> '{}')::uuid END
$$;

CREATE VIEW v_accounts AS
SELECT household_id, id,
       data->>'name'                              AS name,
       data->>'type'                              AS account_type,
       (data->>'initialBalance')::numeric         AS initial_balance,
       COALESCE(data->>'currency','BRL')          AS currency,
       COALESCE((data->>'isArchived')::boolean,false) AS is_archived,
       owner_id, updated_at
FROM records WHERE type = 'Account' AND NOT deleted;

CREATE VIEW v_categories AS
SELECT household_id, id,
       data->>'name'                 AS name,
       data->>'kind'                 AS kind,
       app_uuid(data->'parentId')    AS parent_id,
       owner_id, updated_at
FROM records WHERE type = 'Category' AND NOT deleted;

CREATE VIEW v_transactions AS
SELECT household_id, id,
       data->>'type'                              AS tx_type,          -- income | expense | transfer
       (data->>'amount')::numeric                 AS amount,           -- magnitude (negativo = estorno)
       app_ts(data->'date')                       AS tx_date,
       data->>'title'                             AS title,
       COALESCE(data->>'status','paid')           AS status,           -- pending | paid
       app_uuid(data->'accountId')                AS account_id,
       app_uuid(data->'destinationAccountId')     AS destination_account_id,
       app_uuid(data->'categoryId')               AS category_id,
       app_uuid(data->'creditCardId')             AS credit_card_id,
       app_uuid(data->'invoiceId')                AS invoice_id,
       app_uuid(data->'memberId')                 AS member_id,
       data->>'note'                              AS note,
       -- efeito no resultado (mesma regra de Transaction.signedAmount): receita +, despesa -, transferência 0
       CASE data->>'type'
            WHEN 'income'  THEN  (data->>'amount')::numeric
            WHEN 'expense' THEN -(data->>'amount')::numeric
            ELSE 0 END                            AS signed_amount,
       owner_id, updated_at
FROM records WHERE type = 'Transaction' AND NOT deleted;

-- Gasto/receita por mês e categoria (apenas lançamentos pagos), fuso UTC.
CREATE VIEW v_monthly_by_category AS
SELECT t.household_id,
       date_trunc('month', t.tx_date AT TIME ZONE 'UTC')::date AS month,
       t.category_id,
       c.name AS category_name,
       sum(t.signed_amount) AS total
FROM v_transactions t
LEFT JOIN v_categories c ON c.household_id = t.household_id AND c.id = t.category_id
WHERE t.status = 'paid' AND t.tx_type <> 'transfer'
GROUP BY 1, 2, 3, 4;

CREATE VIEW v_credit_cards AS
SELECT household_id, id,
       data->>'name'                          AS name,
       (data->>'limit')::numeric              AS card_limit,
       (data->>'closingDay')::int             AS closing_day,
       (data->>'dueDay')::int                 AS due_day,
       owner_id, updated_at
FROM records WHERE type = 'CreditCard' AND NOT deleted;

CREATE VIEW v_budgets AS
SELECT household_id, id,
       app_uuid(data->'categoryId')           AS category_id,
       (data #>> '{month,year}')::int         AS year,
       (data #>> '{month,month}')::int        AS month,
       (data->>'limit')::numeric              AS budget_limit,
       owner_id, updated_at
FROM records WHERE type = 'Budget' AND NOT deleted;

CREATE VIEW v_goals AS
SELECT household_id, id,
       data->>'name'                          AS name,
       (data->>'targetAmount')::numeric       AS target_amount,
       (data->>'currentAmount')::numeric      AS current_amount,
       owner_id, updated_at
FROM records WHERE type = 'Goal' AND NOT deleted;

CREATE VIEW v_debts AS
SELECT household_id, id,
       data->>'name'                          AS name,
       (data->>'balance')::numeric            AS balance,
       (data->>'monthlyInterestRate')::numeric AS monthly_interest_rate,
       (data->>'minimumPayment')::numeric     AS minimum_payment,
       owner_id, updated_at
FROM records WHERE type = 'Debt' AND NOT deleted;

CREATE VIEW v_investments AS
SELECT household_id, id,
       data->>'name'                          AS name,
       data->>'ticker'                        AS ticker,
       data->>'assetClass'                    AS asset_class,
       (data->>'quantity')::numeric           AS quantity,
       (data->>'averagePrice')::numeric       AS average_price,
       (data->>'quote')::numeric              AS quote,
       owner_id, updated_at
FROM records WHERE type = 'Investment' AND NOT deleted;

-- Auditoria legível (quem gravou o quê)
CREATE VIEW v_audit AS
SELECT a.at, a.household_id, u.email AS user_email, a.action, a.entity_type, a.entity_id, a.detail
FROM audit_log a LEFT JOIN users u ON u.id = a.user_id;
