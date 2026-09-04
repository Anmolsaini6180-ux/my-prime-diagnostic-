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
| `is_main_admin()`, `is_staff()`, `current_user_role()`, `handle_new_auth_user()`, `prevent_self_role_escalation()`, `can_view_booking()` were callable directly via `/rest/v1/rpc/...` by `anon`/`authenticated` | Warn | **Fixed in migration 0008** — see §2.1. |

### Two different reasons a function shows up in the advisor's WARN list

Not every `SECURITY DEFINER`-callable-by-anon warning means the same thing. This project has two distinct categories:

1. **Intentionally public RPCs** — `validate_coupon`, `create_booking`, `get_slot_availability`, `track_booking`, `track_booking_timeline`, `update_booking_stage`. These are *meant* to be callable by anyone; the advisor can't tell that from a blanket heuristic. Each one does its own real authorization/validation internally (see BOOKING_IMPLEMENTATION.md §4/§6) — the WARN is a false positive against intent, not a gap.
2. **Internal helpers, genuinely over-exposed** — `is_main_admin`, `is_staff`, `current_user_role`, `handle_new_auth_user`, `prevent_self_role_escalation`, `can_view_booking`. These exist only to be called from inside RLS policies/triggers. See below for why they're still accepted for now rather than fixed immediately.

### 2.1 Fixed: internal helpers relocated to a `private` schema (migration 0008)

The advisor's suggested fix — revoke `EXECUTE` from `anon`/`authenticated` — would have **broken every RLS policy that calls them**, since Postgres checks the querying role's `EXECUTE` privilege on a function even when that function is `SECURITY DEFINER`. The actual fix applied: moved all 6 functions into a new `private` schema, which PostgREST never exposes as REST routes, while their Postgres-level `EXECUTE` grants (needed for RLS policies) stayed untouched.

This was safe to do without touching any of the ~27 existing RLS policies that reference these functions, because a policy's `USING`/`WITH CHECK` expression stores a reference to the function **by OID** (like a view or check constraint does), not by re-parsed name text — `ALTER FUNCTION ... SET SCHEMA` preserves the OID. Three functions whose own *body text* called these helpers by qualified name (`can_view_booking`, `prevent_self_role_escalation`, `update_booking_stage`) were recreated with `private.`-prefixed calls; everything else needed zero changes.

**Verified after applying** — not assumed correct from the reasoning above:
- `get_advisors` re-run: all 6 no longer appear in the WARN list at all.
- Fresh signup still creates a `profiles` row correctly (`handle_new_auth_user`, now in `private`, still fires as a trigger).
- Self-role-escalation attempt (`role` and implicitly `status`) still rejected (`prevent_self_role_escalation`).
- A patient account's attempt to write to `packages` still silently affects 0 rows (`is_main_admin`-gated policy), confirmed by re-reading the row unchanged.
- `can_view_booking`-gated visibility re-tested with a real `collection_agent` account across three states: booking they created (visible), unrelated booking (invisible), booking after being assigned (visible) — all correct.
- `update_booking_stage` re-tested: rejected before assignment, succeeded after — confirming its internal `current_user_role()` call still resolves correctly from the new location.

All test accounts/bookings used for this verification were deleted afterward.

## 3. Privilege-escalation protections (mirrors a bug the original app already found and fixed)

The original `index-1.html` documents a real, previously-shipped privilege-escalation bug (a client-editable `localStorage` admin-email list). Two protections were built in from day one here to avoid the Postgres equivalent:

1. **Head-Admin bootstrap is a hardcoded constant inside a `SECURITY DEFINER` trigger function**, never read from a table a client can write to.
2. **`prevent_self_role_escalation()`** blocks a signed-in user from changing their own `role`, `status`, or `parent_sub_admin_id` via a direct `profiles` update, even though the "self update" RLS policy would otherwise permit the row-level write. Row-level RLS alone can't express a column-level rule, so it's enforced in a trigger instead.

