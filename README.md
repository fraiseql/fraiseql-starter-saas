# fraiseql/starter-saas

A multi-tenant SaaS API built with FraiseQL: **organisations, users, subscription plans, NATS observers**.

## What's inside

| File | Purpose |
|------|---------|
| `schema.py` | Type and query definitions (authoring layer) |
| `fraiseql.toml` | Project, runtime, observer, and security configuration |
| `init.sql` | PostgreSQL tables, views, functions, and seed data |
| `docker-compose.yml` | PostgreSQL + NATS + fraiseql in one command |
| `.env.example` | Environment variable template |

## GraphQL API surface

```graphql
type Plan         { id, slug, name, monthlyPriceCents, maxSeats, features }
type Organization { id, slug, name, planId, plan, seatCount, createdAt }
type User         { id, email, displayName, orgId, org, role, createdAt, lastSeenAt }
type Subscription { id, orgId, planId, plan, status, currentPeriodEnd, cancelAtPeriodEnd }

type Query {
  plans: [Plan!]!
  plan(id): Plan
  organizations(limit, offset): [Organization!]!
  organization(id): Organization
  myOrganization(orgId): Organization
  users(orgId, limit, offset): [User!]!
  user(id): User
  subscription(orgId): Subscription
}

type Mutation {
  createOrganization(name, planSlug): Organization!
  inviteUser(orgId, email, role): OrgMember!
  changePlan(orgId, planSlug): Subscription!
  cancelSubscription(orgId): Subscription!
}
```

## Quickstart (Docker — includes NATS)

```bash
cp .env.example .env

pip install fraiseql
python schema.py
fraiseql compile

docker compose up
```

API at **http://localhost:8080/graphql**.
NATS monitoring at **http://localhost:8222**.

## Quickstart (local binary — no NATS)

Remove the `[fraiseql.observers]` section from `fraiseql.toml`, then:

```bash
cp .env.example .env && source .env
pip install fraiseql
python schema.py && fraiseql compile && fraiseql run
```

## Multi-tenancy pattern

Every query that returns tenant-scoped data accepts an `orgId` argument. In production, pass this from JWT claims via your API gateway — never trust the client to supply it directly.

```graphql
# Always scope queries to the authenticated org
query {
  users(orgId: 42, limit: 10) {
    email role
  }
}
```

## Plans and subscriptions

The seed data includes three plans. Upgrade/downgrade is a single mutation:

```graphql
mutation {
  changePlan(orgId: 1, planSlug: "enterprise") {
    status
    plan { name monthlyPriceCents }
  }
}
```

## NATS observers

When `NATS_URL` is set and `[fraiseql.observers]` is configured, FraiseQL publishes mutation events to NATS subjects (e.g. `fraiseql.mutation.createOrganization`). Subscribe downstream for billing webhooks, audit logging, etc.

## Rate limiting

The `fraiseql.toml` ships with rate limiting enabled on auth endpoints (20 req/60 s). Adjust thresholds under `[fraiseql.security.rate_limiting]`.

## Next steps

- Add JWT validation middleware in front of fraiseql
- Wire NATS events to your billing provider (Stripe, etc.)
- Enable audit logging: `[fraiseql.security.audit_logging] enabled = true`
