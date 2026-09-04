# ARCHITECTURE_PLAN.md — Recommended Target Architecture

This is a **recommendation for approval**, not a description of work already done. Nothing in this document has been implemented yet. See [AUDIT.md](AUDIT.md) for the current-state facts this plan is based on.

---

## 1. Guiding Principles

1. **Incremental, non-destructive.** `index-1.html` keeps working at every step. Nothing is deleted until its replacement is verified.
2. **No framework migration.** The brief explicitly rules out blindly converting to React/Vite/Next, and the audit found zero existing build tooling — introducing one now would be the single biggest source of risk for the smallest design benefit. Plain HTML/CSS/JS, split across files, achieves the multi-page requirement without that risk.
3. **Backend untouched.** Same Firebase project, same Firestore collections/fields, same security rules, same RBAC functions. The redesign is a front-end restructuring exercise, not a backend rewrite.
4. **Admin stays out of the blast radius.** The admin dashboard is large, working, and not part of this brief's complaint (the complaint is about the *public* site being single-page). It is touched only to the minimum extent required (see §8).
5. **Reuse over rewrite.** Existing functions (`attachBookingOwnership`, `_requireRole`, the tracker status machine, the toast/modal utilities, the Cloudinary/Razorpay/EmailJS call sites) are called from new pages, not reimplemented.

---

## 2. Chosen Approach & Why

**Recommended: a multi-page static site (plain HTML/CSS/JS), with shared CSS/JS extracted into external files and a small shared-chrome mechanism for the nav/footer — no bundler, no npm, no framework.**

Why this over the alternatives:

| Option | Verdict | Reason |
|---|---|---|
| **Keep single `index-1.html`, add more anchors/modals** | ❌ Rejected | This is exactly the pattern the brief wants removed; it doesn't produce real URLs, real back-button behavior, or a real multi-step booking flow. |
| **Convert to React/Next/Vite SPA** | ❌ Rejected (per explicit instruction) | No build tooling exists today; the team's current workflow is "edit HTML, deploy." A framework migration is a much larger, riskier project than the one being asked for, and would require re-implementing the entire Firebase/RBAC/admin surface to even reach parity before any visible improvement ships. |
| **Multi-page static HTML/CSS/JS (recommended)** | ✅ Recommended | Gives real URLs and a real step-by-step booking flow — the actual ask — while staying inside the project's existing skill set and hosting model. Each page loads Firebase the same way `index-1.html` already does. Zero new tooling to learn or install. |
| **Multi-page + a minimal static-site generator later** (e.g. a tiny Node script that inlines a shared header/footer at build time) | 🔷 Optional future improvement, not required now | Solves the "shared nav/footer duplicated across files" maintenance concern properly, but adds a build step. Recommend revisiting only after the plain-HTML version has shipped and proven the page structure; not a Phase-1 blocker. |

---

## 3. Recommended Folder Structure

