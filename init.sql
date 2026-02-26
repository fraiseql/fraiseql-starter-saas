-- SaaS starter schema
-- Multi-tenant: organisations, users, plans, subscriptions
-- FraiseQL reads from views (v_*) and calls functions (fn_*)

-- ── Tables ────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS plans (
    id                   SERIAL PRIMARY KEY,
    slug                 TEXT    NOT NULL UNIQUE,
    name                 TEXT    NOT NULL,
    monthly_price_cents  INTEGER NOT NULL DEFAULT 0,
    max_seats            INTEGER,        -- NULL = unlimited
    features             TEXT[]  NOT NULL DEFAULT '{}'
);

CREATE TABLE IF NOT EXISTS organizations (
    id         SERIAL PRIMARY KEY,
    slug       TEXT        NOT NULL UNIQUE,
    name       TEXT        NOT NULL,
    plan_id    INTEGER     NOT NULL REFERENCES plans(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS users (
    id           SERIAL PRIMARY KEY,
    email        TEXT        NOT NULL UNIQUE,
    display_name TEXT,
    org_id       INTEGER     NOT NULL REFERENCES organizations(id),
    role         TEXT        NOT NULL DEFAULT 'member'
                             CHECK (role IN ('owner', 'admin', 'member')),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS subscriptions (
    id                   SERIAL PRIMARY KEY,
    org_id               INTEGER     NOT NULL UNIQUE REFERENCES organizations(id),
    plan_id              INTEGER     NOT NULL REFERENCES plans(id),
    status               TEXT        NOT NULL DEFAULT 'active'
                         CHECK (status IN ('active', 'trialing', 'past_due', 'canceled')),
    current_period_end   TIMESTAMPTZ NOT NULL DEFAULT now() + interval '30 days',
    cancel_at_period_end BOOLEAN     NOT NULL DEFAULT false,
    created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── Views ─────────────────────────────────────────────────────────────────────

CREATE OR REPLACE VIEW v_plan AS
SELECT id, slug, name, monthly_price_cents, max_seats, features
FROM plans;

CREATE OR REPLACE VIEW v_organization AS
SELECT
    o.id,
    o.slug,
    o.name,
    o.plan_id,
    row_to_json(p)::jsonb           AS plan,
    (SELECT count(*) FROM users u WHERE u.org_id = o.id)::INTEGER AS seat_count,
    o.created_at::TEXT              AS created_at
FROM organizations o
JOIN plans p ON p.id = o.plan_id;

CREATE OR REPLACE VIEW v_user AS
SELECT
    u.id,
    u.email,
    u.display_name,
    u.org_id,
    row_to_json(o)::jsonb   AS org,
    u.role,
    u.created_at::TEXT      AS created_at,
    u.last_seen_at::TEXT    AS last_seen_at
FROM users u
JOIN organizations o ON o.id = u.org_id;

CREATE OR REPLACE VIEW v_subscription AS
SELECT
    s.id,
    s.org_id,
    s.plan_id,
    row_to_json(p)::jsonb               AS plan,
    s.status,
    s.current_period_end::TEXT          AS current_period_end,
    s.cancel_at_period_end
FROM subscriptions s
JOIN plans p ON p.id = s.plan_id;

-- ── Functions ─────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_create_organization(
    p_name      TEXT,
    p_plan_slug TEXT DEFAULT 'free'
) RETURNS SETOF v_organization AS $$
DECLARE
    v_plan_id INTEGER;
    v_org_id  INTEGER;
    v_slug    TEXT;
BEGIN
    SELECT id INTO v_plan_id FROM plans WHERE slug = p_plan_slug;
    IF v_plan_id IS NULL THEN
        RAISE EXCEPTION 'Unknown plan: %', p_plan_slug;
    END IF;

    v_slug := lower(regexp_replace(p_name, '[^a-zA-Z0-9]+', '-', 'g'));

    INSERT INTO organizations (slug, name, plan_id)
    VALUES (v_slug, p_name, v_plan_id)
    RETURNING id INTO v_org_id;

    INSERT INTO subscriptions (org_id, plan_id)
    VALUES (v_org_id, v_plan_id);

    RETURN QUERY SELECT * FROM v_organization WHERE id = v_org_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_invite_user(
    p_org_id INTEGER,
    p_email  TEXT,
    p_role   TEXT DEFAULT 'member'
) RETURNS TABLE(user_id INTEGER, org_id INTEGER, role TEXT, joined_at TEXT) AS $$
DECLARE
    v_user_id INTEGER;
BEGIN
    INSERT INTO users (email, org_id, role)
    VALUES (p_email, p_org_id, p_role)
    ON CONFLICT (email) DO UPDATE SET org_id = p_org_id, role = p_role
    RETURNING id INTO v_user_id;

    RETURN QUERY
    SELECT u.id, u.org_id, u.role, u.created_at::TEXT
    FROM users u WHERE u.id = v_user_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_change_plan(
    p_org_id    INTEGER,
    p_plan_slug TEXT
) RETURNS SETOF v_subscription AS $$
DECLARE
    v_plan_id INTEGER;
BEGIN
    SELECT id INTO v_plan_id FROM plans WHERE slug = p_plan_slug;
    IF v_plan_id IS NULL THEN
        RAISE EXCEPTION 'Unknown plan: %', p_plan_slug;
    END IF;

    UPDATE organizations SET plan_id = v_plan_id WHERE id = p_org_id;
    UPDATE subscriptions   SET plan_id = v_plan_id, status = 'active',
                               cancel_at_period_end = false
    WHERE org_id = p_org_id;

    RETURN QUERY SELECT * FROM v_subscription WHERE org_id = p_org_id;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION fn_cancel_subscription(
    p_org_id INTEGER
) RETURNS SETOF v_subscription AS $$
BEGIN
    UPDATE subscriptions SET cancel_at_period_end = true WHERE org_id = p_org_id;
    RETURN QUERY SELECT * FROM v_subscription WHERE org_id = p_org_id;
END;
$$ LANGUAGE plpgsql;

-- ── Seed data ─────────────────────────────────────────────────────────────────

INSERT INTO plans (slug, name, monthly_price_cents, max_seats, features) VALUES
    ('free',       'Free',       0,      5,    ARRAY['graphql_api', 'community_support']),
    ('pro',        'Pro',        2900,   25,   ARRAY['graphql_api', 'email_support', 'analytics']),
    ('enterprise', 'Enterprise', 19900,  NULL, ARRAY['graphql_api', 'sla_support', 'analytics', 'sso', 'audit_logs'])
ON CONFLICT DO NOTHING;

SELECT fn_create_organization('Acme Corp', 'pro');

INSERT INTO users (email, display_name, org_id, role)
SELECT 'alice@acme.com', 'Alice', id, 'owner'
FROM organizations WHERE slug = 'acme-corp'
ON CONFLICT DO NOTHING;
