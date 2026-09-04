# SECURITY.md

## 1. Key handling

Only two values ever reach browser code: the Supabase project URL and its **publishable** key (`sb_publishable_...`), hardcoded in `assets/js/supabase-client.js`. This mirrors the existing app's Firebase client config precedent — neither value is a secret; Supabase's own docs state the publishable/anon key is designed to be shipped to clients. Real protection is Row Level Security, enforced server-side and un-bypassable by anything the client sends.

The `service_role` key and any future Razorpay signing secret are **never** referenced anywhere in `assets/` or any `.html` file — see `.env.example` for where they belong (server-side scripts / Supabase Edge Function secrets only).

## 2. Row Level Security — current status

Every table created so far has RLS enabled from the moment it was created (verified via `list_tables` after each migration, not assumed). Two real issues were found and fixed during this build, verified via Supabase's own security advisor — not left for later:

| Issue | Severity | Status |
|---|---|---|
| `main_admin_locks` created without RLS enabled | **Critical** | Fixed in migration 0002, re-verified via advisor — 0 critical/error findings remain. |
| `set_updated_at()` had a mutable search_path | Warn | Fixed in migration 0002. |
| `is_main_admin()`, `is_staff()`, `current_user_role()`, `handle_new_auth_user()`, `prevent_self_role_escalation()` are callable directly via `/rest/v1/rpc/...` by `anon`/`authenticated` | Warn | **Known, accepted for now** — see below. |

### Why the remaining 5 warnings are accepted, not silently ignored

These are `SECURITY DEFINER` helper/trigger functions meant to be called only from inside RLS policies and triggers, not directly by clients. The advisor's suggested fix — revoke `EXECUTE` from `anon`/`authenticated` — would **break every RLS policy that calls them**, because Postgres checks the querying role's `EXECUTE` privilege on a function even when that function is `SECURITY DEFINER`; revoking it blocks the policy evaluation itself, not just direct client calls.

The correct fix is to relocate these functions to a schema PostgREST doesn't expose (e.g. `private`), while keeping their Postgres-level `EXECUTE` grant intact so RLS policies keep working. That touches roughly 16 existing policy definitions and deserves its own isolated, carefully-tested migration rather than being rushed in alongside catalog/auth work. **Actual risk today is low**: each function only returns a boolean fact about the *caller's own* role (via `auth.uid()`), not another user's data — calling `/rpc/is_main_admin` directly tells you nothing you couldn't already infer by attempting an admin action and seeing if it's rejected.

`validate_coupon()` is intentionally public — that's the whole point of the function (see DATABASE.md §3) — so it is not part of this list.

**Follow-up migration required**: move `is_main_admin`, `is_staff`, `current_user_role`, `handle_new_auth_user`, `prevent_self_role_escalation` into a `private` schema and repoint every referencing policy.

## 3. Privilege-escalation protections (mirrors a bug the original app already found and fixed)

The original `index-1.html` documents a real, previously-shipped privilege-escalation bug (a client-editable `localStorage` admin-email list). Two protections were built in from day one here to avoid the Postgres equivalent:

1. **Head-Admin bootstrap is a hardcoded constant inside a `SECURITY DEFINER` trigger function**, never read from a table a client can write to.
2. **`prevent_self_role_escalation()`** blocks a signed-in user from changing their own `role`, `status`, or `parent_sub_admin_id` via a direct `profiles` update, even though the "self update" RLS policy would otherwise permit the row-level write. Row-level RLS alone can't express a column-level rule, so it's enforced in a trigger instead.

## 4. Coupons

`coupons` is **not** publicly readable — verified via RLS policy (`main_admin` read-only). The only way to check a code's validity from the client is `validate_coupon(code, amount)`, which returns a discount amount and a message but never the coupons table itself. This prevents the entire valid-code list from being scraped.

## 5. What's tested vs. what's designed-but-unverified

**Actually tested in a real browser against the live project** (see the session's verification steps): registration → trigger fires → `profiles` row created with correct `full_name`/`phone`/`role` → test account cleaned up via cascade delete; public catalog reads return real seeded data under RLS; protected pages (`my-bookings.html`, `my-reports.html`) correctly gate on session state.

**Designed but not yet exercised**: the `sub_admin`/`collection_agent` RLS paths (no staff accounts exist yet to test against), `prevent_self_role_escalation()`'s actual blocking behavior, and `validate_coupon()` (no coupons exist to validate against yet). These should be explicitly tested — not assumed correct — before this schema is relied on for bookings.

**BLOCKED**: attempted to create a second test account in-browser specifically to provoke the escalation trigger (attempt to self-promote to `main_admin` and confirm it's rejected). Supabase's default auth rate limit ("email rate limit exceeded") was hit after the first test signup earlier in this session, before this second one could run. Re-run this specific test in a follow-up session (the limit is time-windowed) rather than trusting the trigger logic unverified — deliberately not working around it with a hand-crafted `auth.users` row, since that risks a low-fidelity test that doesn't reflect a real PostgREST request context either way.
