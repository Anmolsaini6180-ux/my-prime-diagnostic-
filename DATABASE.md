# DATABASE.md — Supabase Schema Reference

Live project: **my prime diagnoatics lab** (`woedykgrzczgogtymfxg`, `ap-south-1`). This document reflects what is actually deployed, verified via `list_tables`/`execute_sql`, not just what was intended.

---

## 1. Migrations applied so far

| # | File | Purpose |
|---|---|---|
| 0001 | `supabase/migrations/0001_foundation_and_catalog.sql` | `profiles`, Head-Admin bootstrap, `tests`, `packages`, `package_tests`, `package_features`, `coupons` + `validate_coupon()` RPC. RLS enabled on every table. |
| 0002 | `supabase/migrations/0002_security_hardening_fixes.sql` | Fixed a critical gap introduced in 0001 (`main_admin_locks` had RLS disabled) and a function search-path warning. See SECURITY.md §2. |
| 0003 | `supabase/migrations/0003_capture_phone_on_signup.sql` | Fixed the signup trigger to actually store the phone number collected at registration (was silently dropped). |
| 0004 | `supabase/migrations/0004_bookings_schema.sql` | `appointment_slots`, `bookings`, `booking_items`, `collection_addresses`, `booking_status_history`, `generate_booking_code()`, `can_view_booking()`. RLS enabled on every table; no direct insert/update/delete grant to any client role — all writes go through the RPCs in 0005/0007. |
| 0005 | `supabase/migrations/0005_booking_rpcs.sql` | `get_slot_availability()`, `create_booking()`, `update_booking_stage()`, `track_booking()`, `track_booking_timeline()`. Enabled Realtime on `bookings` and `booking_status_history`. |
| 0006 | `supabase/migrations/0006_appointment_slots_unique_label.sql` | Added a unique constraint on `appointment_slots.label`, caught while writing the seed file (see BOOKING_IMPLEMENTATION.md §2). |
| 0007 | `supabase/migrations/0007_fix_ambiguous_status_column.sql` | Fixed a real bug found by running the flow in-browser: `create_booking()`'s ambiguous `status` reference (see BOOKING_IMPLEMENTATION.md §2). |
| 0008 | `supabase/migrations/0008_relocate_internal_helpers_to_private_schema.sql` | Moved `is_main_admin`, `is_staff`, `current_user_role`, `handle_new_auth_user`, `prevent_self_role_escalation`, `can_view_booking` into a new `private` schema (never exposed to PostgREST) — closes the known advisor WARN from Phase 2. See SECURITY.md §2.1 for why this was safe and how it was re-verified. |
| 0009 | `supabase/migrations/0009_super_admin_bootstrap.sql` | Added `anmolsaini6180@gmail.com` as an approved owner email (`private.owner_emails()`, single source of truth for both the signup trigger and the new catch-up function below). Added `private.sync_owner_admins()` — idempotent, promotes any *existing* profile matching an owner email to `main_admin` and creates its lock row; called once in this migration since that email already had a `patient`-role profile from before this request (the signup trigger only fires on brand-new signups, so it alone could not have retroactively promoted it). |
| 0009b | `supabase/migrations/0009b_fix_owner_emails_search_path.sql` | Fixed a `search_path` warning on `owner_emails()` caught immediately via `get_advisors` after 0009. |
| — | `supabase/seed/001_catalog_seed.sql` | Real catalog data ported from `index-1.html` (5 packages, 31 features, 15 tests) — not synthetic. |
| — | `supabase/seed/002_appointment_slots_seed.sql` | The exact 8 time windows from `index-1.html`'s booking form. |

Staff CRUD, reports, and cashflow tables are **not yet created** — that's the admin migration phase, scoped deliberately separately (see ARCHITECTURE_PLAN.md and BOOKING_IMPLEMENTATION.md).

## 2. Tables