```
/ (repo root)
├── index.html                  ← NEW homepage (replaces index-1.html as the live entry point)
├── index-1.html                ← KEPT, untouched, as the admin dashboard host during transition (see §8)
│
├── pages/
│   ├── tests.html               (Tests listing)
│   ├── test-detail.html         (Test detail — reads ?id= or ?slug=)
│   ├── packages.html            (Packages listing)
│   ├── package-detail.html      (Package detail — reads ?id=)
│   ├── about.html
│   ├── contact.html
│   ├── login.html
│   ├── my-bookings.html
│   ├── my-reports.html
│   └── track-booking.html       (public tracker)
│
├── booking/
│   ├── patient-details.html
│   ├── address.html
│   ├── schedule.html
│   ├── review.html
│   └── confirmation.html
│
├── assets/
│   ├── css/
│   │   ├── base.css             (tokens, resets, typography — extracted from the current <style> block)
│   │   ├── components.css       (buttons, cards, forms, modals, toasts)
│   │   ├── booking.css          (new: step indicator, summary rail, review layout)
│   │   └── tracker.css          (extracted from admin styles — shared by admin AND the new public tracker)
│   ├── js/
│   │   ├── firebase-init.js     (extracted verbatim from index-1.html's module script)
│   │   ├── shared-chrome.js     (injects nav + footer HTML into every page — see §5)
│   │   ├── auth.js              (login/signup/OTP — extracted, unchanged logic)
│   │   ├── booking-draft.js     (NEW: the cross-page draft object — see §6)
│   │   ├── booking-submit.js    (the Firestore-write + Razorpay + notifications logic, ported from `handleModalBooking`)
│   │   ├── tracker-shared.js    (TRACKER_STATUSES/TRACKER_FLOW + label mapping — imported by BOTH admin tracker and public tracker so they never drift apart)
│   │   └── toast.js             (extracted toast system, unchanged)
│   └── img/
│       ├── favicons/            (base64 icons extracted to real files — see AUDIT.md §16.3)
│       └── logo.svg
│
└── admin/                        (OPTIONAL Phase-later carve-out — see §8; not required for Phase 1)
```

**Why `pages/` and `booking/` as separate top-level folders**: it keeps the booking *flow* (a linear wizard, always entered via a package/test) visually and mentally distinct from standalone *destination* pages (things you navigate to directly from the nav). This mirrors the brief's own diagram.

**Shared chrome without a build step**: `shared-chrome.js` holds the nav and footer as JS template strings and injects them into a `<div id="site-header"></div>` / `<div id="site-footer"></div>` placeholder that every page includes. This gives single-source-of-truth nav/footer editing today, with zero tooling — and is a drop-in replacement for a "proper" templating system later if one is ever adopted.

---

## 4. Recommended Page Structure (maps directly to the brief's list)

| Brief's requested page | File | Notes |
|---|---|---|
| Home | `index.html` | New, focused homepage — see [UI_PLAN.md](UI_PLAN.md) §5 |
| Tests | `pages/tests.html` | Replaces the "Services" anchor section as a real listing page |
| Test Details | `pages/test-detail.html` | New — today a test only opens a small modal (`openTestModal`) |
| Packages | `pages/packages.html` | Replaces the "Health Packages" anchor section |
| Package Details | `pages/package-detail.html` | Replaces `#pkgModal` Step 1 |
| About Us | `pages/about.html` | Replaces the "About" anchor section |
| Contact Us | `pages/contact.html` | Replaces the "Contact" anchor section |
| Booking (entry) | `booking/patient-details.html` | First wizard step — see [BOOKING_FLOW.md](BOOKING_FLOW.md) |
| Patient Details | `booking/patient-details.html` | Replaces the top half of `#pkgModal` Step 2 |
| Address | `booking/address.html` | New standalone step — replaces the address/pincode/city fields |
| Schedule | `booking/schedule.html` | New standalone step — replaces the date/slot fields |
| Review | `booking/review.html` | New — does not exist today in any form |
| Booking Confirmation | `booking/confirmation.html` | Replaces `#pkgModal` Step 3 |
| Track Booking | `pages/track-booking.html` | **New** — no equivalent exists today (admin tracker is not public) |
| Login | `pages/login.html` | Replaces the Login/Signup/OTP modals |
| My Bookings | `pages/my-bookings.html` | Replaces the `pd-bookings` tab of the patient overlay |
| My Reports | `pages/my-reports.html` | Replaces the `pd-reports` tab of the patient overlay |

Not explicitly requested but currently existing and worth keeping somewhere: **My Payments** and **Profile/Overview** (the other two `pd-` tabs) — recommend folding these into `my-bookings.html` as sub-tabs of one "My Account" page, or adding two more files if a fuller account section is wanted. Flagged as an open question, not decided here.

---

## 5. Shared Chrome Strategy

