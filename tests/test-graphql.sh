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

gql "subscription query" '{ subscription(orgId: 1) { status plan { name } cancelAtPeriodEnd } }' \
    | jq -e '.data.subscription.status != null' > /dev/null

gql "createOrganization mutation" \
    'mutation { createOrganization(name: "Smoke Test Co", planSlug: "free") { id slug plan { slug } } }' \
    | jq -e '.data.createOrganization.slug == "smoke-test-co"' > /dev/null

echo ""
echo "All GraphQL smoke tests passed."
