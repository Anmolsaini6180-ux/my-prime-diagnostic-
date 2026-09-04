# ADMIN_MIGRATION_MAP.md

Every admin feature that exists today in `index-1.html` (per [AUDIT.md §11-12](AUDIT.md)), and where it stands in the Supabase migration. `index-1.html` remains the live, untouched reference for exact current behavior — nothing here is invented; every row was inspected in the original source before being listed.

**Legend**: ✅ Migrated & tested this phase · 🚧 Schema ready, admin UI not built yet · ❌ Not started (schema + UI both pending) · ⏸️ Deferred, out of scope for now

---

## 1. Foundation (must exist before any admin module works)

| Feature (index-1.html) | Target | Status |
|---|---|---|
| RBAC roles (`main_admin`/`sub_admin`/`collection_agent`) | `profiles.role` (Phase 1) | ✅ |
| Head-Admin bootstrap + permanent lock | `handle_new_auth_user()` + `main_admin_locks` (Phase 1) | ✅ |
| Booking ownership scoping (`attachBookingOwnership`, `_bookingsQueryForCurrentRole`) | RLS policies on `bookings` + children (Phase 2) | ✅ — **sub_admin visibility fixed this phase** (migration 0010 Part 2); it previously matched 0 real bookings, see SECURITY.md §2.3 |
| Admin-only internal helpers exposed via public RPC (security gap) | Relocated to `private` schema (Phase 3, migration 0008) | ✅ |
| Admin app shell (login gate, sidebar, layout) | `admin/` | ✅ — sidebar now renders every module below, filtered per-role (`assets/js/admin-shell.js`) |
| Super Admin (Head-Admin) bootstrap for a specific real email, DB-enforced | `private.owner_emails()` + `private.sync_owner_admins()` (Phase 4, migration 0009/0009b) | ✅ — see SECURITY.md §2.2. **Absolute protection added this phase**: a trigger now blocks *any* caller (even another main_admin) from demoting/deactivating a locked account (migration 0010 Part 3). |
| Google OAuth login (admin + public), role-based post-login redirect | `admin/login.html` + `pages/login.html` + `assets/js/post-login-redirect.js` (Phase 4) | 🚧 — unchanged this phase; still blocked on Dashboard config only the project owner can do (see [GOOGLE_OAUTH_SETUP.md](GOOGLE_OAUTH_SETUP.md)) |
| **Login required to create a booking** | `create_booking()` RPC (Phase 5, migration 0010 Part 1) | ✅ — **critical fix**: the RPC previously had no `auth.uid()` check at all and was `anon`-callable; a guest could create a real booking with `user_id = NULL`. Now rejects with no session, verified with a real unauthenticated HTTP call returning 401. See SECURITY.md §2.4. |

## 2. Dashboard

