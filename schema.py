"""FraiseQL SaaS Starter — schema definition.

Demonstrates: multi-tenancy, auth users, subscription plans, NATS observers.

Run this to generate schema.json:
    python schema.py

Then compile and run:
    fraiseql compile
    fraiseql run
"""

import fraiseql


# ── Types ─────────────────────────────────────────────────────────────────────

@fraiseql.type
class Plan:
    """A subscription plan (free, pro, enterprise)."""

    id: int
    slug: str
    name: str
    monthly_price_cents: int
    max_seats: int | None
    features: list[str]


@fraiseql.type
class Organization:
    """A tenant organisation."""

    id: int
    slug: str
    name: str
    plan_id: int
    plan: Plan | None
    seat_count: int
    created_at: str


@fraiseql.type
class OrgMember:
    """A user's membership in an organisation."""

    user_id: int
    org_id: int
    role: str           # "owner" | "admin" | "member"
    joined_at: str


@fraiseql.type
class User:
    """An authenticated user."""

    id: int
    email: str
    display_name: str | None
    org_id: int
    org: Organization | None
    role: str
    created_at: str
    last_seen_at: str | None


@fraiseql.type
class Subscription:
    """An organisation's active billing subscription."""

    id: int
    org_id: int
    plan_id: int
    plan: Plan | None
    status: str         # "active" | "trialing" | "past_due" | "canceled"
    current_period_end: str
    cancel_at_period_end: bool
    created_at: str


# ── Queries ───────────────────────────────────────────────────────────────────

@fraiseql.query(sql_source="v_plan")
def plans() -> list[Plan]:
    """List all available plans."""
    pass


@fraiseql.query(sql_source="v_plan")
def plan(id: int) -> Plan | None:
    """Get a plan by ID."""
    pass


@fraiseql.query(sql_source="v_organization")
def organizations(limit: int = 20, offset: int = 0) -> list[Organization]:
    """List organisations (admin only)."""
    pass


@fraiseql.query(sql_source="v_organization")
def organization(id: int) -> Organization | None:
    """Get an organisation by ID."""
    pass


@fraiseql.query(sql_source="v_organization")
def my_organization(org_id: int) -> Organization | None:
    """Get the calling user's organisation (pass org_id from JWT claims)."""
    pass


@fraiseql.query(sql_source="v_user")
def users(org_id: int, limit: int = 20, offset: int = 0) -> list[User]:
    """List users within an organisation."""
    pass


@fraiseql.query(sql_source="v_user")
def user(id: int) -> User | None:
    """Get a user by ID."""
    pass


@fraiseql.query(sql_source="v_subscription")
def subscription(org_id: int) -> Subscription | None:
    """Get the active subscription for an organisation."""
    pass


# ── Mutations ─────────────────────────────────────────────────────────────────

@fraiseql.mutation(sql_source="fn_create_organization", operation="CREATE")
def create_organization(name: str, plan_slug: str = "free") -> Organization:
    """Create a new organisation on a given plan."""
    pass


@fraiseql.mutation(sql_source="fn_invite_user", operation="CREATE")
def invite_user(org_id: int, email: str, role: str = "member") -> OrgMember:
    """Invite a user to an organisation (backed by v_org_member)."""
    pass


@fraiseql.mutation(sql_source="fn_change_plan", operation="UPDATE")
def change_plan(org_id: int, plan_slug: str) -> Subscription:
    """Upgrade or downgrade an organisation's plan."""
    pass


@fraiseql.mutation(sql_source="fn_cancel_subscription", operation="UPDATE")
def cancel_subscription(org_id: int) -> Subscription:
    """Cancel the subscription at period end."""
    pass


if __name__ == "__main__":
    fraiseql.export_schema("schema.json")
    print("schema.json generated — run: fraiseql compile && fraiseql run")