- **Nav** (`assets/js/shared-chrome.js`): one template, rendered on every page, with the *current page* highlighted. Public nav items per the brief: Home · Tests · Packages · About Us · Contact · Track Booking · Login · **Book a Test** (primary CTA button). Mobile: real hamburger drawer (not just a collapsed anchor list) listing the same items.
- **Footer**: same pattern, one template.
- **Firebase init**: `assets/js/firebase-init.js` is a `<script type="module">` included identically on every page (same pattern `index-1.html` already uses) so `window._firebaseAuth`/`window._firebaseDB`/`window._firestoreFns` are available everywhere, unchanged.
- **Auth state**: `onAuthStateChanged` (in `firebase-init.js`) updates the shared nav's logged-in/out state on every page load, exactly as it does today — this already works across the whole document today, it just needs to run on every new file instead of once.

---

## 6. State/Data Sharing Across Pages (new problem, since it's no longer a SPA)

Today, "selected package" is just a JS variable (`_currentPkgIdx`) because everything is one document. Across real pages, this needs an explicit, small persistence layer:

- **`assets/js/booking-draft.js`** manages one `sessionStorage` key, e.g. `mhl_booking_draft`, shaped as a **superset of the existing booking object fields** (same field names as `handleModalBooking` already produces: `packageId`, `packageName`, `packagePrice`, `userName`, `userMobile`, `userEmail`, `userAddress`, `userPincode`, `userCity`, `scheduledDate`, `scheduledTimeSlot`, `specialNotes`, `paymentMode`, …) so the final submit function needs **zero field renaming** versus today's Firestore writes.
- Each booking step page reads the draft on load (to restore/prefill), writes its own fields into it on "Continue," and the final Review page's "Confirm" button calls the same booking-submit logic that exists today (Razorpay → Firestore `setDoc` → `attachBookingOwnership` → notifications), then clears the draft and redirects to `confirmation.html?id=<bookingId>`.
- Confirmation page reads the just-created booking back from `sessionStorage` (fast path) or Firestore by ID (refresh-safe path) — never re-submits on refresh.
- **Compact package summary** requirement (stays visible through the whole flow): a small shared component in `booking-draft.js` that renders "📦 {packageName} — ₹{price}" (+ a "Change" link back to package selection) from the same draft object, included on every booking-flow page.

`sessionStorage` (not `localStorage`) is recommended for the draft specifically because it's inherently per-tab and self-clears when the booking session ends — it shouldn't linger across unrelated future visits the way the existing `mhl_appointments` cache intentionally does.

---

## 7. Firebase/Firestore Usage — Unchanged

Every new page that needs data (packages/tests listing, booking submit, tracker lookup, my-bookings/my-reports) uses the **exact same** collections, field names, and helper functions documented in [BACKEND_DEPENDENCIES.md](BACKEND_DEPENDENCIES.md). No schema changes. No new Firestore rules required for anything except the new public Track Booking lookup (see [BOOKING_FLOW.md](BOOKING_FLOW.md) §6 for that one necessary rules addition, called out explicitly as the sole backend change this redesign requires).

---

## 8. Admin Dashboard — Minimal-Touch Strategy

**Recommendation for Phase 1: leave the admin dashboard exactly where it is, inside `index-1.html`.** Do not extract it yet. Reasons:
- It is not what the brief is asking to fix.
- It is the highest-risk code to move (RBAC, Cash Flow, staff management, the Booking Tracker) — moving it buys no user-visible benefit in this phase and creates the single largest opportunity to "break the existing admin system," which is an explicit hard constraint.
- `index-1.html` can keep serving as the authenticated admin entry point (e.g. rename its route to `/admin` at the hosting layer, or simply link "Admin Panel" to `index-1.html` from the new site) while `index.html` becomes the new public homepage.

**Only extraction planned for Phase 1**: the `TRACKER_STATUSES`/`TRACKER_FLOW` constants and the pure display-mapping logic, copied (not moved) into `assets/js/tracker-shared.js` so the new public tracker page can render the *same* stage vocabulary without duplicating magic strings by hand. The admin copy inside `index-1.html` is left running as-is; the shared file is a second, independent copy used only by the new public page until a later phase (if ever) consolidates them. This trades a small amount of duplication for zero risk to the admin dashboard.

