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

### 2.3 CRITICAL fix: login-required booking (Phase 5, migration 0010)

Found during this phase's mandatory pre-work inspection, before any new code was written: `create_booking()` read `auth.uid()` into a variable but **never checked it was non-null**, and the function was `GRANT`ed to `anon`. A logged-out visitor could call the RPC directly — bypassing the UI entirely — and create a real booking with `user_id = NULL`. This was a live, exploitable gap, not a theoretical one.

Fixed in two layers:
1. **Runtime check**: `create_booking()` now raises `'You must be signed in to create a booking.'` immediately if `auth.uid()` is null, before touching any other logic.
2. **Grant-level**: `EXECUTE` was revoked from `anon` entirely, so an unauthenticated call never even reaches the function body.

Layer 2 took three attempts to get fully right, each caught by `get_advisors` rather than assumed correct:
- Adding a new `p_source` parameter to `create_booking()` via `CREATE OR REPLACE FUNCTION` created a second function **overload** instead of replacing it — the old 15-argument version (still `anon`-callable, still with no auth check) was still live. Fixed by dropping it outright (migration 0010b).
- `revoke execute ... from anon` isn't the only place a grant can hide: this Supabase project has `ALTER DEFAULT PRIVILEGES` configured to auto-grant `EXECUTE` to `anon`/`authenticated`/`service_role` on every *new* function — a project-level default, separate from vanilla Postgres. Three other new functions (`admin_update_booking`, `assign_collection_agent`, and the two RLS-respecting aggregate RPCs) had this exact grant despite never being explicitly given to `anon`. `revoke ... from public` (migration 0010c) does **not** remove it — the real fix is `revoke ... from anon` specifically (migration 0010d), confirmed by reading `pg_proc.proacl` directly rather than trusting `has_function_privilege` in isolation.

