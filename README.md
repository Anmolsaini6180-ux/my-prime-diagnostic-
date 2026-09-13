# My Prime Diagnostic

A NABL-certified diagnostic lab's public website — plain HTML/CSS/JS (no build step, no framework), backed by Supabase (Postgres + Auth, RLS-secured). The legacy `index-1.html` (Firebase-backed admin dashboard + booking system) remains untouched and running alongside this rebuild — see [ARCHITECTURE_PLAN.md](ARCHITECTURE_PLAN.md) for why, and [AUDIT.md](AUDIT.md) for what it contains.

## Status

This is an active, in-progress rebuild. **Public catalog browsing, patient auth, the full multi-step booking wizard (now login-required — see below), the public tracker, and Realtime status updates are real, live, and tested end-to-end against Supabase.** **A real, extensive admin panel now exists** (`admin/`) — Dashboard, Bookings (view/edit/assign agent), Booking Tracker, Add Booking, WhatsApp Booking, Tests/Packages/Coupons management, Team Management (with a real staff-invite Edge Function), Users, Reports (with CSV export), Analytics, Activity Log, and Settings — all wired to the same Supabase backend with real RBAC. See [ADMIN_MIGRATION_MAP.md](ADMIN_MIGRATION_MAP.md) for exactly what's verified vs. still pending (Cash Flow and the Cloudinary-backed Reports table remain out of scope). **A booking can no longer be created by a logged-out visitor** — this was found to be a real, live gap and fixed at both the database and UI level, see [SECURITY.md §2.3](SECURITY.md). **The approved Super Admin (`anmolsaini6180@gmail.com`) is bootstrapped at the database level and now absolutely protected from demotion** (never a frontend check — see [SECURITY.md §2.2/§2.4](SECURITY.md)), and **Google OAuth login is code-complete on both login pages but not yet functional** — it needs two Dashboard-only configuration steps only the project owner can perform, documented in [GOOGLE_OAUTH_SETUP.md](GOOGLE_OAUTH_SETUP.md); until then, only email/password login works end-to-end. **Firebase and Supabase are currently two separate, non-synced systems** — see [MIGRATION_STATUS.md](MIGRATION_STATUS.md). Nothing in this repo pretends to be finished when it isn't.

**Branding note**: the real My Prime Diagnostic logo is now in the project (`assets/img/logo.jpg`) and used sitewide — header, footer, admin sidebar, admin login. It arrived embedded in a real landing-page HTML file the business supplied (see `pages/offer-full-body-checkup.html`), which had already computed its own logo-derived palette; `assets/css/tokens.css` now uses those exact values (`#174ea6` blue / `#102a43` navy / `#f26b21` orange) instead of the earlier placeholder pulled from index-1.html's own CSS.

## Running it locally

No build step — any static file server works:

```bash
npx http-server -p 5500 -c-1
```

Then open `http://localhost:5500/index.html`. (A `.claude/launch.json` is already set up for the `run`/preview tooling in this environment.)

## Project structure

```
index.html                  New public homepage
pages/                       Tests, Packages, detail pages, About, Contact, Login, Track Booking, My Bookings, My Reports
booking/                     The 5-step wizard: patient-details, collection, schedule, review, confirmation
assets/css/                  tokens.css → base.css → components.css → booking.css (stepper, summary rail, timeline)
assets/js/
  supabase-client.js         Supabase client init (public URL + publishable key — see SECURITY.md)
  shared-chrome.js           Shared nav + footer, injected into every page
  booking-draft.js           Cross-page booking state (sessionStorage) + stepper/summary-rail rendering
  tracker-shared.js          The one place stage keys/labels/colors are defined — public tracker and (later) admin both import this
  post-login-redirect.js     The one place "where does this session belong" is decided (patient vs. staff), shared by both login pages
  whatsapp-helper.js         Builds the wa.me click-to-chat link + confirmation message (customer + admin) — never auto-sends anything
  whatsapp-parser.js         "Smart Paste" parser for WhatsApp Booking — conservative, flags fields it isn't sure of instead of guessing
  admin-ui.js                Shared toast notifications + confirm-dialog used by every admin write action
  services/catalog.js        The only place that queries packages/tests from Supabase
  services/bookings.js       The only place that calls the booking RPCs (create_booking, track_booking, etc.)
  services/settings.js       Reads/writes app_settings — the only place that does
  services/team.js           Staff queries + the only caller of the admin-create-staff Edge Function
supabase/
  migrations/                Every schema change, in order — see DATABASE.md
  seed/                      Real catalog + slot data ported from index-1.html (not synthetic)
  functions/admin-create-staff/  The only code in this project that touches the Supabase Admin API — see SECURITY.md §2.5
admin/                       Staff panel — see ADMIN_MIGRATION_MAP.md for the full module list (Dashboard, Bookings, Tracker, Add Booking,
                              WhatsApp Booking, Tests, Packages, Coupons, Users, Team Management, Reports, Analytics, Activity Log, Settings)
assets/css/admin.css         Admin shell (sidebar/topbar/tables/tracker board/toasts/confirm dialogs), same tokens as the public site
assets/js/admin-guard.js     Real session+role check every admin page calls first (redirects non-staff, deactivated staff)
assets/js/admin-shell.js     Shared admin sidebar/topbar — nav items are filtered per-role before rendering, mirroring real RLS/RPC access
assets/js/admin-booking-detail-modal.js  Shared booking-detail view + edit + assign-agent + stage-update modal (used by Bookings and Tracker)
assets/js/services/admin-bookings.js     Admin booking queries/RPCs — relies entirely on RLS for role scoping, no client-side filtering duplicated
index-1.html                 Legacy Firebase-backed app — everything not yet in admin/ still lives here
```

## Documentation index

| File | Covers |
|---|---|
| [AUDIT.md](AUDIT.md) | What `index-1.html` actually contains, as-built |
| [ARCHITECTURE_PLAN.md](ARCHITECTURE_PLAN.md) | Why plain HTML/CSS/JS, folder structure, phased rollout |
| [BOOKING_FLOW.md](BOOKING_FLOW.md) | Old booking flow(s) vs. the built multi-step wizard, and the Track Booking security decision |
| [BOOKING_IMPLEMENTATION.md](BOOKING_IMPLEMENTATION.md) | What's actually built and tested vs. what's next, bugs found and fixed, real test results |
| [UI_PLAN.md](UI_PLAN.md) | Design direction and page-by-page UI notes |
| [BACKEND_DEPENDENCIES.md](BACKEND_DEPENDENCIES.md) | Everything `index-1.html` depends on (Firebase, Cloudinary, Razorpay, etc.) |
| [DATABASE.md](DATABASE.md) | The actual live Supabase schema |
| [SECURITY.md](SECURITY.md) | RLS model, key handling, known issues and what's verified vs. not |
| [SUPABASE_MIGRATION_PLAN.md](SUPABASE_MIGRATION_PLAN.md) | Firebase → Supabase migration plan (broader scope, still in progress) |
| [ADMIN_MIGRATION_MAP.md](ADMIN_MIGRATION_MAP.md) | Every admin feature in `index-1.html`, and exactly which are/aren't migrated yet |
| [MIGRATION_STATUS.md](MIGRATION_STATUS.md) | Which backend serves what right now, and what real cutover would require |
| [GOOGLE_OAUTH_SETUP.md](GOOGLE_OAUTH_SETUP.md) | The exact Dashboard-only steps needed to finish enabling Google login (code is already in place) |

## Environment

See [.env.example](.env.example) — the two values the client actually uses are public by design (like the existing Firebase config); real secrets are for future Edge Functions only.