| Feature | Target | Status |
|---|---|---|
| `loadAdminDashboard()` — KPI tiles (total/today/pending/confirmed bookings) | `admin/dashboard.html`, real queries against `bookings` | ✅ — **rebuilt this phase** on the new `admin_dashboard_stats()` RPC (one RLS-respecting call instead of 8 separate queries); now also shows Sample Collected, Processing, Home/Walk-in, Unassigned/Assigned, and Booking Value |
| Business Health Score (computed live) | Same page, simplified version | 🚧 (basic counts done; the original's weighted scoring formula not ported) |
| Date-wise Analytics | `admin/analytics.html` | ✅ — bookings by day (14-day), by status, home vs walk-in, top tests/packages, collection agent workload. Real queries, no charting library (CSS bar visualizations) |
| Revenue vs Ad Spend | Same, depends on Cash Flow tables | ❌ (blocked on §7 — no ad-spend data exists anywhere) |
| Sub Admin Dashboard / Collection Agent Dashboard (role-specific views) | Folded into `admin/dashboard.html`'s role-aware query | 🚧 (numbers are correctly RLS-scoped per role via `admin_dashboard_stats()`; no visually distinct layout per role yet) |

## 3. Bookings & Tracker

| Feature | Target | Status |
|---|---|---|
| Booking Management (list/search/filter/detail) | `admin/bookings.html` | ✅ — deep-link search (`?q=`) added this phase for the Users page's "View bookings" link |
| Booking Edit Modal | Folded into the booking detail view | ✅ **built this phase** — `admin_update_booking()` RPC + edit form in `assets/js/admin-booking-detail-modal.js` (patient/collection/address/schedule/notes/status/agent). Tested live end-to-end. Known limitation: cannot change the booked test/package itself (price re-derivation across an item swap was judged too complex/risky to rush) |
| Booking Tracker (Today/Upcoming/Pipeline/History/All views, KPIs, status modal) | `admin/tracker.html`, calling `update_booking_stage()` | ✅ (unchanged this phase; now also carries the Edit/Assign additions via the shared modal) |
| Admin Add Booking (staff books on behalf of a walk-in/phone-in patient) | `admin/add-booking.html` | ✅ **built this phase** — reuses `create_booking()` exactly (no duplicated business logic); server detects the caller is staff and sets `creator_role='staff'`, `user_id=NULL`. Tested live, real booking created and verified in the database |
| WhatsApp Manual Booking (staff pastes an incoming message, reviews, creates) | `admin/whatsapp-booking.html` + `assets/js/whatsapp-parser.js` | ✅ **built this phase** — line-based "Label: Value" parser (matches the format specified for this phase, not the original app's partner-confirmation-specific format — see AUDIT.md's original `parseAndFillBooking`). Ambiguous fields (date/time) are shown as a hint, never auto-applied. Tested live end-to-end including catalogue-item matching |
| Customer/Staff WhatsApp confirmation (`wa.me` click-to-chat, never auto-sent) | `assets/js/whatsapp-helper.js`, wired into `booking/confirmation.html` + both new admin booking pages | ✅ **built this phase** — tested live; generates a correct pre-filled message, phone normalized to `91XXXXXXXXXX` |
| Received Amount modal | Fold into booking detail (payment section) | ❌ — `payment_mode`/`payment_status` are visible in the detail view; no separate "record payment" action yet (no online payment gateway exists to reconcile against — see BOOKING_IMPLEMENTATION.md) |
| Missing Payment Data modal | `admin/payments.html` or a Bookings filter | ❌ |
| Global Admin Search | `admin/` shared search bar | ❌ — each module has its own search/filter instead |

## 4. Catalog

| Feature | Target | Status |
|---|---|---|
| Test Management (CRUD) | `admin/tests.html` | ✅ **built this phase** — Add/Edit/Activate/Deactivate (soft-delete via `is_active`, matching the original's own model — never a hard delete, since `booking_items.test_id` references historical bookings). Main Admin only (existing RLS); Sub Admin gets a read-only view. Every change is logged to `activity_log` automatically via a database trigger. Tested live: create + deactivate both verified in the database |
| Package Management (CRUD, incl. features/tests-included) | `admin/packages.html` | ✅ **built this phase** — same pattern as Tests. Tests-included/features are edited as one-per-line text lists (simplification — no drag-and-drop reorder UI) that replace the package's `package_tests`/`package_features` rows on save |
| Coupons (CRUD, validation rules) | `admin/coupons.html` | ✅ **built this phase** — Main Admin only, with **no read access for anyone else at all** (unlike Tests/Packages) — coupons has zero sub_admin RLS policy by original design (SECURITY.md §4: the full code list must never be scrapeable). Tested live: create + deactivate verified in the database |

## 5. People

| Feature | Target | Status |
|---|---|---|
| User Management (view/search patients) | `admin/users.html` | ✅ **built this phase** — Main Admin only (profiles RLS gives sub_admin visibility only into their own staff team, never patients). **Delete was intentionally not implemented** — real user deletion needs the Admin API (another Edge Function) and was judged out of scope for this pass; NOT COMPLETE, flagged honestly rather than faked |
| Team Management (create/edit/deactivate staff, assign `parent_sub_admin_id`) | `admin/team.html` | ✅ **built this phase** — Main Admin: full CRUD (role change, enable/disable, workload). Sub Admin: read-only view of their own team (matches actual RLS — no update policy exists for sub_admin on other profiles). The protected Super Admin is visibly badged and its controls are hidden, backed by the migration 0010 trigger regardless |
| Add Staff (real account creation) | `supabase/functions/admin-create-staff` (Edge Function) | ✅ **built this phase** — the only way a new `sub_admin`/`collection_agent` account is created. Uses `auth.admin.inviteUserByEmail()` server-side (service-role key never leaves the function); the invited person sets their own password via Supabase's real invite email — no password is ever created or seen by this system. Explicitly rejects a request for `role='main_admin'`. Tested live: real invite sent, profile correctly promoted, and both the "non-main_admin caller" and "role=main_admin requested" rejection paths verified against the deployed function |
| Transfer Collection Agent modal | Fold into `admin/team.html` (role/parent change) + `assign_collection_agent()` on the booking side | ✅ — role/reporting-line change is available in Team Management; per-booking (re)assignment is the dedicated Assign Collection Agent control in the booking detail modal |

## 6. Reports

| Feature | Target | Status |
|---|---|---|
| Booking/Revenue/Collection report with filters + CSV export | `admin/reports.html` | ✅ **built this phase** — date range, status, collection-type filters; real CSV export (client-side Blob, no fake export). Tested live |
| Report Management (Cloudinary upload, status) | `admin/reports.html` (a different, unbuilt feature sharing the same name in the original app) | ❌ — needs a new `reports` table (doesn't exist in Supabase yet: `id, patient user_id/email, booking_id?, name, status, pdf_url, cloudinary_public_id, created_at`). Out of scope for this phase |
| Customer-facing My Reports | `pages/my-reports.html` | ❌ — unchanged, still an honest "coming soon" page, blocked on the same `reports` table |

## 7. Finance

| Feature | Target | Status |
|---|---|---|
| Cash Flow — Income / Expense / Ads | `admin/cashflow.html` | ❌ — needs `cashflow_income`/`cashflow_expense`/`cashflow_ads` tables, none exist in Supabase yet. Out of scope for this phase |
| Payment Management | `admin/payments.html` | ❌ — largely derivable from `bookings.payment_status`/`payment_mode` once the UI exists |

## 8. Operational

| Feature | Target | Status |
|---|---|---|
| Activity Log | `admin/activity.html` | ✅ **built this phase** — new `activity_log` table, written automatically by every RPC and by triggers on Tests/Packages/Coupons/Settings changes (never a client-writable table). Main Admin sees everything; Sub Admin sees their own actions plus activity on bookings they can access; Collection Agent (RLS-only, no nav link) sees their own actions only |
| Settings | `admin/settings.html` | ✅ **built this phase** — new `app_settings` table, Main Admin only. Only 3 genuinely-used keys exist (`lab_name`, `support_phone`, `support_email`) — no placeholder/fake settings. `support_phone`/`lab_name` are live-wired into the public site footer (`assets/js/shared-chrome.js`), verified in the browser |
| AI Insights (Claude API key + business summary) | ⏸️ | Deferred — unchanged from Phase 3's assessment; the original already stores the API key client-side in `localStorage` (BACKEND_DEPENDENCIES.md §11), and rebuilding it securely is its own project |

---

## Sequencing rationale (this phase)

The single highest-priority item was the login-required-booking gap (§1) — a real, live, exploitable hole found during the mandatory pre-work inspection, fixed and verified with a genuine unauthenticated HTTP request before anything else. From there: booking operations (Edit/Assign/Add Booking/WhatsApp Booking) came next since they're the direct "complete the booking lifecycle" ask; then Team Management + the Add Staff Edge Function (the most architecturally involved new piece — real account creation without ever touching a password); then Catalog CRUD (schema was already fully ready, pure UI work); then Users/Activity/Settings/Reports/Analytics. Cash Flow and the Cloudinary-backed Reports table were left out of scope — both need real new schema design decisions this phase didn't have a mandate to make up.