**Verified live, not assumed correct from the SQL:**
- A genuine, unauthenticated HTTP `POST` to `/rest/v1/rpc/create_booking` (real `curl`, the project's real anon key, no `Authorization` bearer beyond it) returned `HTTP 401` with `{"code":"42501","message":"permission denied for function create_booking"}` — rejected at the grant level, never reaching the function's own runtime check.
- A real, authenticated `patient`-role test account calling the same RPC the same way succeeded normally (`MPD-` code returned, row created with the correct `user_id`).
- Every other RPC's grant was re-verified individually with `has_function_privilege('anon', ..., 'EXECUTE')` after the fix: `create_booking`/`admin_update_booking`/`assign_collection_agent`/`admin_dashboard_stats`/`team_workload` all correctly `false` for `anon`, all correctly `true` for `authenticated`.
- The public booking wizard's entry point (`booking/patient-details.html`, the one page every "Book Now" click funnels through) now also checks for a session client-side and redirects to `/pages/login.html?redirect=...` if there isn't one — tested live: click "Book This Test" while logged out → redirected with the draft preserved in `sessionStorage` (never the URL) → log in → lands back on the same page with the draft intact → completed a real booking as that patient, verified in the database (`user_id` set, `creator_role='patient'`). This is real UX, not the actual security boundary — layer 1/2 above are what actually stop a bypass.

### 2.4 Sub Admin visibility fix + absolute Super Admin protection (Phase 5, migration 0010)

Two more gaps found during inspection:

1. **`bookings_sub_admin_select` matched 0 real rows.** The original Phase 2 policy only matched `parent_sub_admin_id = auth.uid()`, but nothing had ever set that column — verified by checking the two real live bookings before touching anything. A `sub_admin` account would have seen an empty Bookings page. Fixed by broadening the policy to also include bookings the `sub_admin` personally created and bookings assigned to collection agents on their own team (`profiles.parent_sub_admin_id`). `create_booking()` now also sets `parent_sub_admin_id` when a `sub_admin` books on a patient's behalf, so their own Admin Add Booking / WhatsApp Booking bookings are visible to them going forward.
2. **A main_admin could demote or deactivate the protected Super Admin.** `profiles_main_admin_update_all` lets any `main_admin` update any profile's `role`/`status`; the existing self-escalation trigger only restricts a user editing *their own* row. Nothing stopped a main_admin from running `update profiles set role='patient' where email='anmolsaini6180@gmail.com'`. Closed with a new, unconditional trigger: any uid present in `main_admin_locks` cannot have its `role` moved away from `main_admin` or its `status` moved away from `active`, **regardless of who's asking** — even a superuser-level direct SQL statement is blocked, since this is a trigger, not an RLS policy that only binds normal client roles. A parallel `BEFORE DELETE` trigger exists too, even though `profiles` has no delete grant to any client role today (belt-and-suspenders for if that ever changes).

**Verified live:**
- Real HTTP tests with genuine JWTs for a throwaway `sub_admin`, two throwaway `collection_agent`s (one on the sub_admin's team, one not), and a throwaway `patient`: the `sub_admin` correctly saw a booking they created via the Admin Add Booking path; assigning the on-team agent succeeded, assigning the off-team agent was rejected with `"You can only assign collection agents on your own team"`; the on-team agent could see and update the booking's stage, the off-team agent could see neither.
- The absolute-protection trigger was tested against a **disposable throwaway "main_admin"** created specifically for this test (temporarily added to `owner_emails()`, promoted and locked exactly like a real bootstrap would), never the real `anmolsaini6180@gmail.com` account. A direct SQL `UPDATE` attempting to set that throwaway account's `role='patient', status='inactive'` — run with full superuser privileges, deliberately chosen to test the strongest possible bypass attempt — was rejected with `"This account is a protected Super Admin and cannot be demoted, deactivated, or have its reporting line changed."` A follow-up read confirmed the row was completely untouched. The throwaway account (and its lock) were deleted afterward as part of normal test cleanup, never the real protected account.

### 2.5 Add Staff Edge Function (Phase 5)

`supabase/functions/admin-create-staff` is the only piece of this project that calls the Supabase Admin API. Real account creation needs the service-role key, which must never reach the browser — so this one operation runs server-side. Design:
- Verifies the caller is an **active `main_admin`**, using the caller's own JWT against a client scoped to it (never the privileged client) — a `sub_admin`/`collection_agent`/patient calling this function gets `403 Only an active Main Admin can add staff.` before any privileged code runs.
- Hard-rejects any request where `role` isn't exactly `sub_admin` or `collection_agent` — `role='main_admin'` (or anything else) is refused with `400 Role must be sub_admin or collection_agent.` Super Admin status is only ever granted by the DB-level bootstrap (§2.2), never this form, and this is enforced in code, not just by omission.
- Uses `auth.admin.inviteUserByEmail()` — creates a real `auth.users` row and sends Supabase's own invite email. The invited person sets **their own** password by following that email's link. This function never creates, generates, sees, or stores a password for anyone.
- After the signup trigger creates the default `patient`-role profile, the function promotes it to the requested role (and `parent_sub_admin_id`, for a `collection_agent`) using the service-role client — the one reviewed, audited path for this, intentionally the only code in the project that bypasses RLS on `profiles` by design.
- Logs the action to `activity_log`.

**Verified live against the deployed function (not a local simulation):**
- A real invite sent to a throwaway alias; the resulting `profiles` row confirmed with `role='sub_admin'`, `status='active'` — genuine end-to-end success.
- Calling the function with `role: 'main_admin'` was rejected with exactly the expected `400` error.
- Calling the function while authenticated as a real (throwaway) `collection_agent` account was rejected with exactly the expected `403` error.
- Test account and its invite were deleted afterward.

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
- **`sub_admin`**: rows where `parent_sub_admin_id = auth.uid()`, OR `created_by_user_id = auth.uid()` (bookings they personally created via Admin Add Booking/WhatsApp Booking), OR `assigned_collection_agent_id` is one of their own team's agents. Broadened in Phase 5 (migration 0010) — the original clause alone matched zero real bookings, see §2.4.
- **`collection_agent`**: rows where `assigned_collection_agent_id = auth.uid()` or `created_by_user_id = auth.uid()`.
- **`main_admin`**: everything.

Writes beyond stage changes go through two more Phase-5 RPCs, both `SECURITY DEFINER`, both `main_admin`/`sub_admin` only: `admin_update_booking()` (patient/collection/address/schedule/notes/status/agent — never price) and `assign_collection_agent()` (validated via `private.validate_agent_assignment()` so a `sub_admin` can only assign their own team's agents). Neither opens a new direct-write path on the tables themselves — both remain RPC-only, same as `create_booking()`/`update_booking_stage()`.

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

**Phase 5 (admin operations + booking auth) — tested live, real browser + real HTTP calls, not read back from source and assumed correct:**
- **Login-required booking (§2.3)**: a genuine unauthenticated HTTP call to `create_booking` returns 401; a real logged-out click on "Book This Test" redirects to login with the draft preserved and no sensitive data in the URL; logging in returns the visitor to the exact booking step they left, and a real booking completes successfully afterward with the correct `user_id`/`creator_role`.
- **Sub Admin visibility + team scoping (§2.4)**: a real `sub_admin` account saw a booking it created (previously would have seen nothing); assigning an agent on their own team succeeded, assigning one off their team was rejected with the exact expected error; the on-team agent could see/update the booking, the off-team agent could see neither.
- **Absolute Super Admin protection (§2.4)**: a direct superuser-level SQL update attempting to demote/deactivate a disposable *test* locked account was rejected by the new trigger; the row was confirmed unchanged afterward. The real protected account was never touched by this test.
- **Add Staff Edge Function (§2.5)**: a real invite created a real `sub_admin` account; requesting `role='main_admin'` was rejected; calling as a non-main_admin was rejected.
- **Admin booking edit + agent assignment**: `admin_update_booking()` and `assign_collection_agent()` both exercised through the real UI (`admin/bookings.html`'s detail modal) against a disposable test booking — patient name, special notes, and assigned agent all updated correctly and persisted; both actions logged to `activity_log` and `booking_status_history`.
- **Admin Add Booking**: a full booking created through `admin/add-booking.html` end-to-end, verified in the database as `creator_role='staff'`, `user_id=NULL`, `source='admin'`.
- **WhatsApp Booking parsing**: the exact "Name/Phone/Age/Gender/Test/Collection/Address/Date/Time" message format specified for this phase parsed correctly into every field (name, phone, age, gender, address, pincode); the item-matching search correctly narrowed to the right catalogue entry; the resulting booking completed successfully end-to-end.
- **WhatsApp confirmation link (customer + admin)**: generates a correct `wa.me` link with the phone normalized to `91XXXXXXXXXX` and a complete, correctly-formatted message (booking ID/patient/test/collection/date/amount/tracking link/support number) — confirmed the link is never auto-sent, only opened for the user to send themselves.
- **Price integrity across a catalog price change**: booked a test at ₹99, changed its price to ₹149 as `main_admin`, booked it again — the first booking retained ₹99, the second correctly showed ₹149. Confirms Section 27/41's requirement is real, not assumed.
- **Catalog CRUD (Tests/Packages/Coupons)**: a test add + deactivate, a coupon add + deactivate, all exercised through the real admin UI and verified in the database; every change automatically appeared in `activity_log` via the new triggers.
- **Settings → public site wiring**: changed `support_phone`'s seed value and confirmed the public homepage footer picked it up live, via a real page load (not a mock).
- **RLS-respecting dashboard aggregates**: `admin_dashboard_stats()` rendered correct, real counts (including the new Sample Collected/Processing/Unassigned/Assigned/Booking Value tiles) against the live 2-booking dataset.
- **A real bug found and fixed during this pass**: `admin/team.html` had a `ReferenceError: Cannot access 'isMainAdmin' before initialization` — a variable referenced by code that ran before its own declaration. Caught by loading the actual page in a browser and reading its console, not by re-reading the source; fixed by reordering the declaration, then re-verified the page renders and its role-gated controls work correctly.

All Phase 5 test accounts, test bookings, and test log entries were deleted after verification (including from `activity_log`, which has no automatic cascade from a deleted booking/account) — the live database holds only the real catalog seed data plus the two real pre-existing profiles/bookings noted in DATABASE.md §4, plus the 3 genuine `app_settings` seed rows.

**Designed but not yet exercised**: `validate_coupon()`'s expiry/usage-limit/min-amount branches (only the percent-discount happy path and the invalid-code path were exercised). Package/Test edit (as opposed to add/deactivate) was not separately re-tested this pass beyond code review, since it shares the exact same save handler as add.
