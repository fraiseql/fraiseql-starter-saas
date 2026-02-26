#!/usr/bin/env bash
set -euo pipefail

PSQL="psql -h localhost -U postgres -d saas --no-psqlrc -v ON_ERROR_STOP=1"

pass() { echo "✅ $1"; }
fail() { echo "❌ $1" >&2; exit 1; }

check_count() {
    local label="$1"
    local query="$2"
    local min="$3"
    local count
    count=$($PSQL -tAc "$query")
    if [ "$count" -ge "$min" ]; then
        pass "$label (count=$count)"
    else
        fail "$label: expected >= $min, got $count"
    fi
}

check_exists() {
    local label="$1"
    local query="$2"
    local count
    count=$($PSQL -tAc "$query")
    if [ "$count" -eq 1 ]; then
        pass "$label"
    else
        fail "$label: not found"
    fi
}

echo "── Tables ──────────────────────────────────────────────────────────────"
for tbl in tb_plan tb_organization tb_user tb_subscription; do
    check_exists "table $tbl" \
        "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_name='$tbl'"
done

echo "── Views ───────────────────────────────────────────────────────────────"
for view in v_plan v_organization v_org_member v_user v_subscription; do
    check_exists "view $view" \
        "SELECT COUNT(*) FROM information_schema.views WHERE table_schema='public' AND table_name='$view'"
done

echo "── Functions ───────────────────────────────────────────────────────────"
for fn in fn_create_organization fn_invite_user fn_change_plan fn_cancel_subscription; do
    check_exists "function $fn" \
        "SELECT COUNT(*) FROM information_schema.routines WHERE routine_schema='public' AND routine_name='$fn'"
done

echo "── Seed counts ─────────────────────────────────────────────────────────"
check_count "tb_plan seed"         "SELECT COUNT(*) FROM tb_plan"         3
check_count "tb_organization seed" "SELECT COUNT(*) FROM tb_organization" 1
check_count "tb_subscription seed" "SELECT COUNT(*) FROM tb_subscription" 1
check_count "tb_user seed"         "SELECT COUNT(*) FROM tb_user"         1

echo "── v_organization columns ──────────────────────────────────────────────"
expected_cols="id slug name plan_id plan seat_count created_at"
actual_cols=$($PSQL -tAc \
    "SELECT string_agg(column_name, ' ' ORDER BY ordinal_position)
     FROM information_schema.columns
     WHERE table_schema='public' AND table_name='v_organization'")
for col in $expected_cols; do
    if echo "$actual_cols" | grep -qw "$col"; then
        pass "v_organization column: $col"
    else
        fail "v_organization missing column: $col"
    fi
done

echo "── v_subscription columns ──────────────────────────────────────────────"
expected_cols="id org_id plan_id plan status current_period_end cancel_at_period_end created_at"
actual_cols=$($PSQL -tAc \
    "SELECT string_agg(column_name, ' ' ORDER BY ordinal_position)
     FROM information_schema.columns
     WHERE table_schema='public' AND table_name='v_subscription'")
for col in $expected_cols; do
    if echo "$actual_cols" | grep -qw "$col"; then
        pass "v_subscription column: $col"
    else
        fail "v_subscription missing column: $col"
    fi
done

echo "── fn_create_organization ──────────────────────────────────────────────"
new_org_id=$($PSQL -tAc \
    "SELECT id FROM fn_create_organization('CI Test Org', 'free') LIMIT 1")
new_org_id=$(echo "$new_org_id" | tr -d '[:space:]')
if [ -z "$new_org_id" ]; then
    fail "fn_create_organization returned no row"
fi
check_exists "fn_create_organization result in v_organization" \
    "SELECT COUNT(*) FROM v_organization WHERE id = $new_org_id"
check_exists "fn_create_organization subscription created" \
    "SELECT COUNT(*) FROM tb_subscription WHERE org_id = $new_org_id"
check_exists "fn_create_organization slug generated" \
    "SELECT COUNT(*) FROM tb_organization WHERE id = $new_org_id AND slug = 'ci-test-org'"

echo "── fn_invite_user ──────────────────────────────────────────────────────"
new_user_id=$($PSQL -tAc \
    "SELECT user_id FROM fn_invite_user($new_org_id, 'ci-user@example.com', 'member') LIMIT 1")
new_user_id=$(echo "$new_user_id" | tr -d '[:space:]')
if [ -z "$new_user_id" ]; then
    fail "fn_invite_user returned no row"
fi
check_exists "fn_invite_user user created in tb_user" \
    "SELECT COUNT(*) FROM tb_user WHERE email = 'ci-user@example.com'"
check_exists "fn_invite_user result in v_org_member" \
    "SELECT COUNT(*) FROM v_org_member WHERE user_id = $new_user_id"

echo "── fn_change_plan ──────────────────────────────────────────────────────"
new_status=$($PSQL -tAc \
    "SELECT status FROM fn_change_plan($new_org_id, 'pro') LIMIT 1")
new_status=$(echo "$new_status" | tr -d '[:space:]')
if [ "$new_status" = "active" ]; then
    pass "fn_change_plan status=active"
else
    fail "fn_change_plan: expected active, got: $new_status"
fi

echo "── fn_cancel_subscription ──────────────────────────────────────────────"
canceled=$($PSQL -tAc \
    "SELECT cancel_at_period_end FROM fn_cancel_subscription($new_org_id) LIMIT 1")
canceled=$(echo "$canceled" | tr -d '[:space:]')
if [ "$canceled" = "t" ]; then
    pass "fn_cancel_subscription cancel_at_period_end=true"
else
    fail "fn_cancel_subscription: expected t, got: $canceled"
fi

echo "── Cleanup ─────────────────────────────────────────────────────────────"
$PSQL -c "DELETE FROM tb_user         WHERE email = 'ci-user@example.com'"
$PSQL -c "DELETE FROM tb_subscription WHERE org_id = $new_org_id"
$PSQL -c "DELETE FROM tb_organization WHERE id = $new_org_id"
pass "cleanup done"

echo ""
echo "All PostgreSQL integration tests passed."
