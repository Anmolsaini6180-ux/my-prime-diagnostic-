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

### 2.2 Super Admin bootstrap + Google OAuth readiness (Phase 4, migrations 0009/0009b)

The approved Super Admin (`anmolsaini6180@gmail.com`) is enforced entirely at the database level — there is no `if (email === '...')` anywhere in frontend code, and no such check is needed there:

- `private.owner_emails()` — a `SECURITY DEFINER`, `private`-schema SQL function (never exposed via PostgREST) returning the fixed array of approved owner emails. The single source of truth; nothing else hardcodes the list.
- `private.handle_new_auth_user()` (the existing signup trigger, unchanged in purpose since Phase 1) now calls `private.owner_emails()` instead of a hardcoded array, so it works identically regardless of which auth provider created the row — Supabase Auth writes a normal `auth.users` row for a Google sign-in exactly as it does for email/password, and the trigger fires on that insert either way. Anyone whose email isn't in `owner_emails()` gets `role='patient'` by default — including every non-approved Google account.
- `private.sync_owner_admins()` — a one-off, safely re-runnable catch-up function added because inspection (per this phase's explicit instruction to check existing state before changing anything) found `anmolsaini6180@gmail.com` already had a `profiles` row with `role='patient'` from prior real usage. The signup trigger only fires on new `auth.users` inserts, so it could never retroactively promote a pre-existing account — `sync_owner_admins()` closes that gap. It was invoked once, in migration 0009, and both promoted the account and inserted its `main_admin_locks` row in the same transaction.
- **No RLS was weakened to make Google login work.** A Google-authenticated session is, from Postgres's point of view, indistinguishable from a password-authenticated one — same `auth.uid()`, same `profiles` row, same policies. Google support required zero changes to any RLS policy.
- **`main_admin_locks` continues to guarantee non-reversibility**: once a row exists for a uid, nothing in this project's code path removes it, and `prevent_self_role_escalation()` (§3) still blocks every account — including the Super Admin's own session — from changing `role` via direct client update. The *only* way `role='main_admin'` is ever granted is server-side, via the trigger or `sync_owner_admins()`, both `SECURITY DEFINER` and neither reachable from client code.

**Verified this session** (not assumed correct from the reasoning above):
- Re-ran `get_advisors` after migrations 0009/0009b — the only new finding was `owner_emails()`'s missing `search_path`, fixed immediately in 0009b; re-ran again afterward with 0 new findings.
- **Retroactive promotion (real account)**: confirmed via direct read that `anmolsaini6180@gmail.com`'s `profiles` row shows `role: main_admin` and a corresponding `main_admin_locks` row exists, timestamped from this session's migration — not fabricated, this is the actual live row.
- **Fresh-signup promotion path**: temporarily added a throwaway `metrohealthlab.in+...@gmail.com`-style test alias to `owner_emails()`, created a real pre-confirmed account for it directly in `auth.users` (so the real trigger — not a simulation — would fire), confirmed it was promoted to `main_admin` with a lock row created automatically, then removed the alias, restored the real 3-email list, and confirmed the restored list matched exactly. Test account deleted afterward.
- **Non-owner default**: the same test mechanism, with an email *not* in `owner_emails()`, confirmed `role` defaults to `patient` — this is the exact code path a real non-approved Google signup would go through, since the trigger doesn't distinguish providers.
- **Google OAuth client wiring — partially verified, explicitly not complete.** Clicking "Continue with Google" on both `pages/login.html` and `admin/login.html` correctly calls `supabase.auth.signInWithOAuth()` and navigates to Supabase's real `/auth/v1/authorize` endpoint with the correct provider and a dynamic `redirect_to` matching whatever origin the app is running on. Supabase responded with `{"error_code":"validation_failed","msg":"Unsupported provider: provider is not enabled"}` — proof the client-side code is correct and the only remaining gap is Dashboard-side configuration (enabling the provider + pasting Google Client ID/Secret + allow-listing redirect URLs), documented in [GOOGLE_OAUTH_SETUP.md](GOOGLE_OAUTH_SETUP.md). **The actual OAuth consent handshake — a real Google account completing sign-in and landing back on the app with a working session — has NOT been tested**, per this phase's explicit instruction not to declare Google login complete until that flow is actually tested. It requires the two Dashboard-only steps above, which only the project owner can perform.
- No password was created, printed, generated, or stored anywhere for `anmolsaini6180@gmail.com`, in this session or any prior one. The account's promotion relies entirely on its existing credentials (real account, real prior usage) — the bootstrap migration only ever touches `profiles`/`main_admin_locks`, never `auth.users` passwords.

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
- **Super Admin bootstrap (§2.2)**: retroactive promotion verified against the real, pre-existing `anmolsaini6180@gmail.com` account; fresh-signup promotion and non-owner-default-to-patient both verified via a real (SQL-created, pre-confirmed) throwaway test account exercising the actual trigger — not simulated.

All test accounts and test bookings were deleted after verification — the live database holds only the real catalog seed data plus the two real pre-existing profiles/bookings noted in DATABASE.md §4.

**Explicitly NOT tested — do not read anything above as claiming otherwise**: the end-to-end Google OAuth consent flow (a real Google account completing sign-in and returning to the app with a working session). Client-side wiring was verified to reach Supabase's real endpoint correctly (§2.2), but the handshake itself is blocked on two Dashboard-only configuration steps documented in [GOOGLE_OAUTH_SETUP.md](GOOGLE_OAUTH_SETUP.md) that only the project owner can perform. This is a deliberate, explicit distinction per this phase's own instruction not to declare Google login complete until actually tested.

**Designed but not yet exercised**: `validate_coupon()`'s expiry/usage-limit/min-amount branches (only the percent-discount happy path and the invalid-code path were exercised).
