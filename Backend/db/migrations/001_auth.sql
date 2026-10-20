-- 001: usuários, households, memberships, convites, refresh tokens, bloqueio de login.
-- gen_random_uuid() é nativo no PostgreSQL 13+.

CREATE TABLE users (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    email         text        NOT NULL,                 -- sempre minúsculo (normalizado pela API)
    name          text        NOT NULL,
    password_hash text        NOT NULL,                 -- argon2id (string PHC); nunca a senha
    disabled      boolean     NOT NULL DEFAULT false,
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT users_email_lower CHECK (email = lower(email))
);
CREATE UNIQUE INDEX users_email_uq ON users (email);

CREATE TABLE households (
    id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    name       text        NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

-- Um usuário pertence a UM household (PK em user_id). Para multi-household no futuro, troque a PK por (user_id, household_id).
CREATE TABLE memberships (
    user_id      uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    household_id uuid        NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    role         text        NOT NULL CHECK (role IN ('admin','member','dependent')),
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX memberships_household_idx ON memberships (household_id);

-- Convite: código curto, uso único, 48h. Só o hash SHA-256 do código é guardado.
CREATE TABLE invites (
    id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    household_id uuid        NOT NULL REFERENCES households(id) ON DELETE CASCADE,
    code_hash    text        NOT NULL UNIQUE,
    role         text        NOT NULL CHECK (role IN ('member','dependent')),
    created_by   uuid        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    expires_at   timestamptz NOT NULL,
    used_at      timestamptz,
    used_by      uuid        REFERENCES users(id) ON DELETE SET NULL,
    created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX invites_household_idx ON invites (household_id) WHERE used_at IS NULL;

-- Refresh tokens com rotação. Só o hash é guardado. family_id agrupa a cadeia de rotação (detecção de reuso).
CREATE TABLE refresh_tokens (
    id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     uuid        NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    family_id   uuid        NOT NULL,
    token_hash  text        NOT NULL UNIQUE,
    expires_at  timestamptz NOT NULL,
    revoked_at  timestamptz,
    created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX refresh_tokens_user_idx   ON refresh_tokens (user_id);
CREATE INDEX refresh_tokens_family_idx ON refresh_tokens (family_id);

-- Bloqueio progressivo do login. A chave é sha256(email) para valer também para e-mails inexistentes
-- (não revela quais e-mails têm conta).
CREATE TABLE login_throttle (
    key_hash     text PRIMARY KEY,
    failures     integer     NOT NULL DEFAULT 0,
    locked_until timestamptz,
    updated_at   timestamptz NOT NULL DEFAULT now()
);
