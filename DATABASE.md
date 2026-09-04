# DATABASE.md — Supabase Schema Reference

Live project: **my prime diagnoatics lab** (`woedykgrzczgogtymfxg`, `ap-south-1`). This document reflects what is actually deployed, verified via `list_tables`/`execute_sql`, not just what was intended.

---

## 1. Migrations applied so far

| # | File | Purpose |
|---|---|---|
| 0001 | `supabase/migrations/0001_foundation_and_catalog.sql` | `profiles`, Head-Admin bootstrap, `tests`, `packages`, `package_tests`, `package_features`, `coupons` + `validate_coupon()` RPC. RLS enabled on every table. |
| 0002 | `supabase/migrations/0002_security_hardening_fixes.sql` | Fixed a critical gap introduced in 0001 (`main_admin_locks` had RLS disabled) and a function search-path warning. See SECURITY.md §2. |
| 0003 | `supabase/migrations/0003_capture_phone_on_signup.sql` | Fixed the signup trigger to actually store the phone number collected at registration (was silently dropped). |
| — | `supabase/seed/001_catalog_seed.sql` | Real catalog data ported from `index-1.html` (5 packages, 31 features, 15 tests) — not synthetic. |

Bookings, tracker, reports, staff CRUD, and cashflow tables are **not yet created** — that's the next backend phase, scoped deliberately separately (see ARCHITECTURE_PLAN.md).

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

## 3. Functions

| Function | Type | Purpose |
|---|---|---|
| `handle_new_auth_user()` | Trigger (`auth.users` → `AFTER INSERT`) | Creates the `profiles` row for every new signup; grants `main_admin` only to the two hardcoded owner emails, only once. |
| `prevent_self_role_escalation()` | Trigger (`profiles` → `BEFORE UPDATE`) | Blocks a non-`main_admin` from changing their own `role`/`status`/`parent_sub_admin_id`, even though the RLS policy otherwise allows self-updates. |
| `is_main_admin()`, `is_staff()`, `current_user_role()` | SQL, `SECURITY DEFINER` | RLS policy helpers — avoid recursive policy evaluation. See SECURITY.md §2 for their known, accepted advisory. |
| `set_updated_at()` | Trigger helper | Keeps `updated_at` current on `profiles`/`tests`/`packages`/`coupons`. |
| `validate_coupon(code, amount)` | RPC, `SECURITY DEFINER` | The **only** public surface for coupon checks — returns validity + discount, never the coupons table itself. |

## 4. Design decisions worth knowing

- **`profiles` consolidates Firebase's `users` + `staff_users`** into one table (`role='patient'` for regular customers) — a deliberate schema improvement, not a 1:1 Firestore copy, per the explicit instruction to design a proper relational schema rather than blindly porting documents.
- **`package_features` stores a snapshot, not a live join to `tests`** — a package's advertised contents never silently change if a linked test is later edited, matching the "historically accurate" requirement for anything a customer was shown at booking/purchase time.
- **No `finance_admin` role exists** — the source app (`index-1.html`) only ever implements `main_admin`/`sub_admin`/`collection_agent`; a 4th role was not invented despite being mentioned as a hypothetical example in the request.
