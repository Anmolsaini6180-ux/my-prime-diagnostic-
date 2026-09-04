# My Prime Diagnostic

A NABL-certified diagnostic lab's public website — plain HTML/CSS/JS (no build step, no framework), backed by Supabase (Postgres + Auth, RLS-secured). The legacy `index-1.html` (Firebase-backed admin dashboard + booking system) remains untouched and running alongside this rebuild — see [ARCHITECTURE_PLAN.md](ARCHITECTURE_PLAN.md) for why, and [AUDIT.md](AUDIT.md) for what it contains.

## Status

This is an active, in-progress rebuild. **Public catalog browsing, patient auth, the full multi-step booking wizard, the public tracker, and Realtime status updates are real, live, and tested end-to-end against Supabase.** **A real admin panel now exists too** (`admin/`) — staff login with RBAC enforcement, a Dashboard with real KPIs, and full Bookings/Booking Tracker management wired to the same Supabase backend — see [BOOKING_IMPLEMENTATION.md](BOOKING_IMPLEMENTATION.md) and [ADMIN_MIGRATION_MAP.md](ADMIN_MIGRATION_MAP.md) for exactly what's verified vs. still pending (most admin modules — Tests/Packages/Coupons/Staff/Reports/Cash Flow/Settings — are not built yet). **The approved Super Admin (`anmolsaini6180@gmail.com`) is now bootstrapped at the database level** (never a frontend check — see [SECURITY.md §2.2](SECURITY.md)), and **Google OAuth login is code-complete on both login pages but not yet functional** — it needs two Dashboard-only configuration steps only the project owner can perform, documented in [GOOGLE_OAUTH_SETUP.md](GOOGLE_OAUTH_SETUP.md); until then, only email/password login works end-to-end. **Firebase and Supabase are currently two separate, non-synced systems** — see [MIGRATION_STATUS.md](MIGRATION_STATUS.md). Nothing in this repo pretends to be finished when it isn't.

**Branding note**: the real My Prime Diagnostic logo has been shared but not yet received as a file (see MIGRATION_STATUS.md / the latest session notes) — the site currently uses a placeholder 🏥 emoji mark everywhere a real logo asset belongs. Design tokens (`assets/css/tokens.css`) already closely match the logo's navy/orange palette (sourced from the original site's own CSS), pending exact pixel-level confirmation once the file is available.

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
  services/catalog.js        The only place that queries packages/tests from Supabase
  services/bookings.js       The only place that calls the booking RPCs (create_booking, track_booking, etc.)
supabase/
  migrations/                Every schema change, in order — see DATABASE.md
  seed/                      Real catalog + slot data ported from index-1.html (not synthetic)
admin/                       Staff panel: login, dashboard, bookings, tracker (real Supabase data + RLS-enforced)
assets/css/admin.css         Admin shell (sidebar/topbar/tables/tracker board), same tokens as the public site
assets/js/admin-guard.js     Real session+role check every admin page calls first (redirects non-staff, deactivated staff)
assets/js/admin-shell.js     Shared admin sidebar/topbar, only links to modules that actually exist
assets/js/admin-booking-detail-modal.js  Shared booking-detail-with-stage-update modal (used by Bookings and Tracker)
assets/js/services/admin-bookings.js     Admin booking queries — relies entirely on RLS for role scoping, no client-side filtering duplicated
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