A full admin extraction into its own `admin/` tree (per the folder sketch in §3) is left as an **optional later phase**, only after the public redesign has shipped and stabilized.

---

## 9. Migration Steps (phased rollout)

| Phase | Scope | Ships when |
|---|---|---|
| **0 — Audit** (this phase) | Documentation only. No code changes. | ✅ This PR |
| **1 — Extract shared CSS/JS** | Pull design tokens, component CSS, Firebase init, auth, toast/modal utilities out of `index-1.html`'s `<style>`/`<script>` into `assets/`, with **zero behavior change** — `index-1.html` itself can start `<link>`/`<script src>`-ing these instead of inlining them, as a parity check. | Visual/functional diff against current site is zero |
| **2 — Build new public pages** | Home, Tests, Test Detail, Packages, Package Detail, About, Contact, Login, using shared chrome + existing Firestore reads (packages/tests listeners ported as-is). | New pages live at new URLs; `index-1.html` untouched and still reachable |
| **3 — Build the booking wizard** | 5 steps + confirmation, using `booking-draft.js`, calling the ported `handleModalBooking` logic unchanged at the Review→Confirm step. | A full booking end-to-end on the new pages writes a real `bookings` doc identical in shape to today's |
| **4 — Public Track Booking** | New page + the one required Firestore-rules addition (see BOOKING_FLOW.md §6). | A booking made in Phase 3 can be tracked publicly |
| **5 — My Bookings / My Reports** | Extract from the `pd-` overlay into real pages; decide whether to upgrade to live per-user Firestore queries (see AUDIT.md §10) as part of this phase or keep the localStorage-cache approach for now. | Logged-in patient can reach these from real URLs |
| **6 — Cutover** | Point the site's root at the new `index.html`; add a link/redirect from old anchor URLs (`/#packages` etc.) to the new pages for any bookmarked/shared links; keep `index-1.html` reachable at `/admin` (or similar) indefinitely for staff. | Public launch |
| **7 — (Optional, later)** | Admin extraction into its own tree; Supabase migration (wholly separate project — see [SUPABASE_MIGRATION_PLAN.md](SUPABASE_MIGRATION_PLAN.md)). | Only after Phase 6 is stable |

Each phase is independently shippable and independently revertable — none requires the next to be started.

---

## 10. Testing / Rollback Strategy

- Because `index-1.html` is never deleted or modified for the admin portions, **rollback at any phase is "point the domain/root back at `index-1.html`."**
- Phase 1's success criterion is a literal before/after diff of the *rendered* page (not the source) showing no visible or functional change — this validates the CSS/JS extraction before any new page is built on top of it.
- Each new booking-flow page should be manually walked end-to-end (including a real Firestore write in a test/staging capacity) before Phase 6 cutover, specifically checking that: the admin Booking Management table shows the new booking identically to an old one; the admin Booking Tracker can move it through stages; RBAC ownership fields are populated correctly for a booking made while logged out (patient) vs. logged in as staff.

---

## 11. What Explicitly Does NOT Change In This Redesign

- Firebase project, config, and SDK version.
- Firestore collection names, document shapes, and field names.
- Firestore Security Rules (other than the one narrowly-scoped addition for public tracker lookup, called out explicitly when it's proposed — not part of this phase).
- The RBAC role model, ownership-scoping functions, and Head-Admin lock mechanism.
- The admin dashboard's internal logic, layout, or location (stays in `index-1.html` for Phase 1).
- Cloudinary configuration and report-upload pipeline.
- Razorpay integration logic (only its `RAZORPAY_ENABLED`/key values are ever a *business* decision, never touched by this redesign).
- Any `localStorage` key the admin dashboard currently depends on.