| Table | Rows (live) | RLS | Purpose |
|---|---|---|---|
| `profiles` | 0 | ✅ | One row per `auth.users` id. `role` defaults to `patient`; staff roles (`main_admin`/`sub_admin`/`collection_agent`) mirror the original Firebase model. |
| `main_admin_locks` | 0 | ✅ | Permanent record of who has ever been granted `main_admin`. Never written by client code — only by the signup trigger. |
| `tests` | 15 | ✅ | Individual lab tests. Public read (active only); writes are `main_admin` only. |
| `packages` | 5 | ✅ | Health checkup packages. Same read/write split as `tests`. |
| `package_tests` | 0 (this catalog uses `package_features` — see below) | ✅ | Structured tests-included list for a package, when a package uses the newer per-test schema. |
| `package_features` | 31 | ✅ | Plain-string feature list for a package (the schema all 5 seeded packages actually use, matching the source app). |
| `coupons` | 0 | ✅ | Not publicly readable — see SECURITY.md §3. Empty because the source app has no default coupons (admin-created only). |
| `appointment_slots` | 8 | ✅ | The 8 real time windows from the source app's booking form. Public read (active only); `main_admin` writes. `default_capacity` (12) is a placeholder pending the business's real per-slot numbers. |
| `bookings` | 0 (test data cleaned up after verification) | ✅ | The core booking record — patient snapshot, collection details, pricing (always server-computed), payment, `status` (coarse lifecycle) + `stage` (fine-grained pipeline, the original app's exact TRACKER_FLOW vocabulary), RBAC ownership fields. No insert/update/delete grant to any client role — every write goes through `create_booking()`/`update_booking_stage()`. |
| `booking_items` | 0 | ✅ | One row per item in a booking (package or test), snapshotting name+price. Schema supports multiple items per booking; the wizard built so far always inserts exactly one. |
| `collection_addresses` | 0 | ✅ | One-way FK to `bookings` (not circular), created only when `collection_type='home'`. |
| `booking_status_history` | 0 | ✅ | Full audit trail of every stage/status change. Customer-facing RPCs only ever select `new_status`+`created_at` from this table — `note`/`changed_by`/`changed_by_name` are never part of a customer-facing return shape. |

## 3. Functions

| Function | Type | Purpose |
|---|---|---|
| `handle_new_auth_user()` | Trigger (`auth.users` → `AFTER INSERT`) | Creates the `profiles` row for every new signup (any provider — email/password or Google, the trigger fires on the `auth.users` row regardless of how it was created); grants `main_admin` only to the emails in `owner_emails()`, only once. |
| `owner_emails()` | SQL, `private` schema | Single source of truth for the 3 approved Head Admin emails — both `handle_new_auth_user()` and `sync_owner_admins()` read from this instead of each keeping their own copy. |
| `sync_owner_admins()` | PL/pgSQL, `private` schema | Idempotent catch-up: promotes any *existing* profile matching an owner email that isn't already `main_admin`, and ensures its lock row exists. Safe to re-run any time (e.g., after adding a future owner email) — a no-op for anyone already promoted, never touches a non-owner email. |
| `prevent_self_role_escalation()` | Trigger (`profiles` → `BEFORE UPDATE`) | Blocks a non-`main_admin` from changing their own `role`/`status`/`parent_sub_admin_id`, even though the RLS policy otherwise allows self-updates. |
| `is_main_admin()`, `is_staff()`, `current_user_role()` | SQL, `SECURITY DEFINER` | RLS policy helpers — avoid recursive policy evaluation. Relocated to the `private` schema in migration 0008 — see SECURITY.md §2.1. |
| `set_updated_at()` | Trigger helper | Keeps `updated_at` current on `profiles`/`tests`/`packages`/`coupons`. |
| `validate_coupon(code, amount)` | RPC, `SECURITY DEFINER` | The **only** public surface for coupon checks — returns validity + discount, never the coupons table itself. |
| `can_view_booking(booking_id)` | SQL, `SECURITY DEFINER` | Shared RLS helper for `booking_items`/`collection_addresses`/`booking_status_history` — mirrors `bookings`' own visibility rule exactly, so the child tables can't drift out of sync with it. |
| `generate_booking_code()` | PL/pgSQL | Collision-checked, bounded-retry generator for `MPD-XXXXXX` codes. See BOOKING_IMPLEMENTATION.md §3. |
| `get_slot_availability(date)` | SQL, `SECURITY DEFINER` | Real capacity check — counts actual non-cancelled bookings per slot for a date. Public. |
| `create_booking(...)` | RPC, `SECURITY DEFINER` | The only way a booking is ever created. Validates item/availability/coupon, recalculates price server-side, transactional, idempotent. See BOOKING_IMPLEMENTATION.md §4. |
| `update_booking_stage(booking_id, stage, note)` | RPC, `SECURITY DEFINER` | The only way a booking's stage changes. Role-scoped: full flexibility for `main_admin`/`sub_admin`, narrow field-relevant stages for `collection_agent` on their own bookings only. |
| `track_booking(code, phone)`, `track_booking_timeline(code, phone)` | RPC, `SECURITY DEFINER` | The only public surface for checking a booking's status — requires both fields to match; returns minimal safe fields only. See BOOKING_IMPLEMENTATION.md §5. |

## 4. Design decisions worth knowing

- **`profiles` consolidates Firebase's `users` + `staff_users`** into one table (`role='patient'` for regular customers) — a deliberate schema improvement, not a 1:1 Firestore copy, per the explicit instruction to design a proper relational schema rather than blindly porting documents.
- **`package_features` stores a snapshot, not a live join to `tests`** — a package's advertised contents never silently change if a linked test is later edited, matching the "historically accurate" requirement for anything a customer was shown at booking/purchase time.
- **No `finance_admin` role exists** — the source app (`index-1.html`) only ever implements `main_admin`/`sub_admin`/`collection_agent`; a 4th role was not invented despite being mentioned as a hypothetical example in the request.
- **`bookings.status` (coarse) + `bookings.stage` (fine-grained) is a deliberate two-column split**, not redundancy — it mirrors the original app's own separation between a booking's payment/lifecycle state and its operational tracker position, just normalized: the original's separate `tracker_states` collection (with a JSON timeline array) is replaced here by `stage` living directly on `bookings` (always exactly 1:1 with a booking, so no reason for a separate table) plus `booking_status_history` as a proper relational audit trail instead of a JSON array column.
- **`bookings`/`booking_items`/`collection_addresses` have no INSERT/UPDATE/DELETE grant for `anon` or `authenticated` at all** — every write goes through a `SECURITY DEFINER` RPC. This isn't a stopgap; it's the actual intended design, since it's the only way to guarantee price/discount/availability are always server-computed.
- **Realtime is enabled on `bookings` and `booking_status_history`** via `supabase_realtime` publication — verified live for a logged-in user's own booking. Not usable by anonymous guests (no table grant), who get a polling fallback instead — see BOOKING_IMPLEMENTATION.md §5.
- **Real pre-existing data, discovered (not created) during the Phase 4 inspection**, kept for operational transparency: two real `profiles` rows already existed from prior genuine usage — `anmolsaini6180@gmail.com` (now `main_admin`, promoted by `sync_owner_admins()` in migration 0009 — see SECURITY.md §2.2) and `sagarmedi001@gmail.com` (unaffected, remains `role='patient'`). Two real, independently-created bookings also already existed: `MPD-U5XZGR` ("Anmol Saini") and `MPD-3RNZWS` ("Sachin Saini"). None of this was fabricated for a test — it was live data found while verifying the bootstrap migration's effect, and is called out explicitly per the project's no-fake-data / honest-reporting rule.
