# ADMIN_MIGRATION_MAP.md

Every admin feature that exists today in `index-1.html` (per [AUDIT.md §11-12](AUDIT.md)), and where it stands in the Supabase migration. `index-1.html` remains the live, untouched reference for exact current behavior — nothing here is invented; every row was inspected in the original source before being listed.

**Legend**: ✅ Migrated & tested this phase · 🚧 Schema ready, admin UI not built yet · ❌ Not started (schema + UI both pending) · ⏸️ Deferred, out of scope for now

---

## 1. Foundation (must exist before any admin module works)

| Feature (index-1.html) | Target | Status |
|---|---|---|
| RBAC roles (`main_admin`/`sub_admin`/`collection_agent`) | `profiles.role` (Phase 1) | ✅ |
| Head-Admin bootstrap + permanent lock | `handle_new_auth_user()` + `main_admin_locks` (Phase 1) | ✅ |
| Booking ownership scoping (`attachBookingOwnership`, `_bookingsQueryForCurrentRole`) | RLS policies on `bookings` + children (Phase 2) | ✅ |
| Admin-only internal helpers exposed via public RPC (security gap) | Relocated to `private` schema (Phase 3, migration 0008) | ✅ |
| Admin app shell (login gate, sidebar, layout) | `admin/` — this phase | ✅ (built this session) |

## 2. Dashboard

| Feature | Target | Status |
|---|---|---|
| `loadAdminDashboard()` — KPI tiles (total/today/pending/confirmed bookings) | `admin/dashboard.html`, real queries against `bookings` | ✅ (built + tested this session) |
| Business Health Score (computed live) | Same page, simplified version | 🚧 (basic counts done; the original's weighted scoring formula not ported) |
| Date-wise Analytics | `admin/analytics.html` | ❌ |
| Revenue vs Ad Spend | Same, depends on Cash Flow tables | ❌ (blocked on §8) |
| Sub Admin Dashboard / Collection Agent Dashboard (role-specific views) | Folded into `admin/dashboard.html`'s role-aware query | 🚧 (main_admin view built; role-specific dashboards not yet) |

## 3. Bookings & Tracker

| Feature | Target | Status |
|---|---|---|
| Booking Management (list/search/filter/detail) | `admin/bookings.html` | ✅ (built + tested this session, real Supabase data) |
| Booking Edit Modal | Folded into the booking detail view | 🚧 (view built; inline edit of patient/schedule fields not yet) |
| Booking Tracker (Today/Upcoming/Pipeline/History/All views, KPIs, status modal) | `admin/tracker.html`, calling `update_booking_stage()` | ✅ (built + tested this session — status update tested live) |
| WhatsApp Manual Booking modal (staff pastes an incoming order) | Fold into a "Create Booking" action in `admin/bookings.html` | ❌ |
| Received Amount modal | Fold into booking detail (payment section) | ❌ |
| Missing Payment Data modal | `admin/payments.html` or a Bookings filter | ❌ |
| Global Admin Search | `admin/` shared search bar | ❌ |

## 4. Catalog

| Feature | Target | Status |
|---|---|---|
| Test Management (CRUD) | `admin/tests.html` — `tests` table + RLS already support this | ❌ (schema ready from Phase 1, UI not built) |
| Package Management (CRUD, incl. features/tests-included) | `admin/packages.html` — `packages`/`package_features`/`package_tests` already support this | ❌ (schema ready, UI not built) |
| Coupons (CRUD, validation rules) | `admin/coupons.html` — `coupons` table + `validate_coupon()` already support this | ❌ (schema ready, UI not built) |

## 5. People

| Feature | Target | Status |
|---|---|---|
| User Management (view/search/delete patients) | `admin/users.html` — queries `profiles` where `role='patient'` | ❌ |
| Team Management (create/edit/deactivate staff, assign `parent_sub_admin_id`) | `admin/staff.html` | ❌ |
| Transfer Collection Agent modal | Fold into `admin/staff.html` | ❌ |

## 6. Reports

| Feature | Target | Status |
|---|---|---|
| Report Management (Cloudinary upload, status) | `admin/reports.html` | ❌ — needs a new `reports` table (doesn't exist in Supabase yet: `id, patient user_id/email, booking_id?, name, status, pdf_url, cloudinary_public_id, created_at`) |
| Customer-facing My Reports | `pages/my-reports.html` | ❌ — currently still an honest "coming soon" page from Phase 1, blocked on the same `reports` table |

## 7. Finance

| Feature | Target | Status |
|---|---|---|
| Cash Flow — Income / Expense / Ads | `admin/cashflow.html` | ❌ — needs `cashflow_income`/`cashflow_expense`/`cashflow_ads` tables, none exist in Supabase yet |
| Payment Management | `admin/payments.html` | ❌ — largely derivable from `bookings.payment_status`/`payment_mode` once the UI exists |

## 8. Operational

| Feature | Target | Status |
|---|---|---|
| Activity Log | `admin/activity.html` | ❌ — needs an `activity_log` table |
| Settings (Cloudinary config, admin emails, notification toggles) | `admin/settings.html` | ❌ — needs an `app_settings` table (key/value, replacing `config/admins` + `mhl_settings`) |
| AI Insights (Claude API key + business summary) | ⏸️ | Deferred — the original already stores the API key client-side in `localStorage`, a security pattern flagged (not fixed) in [BACKEND_DEPENDENCIES.md §11](BACKEND_DEPENDENCIES.md); not worth porting as-is, and rebuilding it securely (server-side key) is its own project, not part of this admin migration. |

---

## Sequencing rationale

Bookings + Tracker were built first because (a) they're what Phase 2's entire backend was designed for and unlock the most value with the least new schema, and (b) they let staff actually operate on the bookings customers are now placing through the new public wizard — leaving that gap open the longest would have been the worst sequencing choice. Catalog management (Tests/Packages/Coupons) is next in priority since its schema is already fully ready — it's pure UI work with zero new tables. Reports, Cash Flow, and Settings each need genuinely new schema design and are scoped as their own follow-up passes rather than rushed.
