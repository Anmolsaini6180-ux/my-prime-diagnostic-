# My Prime Diagnostic

A NABL-certified diagnostic lab's public website — plain HTML/CSS/JS (no build step, no framework), backed by Supabase (Postgres + Auth, RLS-secured). The legacy `index-1.html` (Firebase-backed admin dashboard + booking system) remains untouched and running alongside this rebuild — see [ARCHITECTURE_PLAN.md](ARCHITECTURE_PLAN.md) for why, and [AUDIT.md](AUDIT.md) for what it contains.

## Status

This is an active, in-progress rebuild. **Public catalog browsing, patient auth, the full multi-step booking wizard, the public tracker, and Realtime status updates are real, live, and tested end-to-end against Supabase** — see [BOOKING_IMPLEMENTATION.md](BOOKING_IMPLEMENTATION.md) for exactly what was verified. Admin migration (moving staff-facing tools off `index-1.html`) is the next phase. Nothing in this repo pretends to be finished when it isn't.

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
  services/catalog.js        The only place that queries packages/tests from Supabase
  services/bookings.js       The only place that calls the booking RPCs (create_booking, track_booking, etc.)
supabase/
  migrations/                Every schema change, in order — see DATABASE.md
  seed/                      Real catalog + slot data ported from index-1.html (not synthetic)
index-1.html                 Legacy Firebase-backed app — admin dashboard lives here for now
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

## Environment

See [.env.example](.env.example) — the two values the client actually uses are public by design (like the existing Firebase config); real secrets are for future Edge Functions only.
