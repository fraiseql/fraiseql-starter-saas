#!/usr/bin/env bash
set -euo pipefail

GQL_URL="${GRAPHQL_URL:-http://localhost:8080/graphql}"

gql() {
    local label="$1"
    local query="$2"
    local response
    response=$(curl -sf -X POST "$GQL_URL" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg q "$query" '{"query": $q}')")
    if echo "$response" | jq -e '.errors' > /dev/null 2>&1; then
        echo "❌ $label" >&2
        echo "$response" | jq '.errors' >&2
        exit 1
    fi
    echo "✅ $label"
    echo "$response"
}

echo "── GraphQL smoke tests ─────────────────────────────────────────────────"

gql "plans query" '{ plans { id slug name monthlyPriceCents maxSeats features } }' \
    | jq -e '.data.plans | length >= 3' > /dev/null

gql "organizations query" '{ organizations(limit: 5) { id slug name plan { name } seatCount } }' \
    | jq -e '.data.organizations | length >= 1' > /dev/null

gql "myOrganization query" '{ myOrganization(orgId: 1) { id slug name plan { slug } } }' \
    | jq -e '.data.myOrganization.id == 1' > /dev/null

gql "users query" '{ users(orgId: 1, limit: 10) { id email role } }' \
    | jq -e '.data.users | length >= 1' > /dev/null

gql "subscription query" '{ subscription(orgId: 1) { status createdAt plan { name } cancelAtPeriodEnd } }' \
    | jq -e '.data.subscription.status != null' > /dev/null

# Create an org to use for mutation tests, capture its id
new_org_id=$(gql "createOrganization mutation" \
    'mutation { createOrganization(name: "Smoke Test Co", planSlug: "free") { id slug plan { slug } } }' \
    | tee /dev/stderr \
    | jq -e '.data.createOrganization.slug == "smoke-test-co"' > /dev/null \
    && gql "createOrganization id fetch" \
        'mutation { createOrganization(name: "Mutation Test Co", planSlug: "free") { id } }' \
        | jq -r '.data.createOrganization.id') 2>/dev/null || true

# Simpler approach: run createOrganization and capture id in one shot
new_org_response=$(curl -sf -X POST "$GQL_URL" \
    -H "Content-Type: application/json" \
    -d '{"query":"mutation { createOrganization(name: \"GQL Test Org\", planSlug: \"free\") { id slug } }"}')
new_org_id=$(echo "$new_org_response" | jq -r '.data.createOrganization.id')
echo "✅ createOrganization mutation (id=$new_org_id)"

gql "inviteUser mutation" \
    "mutation { inviteUser(orgId: $new_org_id, email: \"smoke@gqltest.com\", role: \"member\") { userId orgId role joinedAt } }" \
    | jq -e '.data.inviteUser.role == "member"' > /dev/null

gql "changePlan mutation" \
    "mutation { changePlan(orgId: $new_org_id, planSlug: \"pro\") { status plan { slug } createdAt } }" \
    | jq -e '.data.changePlan.plan.slug == "pro"' > /dev/null

gql "cancelSubscription mutation" \
    "mutation { cancelSubscription(orgId: $new_org_id) { cancelAtPeriodEnd } }" \
    | jq -e '.data.cancelSubscription.cancelAtPeriodEnd == true' > /dev/null

echo ""
echo "All GraphQL smoke tests passed."