**Verified live** (Phase 2, closing out a Phase-1 BLOCKED item — the first attempt hit Supabase's auth rate limit before it could run): signed in as a real, freshly-created `patient`-role test account and attempted `supabase.from('profiles').update({ role: 'main_admin' })` and `.update({ status: 'inactive' })` against their own row via the real client SDK. Both were rejected with the trigger's exact error message, and a follow-up read confirmed the row was untouched (`role` still `patient`, `status` still `active`). Test account deleted afterward.

## 4. Coupons

`coupons` is **not** publicly readable — verified via RLS policy (`main_admin` read-only). The only way to check a code's validity from the client is `validate_coupon(code, amount)`, which returns a discount amount and a message but never the coupons table itself. This prevents the entire valid-code list from being scraped.

## 5. Booking RLS and RPC authorization (Phase 2)

`bookings`, `booking_items`, `collection_addresses`, and `booking_status_history` have **no INSERT/UPDATE/DELETE grant for any client role at all** — every write goes through `create_booking()` or `update_booking_stage()`, both `SECURITY DEFINER`. This means "a customer can't modify price/status/ownership" isn't a policy that could theoretically have a gap — there is no direct write path to have a gap in.

Read access:
- **Patient**: only rows where `bookings.user_id = auth.uid()`. A guest (no session) has no table-level `anon` grant on `bookings` at all — their only path is `track_booking()`, which requires the exact phone number too.
- **`sub_admin`**: rows where `parent_sub_admin_id = auth.uid()`.
- **`collection_agent`**: rows where `assigned_collection_agent_id = auth.uid()` or `created_by_user_id = auth.uid()`.
- **`main_admin`**: everything.

`update_booking_stage()` additionally restricts `collection_agent` to the stages `dispatched`/`collected`/`cancelled`/`no_show` (the ones an actual field agent's job covers) and only on bookings assigned to or created by them — `main_admin`/`sub_admin` keep the original app's full flexibility to set any stage.

## 6. What's tested vs. what's designed-but-unverified

**Actually tested end-to-end, in a real browser, against the live project — not read back from the source and assumed correct:**
- Registration → trigger fires → `profiles` row created with correct `full_name`/`phone`/`role`.
- **Self-role-escalation attempt, both `role` and `status`** — rejected by `prevent_self_role_escalation()`, confirmed via a real update attempt through the client SDK and a follow-up read (§3).
- Full booking wizard, both **Home Collection** and **Walk-in at Lab**, database records verified field-by-field afterward (`bookings`, `booking_items`, `collection_addresses` present/absent correctly, `booking_status_history`).
- **Coupon discount** applied correctly (10% off, `used_count` incremented) — and a real bug in how the review page carried the applied coupon through to submission was caught and fixed in the process (BOOKING_IMPLEMENTATION.md §2).
- **Duplicate-submission protection**: two `create_booking()` calls with the same idempotency key produced exactly one database row.
- **Real slot-capacity enforcement**: temporarily set a slot's capacity to 1, confirmed a second booking for that date+slot was rejected, confirmed the Schedule page's own availability query reflected `is_available: false`.
- **Public tracker security**: a real booking code with the *wrong* phone number returns "not found"; the correct phone returns the real timeline with customer-facing labels and no internal notes or staff names.
- **`update_booking_stage()` authorization**: a `collection_agent` not assigned to a booking is rejected; the same agent, once assigned, can move it through `dispatched`→`collected`; a disallowed stage (`report_ready`) is rejected even hypothetically; a `patient`-role account is rejected outright.
- **Cross-user isolation (2 real accounts, "User A / User B")**: User B's session — via `select('*')`, a targeted `eq('booking_code', ...)` lookup, and direct reads of `booking_items`/`booking_status_history` — returned empty for every one of User A's rows; the My Bookings page correctly showed an honest "No bookings yet" rather than an error or someone else's data.
- **Realtime**: a database-side stage update appeared in a logged-in user's My Bookings page with zero manual refresh.
- Public catalog reads return real seeded data under RLS; protected pages (`my-bookings.html`, `my-reports.html`) correctly gate on session state.

All test accounts and test bookings were deleted after verification — the live database holds only the real catalog seed data.

- **Internal-helper relocation (§2.1)**: moved to `private` schema, `get_advisors` re-verified clean, and every dependent code path (signup trigger, self-escalation guard, catalog write-gating, booking visibility, stage-update authorization) re-tested with real accounts afterward.

**Designed but not yet exercised**: `validate_coupon()`'s expiry/usage-limit/min-amount branches (only the percent-discount happy path and the invalid-code path were exercised).
