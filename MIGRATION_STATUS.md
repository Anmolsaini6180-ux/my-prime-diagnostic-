# MIGRATION_STATUS.md

Firebase → Supabase migration status. Firebase is untouched and remains the fallback/legacy system until this migration is explicitly declared complete and approved for cutover — nothing here has flipped that switch.

---

## 1. Current state: which backend serves what

| Surface | Backend | Notes |
|---|---|---|
| `index-1.html` (legacy site + full admin) | **Firebase** (Auth + Firestore) | Completely untouched — zero diff against the original baseline commit. Still the only place several modules exist at all (Cash Flow, Settings, Activity Log, AI Insights, WhatsApp manual booking, coupons/tests/packages admin UI). |
| New public site (`index.html`, `pages/`, `booking/`) | **Supabase** (Auth + Postgres + RLS + Realtime) | Fully live: catalog browsing, patient auth, the 5-step booking wizard, public tracker, My Bookings. |
| New admin panel (`admin/`) | **Supabase** | Live: staff login/RBAC gate (incl. Google-ready), Dashboard (real KPIs incl. revenue), Bookings (list/search/filter/detail/**edit/assign agent**), Booking Tracker, **Add Booking**, **WhatsApp Booking**, **Tests/Packages/Coupons management**, **Team Management + real staff-invite Edge Function**, **Users**, **Reports (CSV export)**, **Analytics**, **Activity Log**, **Settings**. |
| New admin panel — everything else | **Not built yet** | Cash Flow (Income/Expense/Ads) and the Cloudinary-backed Reports/My Reports feature — both need new schema design decisions out of scope for this phase. See [ADMIN_MIGRATION_MAP.md](ADMIN_MIGRATION_MAP.md) for the full breakdown. |

**There are currently two entirely separate, non-overlapping data stores** — the Firebase project (`metrohealthlab-c864d`) that `index-1.html` reads/writes, and the Supabase project (`woedykgrzczgogtymfxg`) that the new pages/admin read/write. **They do not sync with each other.** A booking made through the new Supabase-backed wizard does not appear in `index-1.html`'s admin, and vice versa. This is a known, deliberate consequence of building the replacement alongside the original rather than migrating the original's live data — see §3.

## 2. Why no data migration has happened yet

Firebase holds real, presumably-live production data (real patient bookings, real staff accounts) accumulated through `index-1.html`. Migrating that data into Supabase's schema is a distinct, higher-stakes project from building the replacement system, for reasons already flagged in [SUPABASE_MIGRATION_PLAN.md](SUPABASE_MIGRATION_PLAN.md): Firebase Auth UIDs and Supabase Auth UIDs are different identifier spaces, existing RBAC/ownership fields are keyed to Firebase UIDs, and a real data migration needs its own careful, auditable pass (export → transform → import → verify) rather than being folded into UI/schema-design work. **No production Firestore data has been read, exported, or copied as part of this work.**

## 3. What "cutover" would actually require (not done)

1. A real plan for existing Firebase-side bookings/staff/reports — either migrate them into Supabase with a UID-remapping strategy, or run both systems in parallel for some defined period and reconcile manually.
2. The remaining admin modules (§1) built and tested to the same standard as Bookings/Tracker.
3. The `reports`, `cashflow_*`, `activity_log`, and `app_settings` tables designed, migrated, and wired (none exist in Supabase yet).
4. A decision on Cloudinary report continuity (already flagged as "keep, don't replace" — needs the new `reports` table before the admin upload flow and customer-facing My Reports can go live).
5. Explicit approval, since this is a business-critical cutover, not a technical checkbox.

**None of this has been started.** This document exists to make that gap visible, not to imply it's close.

## 4. What must never happen without separate, explicit approval

- Deleting or modifying the Firebase project, its Firestore data, or its Security Rules.
- Deleting or modifying `index-1.html`.
- Treating the new Supabase-backed system as "the real one" for business operations while real bookings might still be landing in Firebase via `index-1.html` — until both are reconciled, staff must keep using whichever system customers are actually booking through.
