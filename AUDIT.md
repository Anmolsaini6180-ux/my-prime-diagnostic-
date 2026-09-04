# AUDIT.md — Current State Audit

**My Prime Diagnostic — Website & Admin Platform**
Audit date: 2026-09-04 · Branch audited: `feature/website-redesign` · Commit: `1828fe8`

This document is a factual, as-is snapshot of the existing codebase. It contains **no redesign decisions** — those live in [ARCHITECTURE_PLAN.md](ARCHITECTURE_PLAN.md), [BOOKING_FLOW.md](BOOKING_FLOW.md), [UI_PLAN.md](UI_PLAN.md), [BACKEND_DEPENDENCIES.md](BACKEND_DEPENDENCIES.md), and [SUPABASE_MIGRATION_PLAN.md](SUPABASE_MIGRATION_PLAN.md).

---

## 1. Executive Summary

The entire product — public marketing site, patient self-service dashboard, and full staff/admin back-office — is **one static HTML file**: [`index-1.html`](index-1.html) (907 KB, 14,319 lines). There is no build tool, no package manager, no framework, and no other source file in the repository. All CSS and JavaScript are inline in that single file, loaded directly by the browser with zero compilation step.

Despite the unconventional single-file shape, the application is **not a toy**. It has:
- A real Firebase backend (Auth + Firestore) with a genuinely hardened, documented RBAC model and a fixed history of a discovered-and-patched privilege-escalation bug (visible in code comments).
- A working, fairly sophisticated **admin-only Booking Tracker** with a 6-stage pipeline, live Firestore sync, Kanban/timeline views, and CSV export.
- Live Razorpay, Cloudinary, EmailJS, WhatsApp-link, Google-Sheets-webhook, and GA4 integrations.
- A parallel "Cash Flow" (income/expense/ad-spend) mini-ERP inside the admin dashboard.

The core problem the redesign brief is solving is real: **every customer-facing "page" today is actually an anchor-scroll section or a modal overlay on one document**, and the entire booking form (patient details + address + date/time + payment) is one dense step crammed inside a package popup.

---

## 2. Repository State

```
Branch:        feature/website-redesign  (confirmed via git branch --show-current)
Tracking:      origin/feature/website-redesign (up to date)
Remote:        https://github.com/Anmolsaini6180-ux/my-prime-diagnostic-.git
Latest commit: 1828fe8 "chore: add existing website baseline"
Working tree:  clean
```

**⚠️ Finding: `main` does not exist yet**, locally or on the remote (`git ls-remote --heads origin` returns only `feature/website-redesign`). There is currently nothing to accidentally merge into — but it also means this feature branch *is* the de facto mainline until a `main` is created. No action taken; flagged for awareness only.

### 2.1 Full file inventory (repo root, excluding `.git`)

| Path | Size | Notes |
|---|---|---|
| `index-1.html` | 907,002 bytes / 14,319 lines | The entire application |

That is the complete repository. No `package.json`, no `.gitignore`, no `assets/` folder, no `firebase.json`/`.firebaserc`, no `firestore.rules`, no `manifest.json`, no `/icons` — **even though `index-1.html` references all of these** (see §16, Gaps).

---

## 3. Technology Stack (as found)

| Layer | Technology | Version / detail |
|---|---|---|
| Markup/CSS/JS | Hand-written HTML5, CSS3, vanilla ES6+ JavaScript | No framework, no TypeScript, no bundler |
| Backend | Firebase (Google) | JS SDK **v10.12.0**, loaded via `type="module"` `<script>` from `gstatic.com` (no npm install) |
| Firebase services used | Auth, Firestore | Both actively used. **Storage** is initialized but only used as a legacy fallback (see §15.1) |
| Database | Cloud Firestore | Native mode, document/collection model, real-time listeners (`onSnapshot`) used extensively |
| File hosting | Cloudinary | Unsigned upload preset, used solely for patient report PDFs |
| Payments | Razorpay Checkout.js | Loaded via CDN `<script>`; currently **test-mode key + disabled flag** (see §15.2) |
| Email | EmailJS (`@emailjs/browser@4`) | Free-tier, 200 emails/month |
| Messaging | WhatsApp `wa.me` deep links | Not the official WhatsApp Business API — just link-opening |
| Analytics | Google Analytics 4 (`gtag.js`) | Measurement ID `G-SEPVHXBRQP` |
| Backup logging | Google Apps Script Web App (Sheets) | Every booking is POSTed to it, fire-and-forget |
| AI feature | Anthropic Claude API | Called client-side using an API key the admin pastes into Settings and that is stored in `localStorage` (see §16) |
| Fonts | Google Fonts | `Sora` (body) + `Clash Display` (headings) |
| Icons | Font Awesome 6.5.0 | CDN |
| Hosting model implied | Static hosting (Firebase Hosting–shaped, given `firebase.json`-style comments and root-relative `/manifest.json`, `/icons/...` paths) | Not confirmed — no hosting config in repo |

**No React, Vue, Next.js, or Vite exists anywhere in this codebase today.** (Relevant to the instruction not to blindly convert to one.)

---

## 4. File Structure Map of `index-1.html`

Approximate line ranges (see file for exact boundaries):

| Lines | Content |
|---|---|
| 1–111 | `<head>`: meta/SEO tags, Open Graph/Twitter cards, PWA meta, favicons (inline base64), GA4 snippet, JSON-LD `MedicalBusiness` schema, Google Fonts, Font Awesome |
| 112–501 | `<script type="module">` — Firebase init, `firebaseConfig`, RBAC role resolution, Head-Admin bootstrap/lock, realtime listeners for packages/tests/bookings, `onAuthStateChanged` |
| 502–505 | EmailJS SDK + Razorpay Checkout SDK `<script>` tags |
| 506–2,826 | `<style>` — ~2,320 lines of CSS (design tokens, public site styles, admin dashboard styles, patient dashboard styles) |
| 2,830–3,855 | Body markup: PWA install banner, toast container, **nav**, mobile search overlay, **Login/Signup/OTP modals**, cart sidebar, **Hero → Services → Why Us → Packages → "Booking Process" → Report Portal → Testimonials → About → Contact** sections, **Package Detail Modal (3-step booking)**, Footer, floating/mobile-sticky CTA |
| 3,856–5,137 | `<script>` — auth (Google/email/OTP), booking-confirmation email, Firestore save helpers, modal open/close, cart logic, **`handleBooking()`** (cart checkout path), coupon lookup/apply, toast system |
| 5,139–7,080 | Body markup: **entire Admin Dashboard** (RBAC-gated nav, Dashboard/Analytics/Users/Team/Bookings/Reports/Payments/Tests/Packages/Coupons/Settings/AI Insights/Activity Log/Cash Flow/Booking Tracker pages, ~15 modals) |
| 7,081–7,252 | Body markup: **Patient "My Account" dashboard** (`pd-` prefixed) — Overview/Profile/Bookings/Reports/Payments tabs, rendered as a full-screen overlay, not a page |
| 7,253–11,806 | `<script>` — the largest block: admin data loading/rendering for every admin page, Cash Flow logic, Cloudinary report upload, **package-modal booking flow (`openPkgModal` → `handleModalBooking` → success screen)**, patient dashboard data binding |
| 11,808–12,489 | Body markup + logic: **WhatsApp Manual Booking modal** (staff tool to paste a WhatsApp order and auto-fill a booking) and **Received Amount modal** |
| 12,660–13,437 | `<script>` — RBAC helper functions (`_requireRole`, ownership scoping), staff (Sub Admin/Collection Agent) CRUD, Transfer Agent modal |
| 13,439–14,124 | `<script>` — **Booking Tracker** (admin): status constants, Firestore sync, KPsection rendering, Today/Upcoming/Pipeline/History/All views, status/detail modals, CSV export |
| 14,126–14,316 | Missing Payment modal, PWA install trigger |

---

## 5. Design System Already In Place

This is worth preserving, not replacing:

**Colors** (CSS custom properties, `:root`, with a dark-mode override block):
| Token | Light | Dark |
|---|---|---|
| `--blue` (primary) | `#04378A` | same |
| `--blue-light` | `#3C63A4` | same |
| `--orange` (accent) | `#F16C0F` | same |
| `--text` | `#0F172A` | `#F0F6FF` |
| `--bg` | `#FFFFFF` | `#080F1E` |
| `--card-bg` | `#FFFFFF` | `#0E1A30` |

Dark mode is a real, working feature (`data-theme` attribute on `<html>`, toggle button in nav) — not just a media query.

**Admin dashboard has its own separate dark "SaaS" palette** (`--a-bg: #0A0F1E`, `--a-teal: #2DD9B9`, `--a-orange: #FF9142`, `--a-purple: #A78BFA`, etc.) — visually distinct from the public site, which is intentional (staff tool vs. patient-facing brand).

**Typography:** `Clash Display` for headings, `Sora` for body — a genuinely premium pairing already selected. No reason to change it.

---

## 6. Public-Facing Surface (current)

The public nav (`<nav id="navbar">`) links are **all in-page anchors**: Services, Why Us, Packages, Reports, About, Contact — plus a live search box (searches tests/packages), cart icon, dark-mode toggle, and Login/Sign Up buttons (replaced by a user-avatar dropdown once logged in: Patient Dashboard / My Profile / My Bookings / My Reports / My Payments / Admin Panel (staff only) / Logout).

There is **no hamburger-driven page menu on mobile** distinct from desktop — mobile reuses the same anchor nav collapsed behind a hamburger (`#hamburger`), which is a reasonable pattern already, just pointed at anchors instead of routes.

**Everything that should be a distinct page today is a modal or overlay**, all layered on top of the one document:
- Login / Signup / OTP — modals
- Cart — slide-in sidebar
- Package Detail + Booking (3 steps) — a single modal (`#pkgModal`)
- Patient "My Account" (Overview/Profile/Bookings/Reports/Payments) — full-screen overlay (`#pdOverlay`)
- Entire Admin Dashboard — full-screen overlay (RBAC-gated)

---

## 7. Booking System — Two Parallel Pathways Found

This is the single most important functional finding for the redesign.

### 7.1 Pathway A — Package Modal (`handleModalBooking`, ~line 11,606)
Triggered by "Book Now"/"View Details & Book" on a package card → opens `#pkgModal` → Step 1 (package detail, read-only) → Step 2 (one dense form: name, phone, email, DOB, address, pincode, city, date, time-slot dropdown, notes, payment-method choice) → Step 3 (success screen with Booking ID). This is the **primary, currently-used, single-package purchase flow** and the one the redesign brief's desired flow maps onto most directly.

### 7.2 Pathway B — Cart Checkout (`handleBooking`, ~line 4,810)
Triggered by "Add to Cart" on one or more tests/packages → cart sidebar → "Proceed to Booking" scrolls to a `#booking` section form (name/phone/email/date/slot/area/pin/test-dropdown/collection-type/address/**coupon code**). Supports **coupon codes** (Pathway A currently does not). This appears to be an older/parallel flow for multi-item purchases.

**Both pathways**: validate an Indian 10-digit mobile number (`^[6-9]\d{9}$`) and 6-digit pincode, generate a `MPD-<Date.now()>` booking ID, call `attachBookingOwnership()` (RBAC stamping), optionally run Razorpay Checkout, `setDoc`/`addDoc` to Firestore `bookings`, mirror to `localStorage.mhl_appointments`, POST to the Google Sheet webhook, and conditionally fire a WhatsApp `wa.me` link + EmailJS confirmation email based on admin toggles in `mhl_settings`.

**Neither pathway currently offers a "Home Collection vs. Visit Lab" choice** — collection type is hardcoded to `"Home Sample Collection"` in Pathway A; Pathway B has a `#bkCollection` field whose options weren't fully enumerated in this pass. See [BOOKING_FLOW.md](BOOKING_FLOW.md) for the field-by-field breakdown and the reconciliation recommendation.

---

## 8. Authentication

Firebase Auth, methods wired: Google popup (`signInWithPopup`), email/password (`signInWithEmailAndPassword` / `createUserWithEmailAndPassword`), password reset (`sendPasswordResetEmail`), and phone/OTP scaffolding (`RecaptchaVerifier`, `signInWithPhoneNumber`, plus a custom OTP modal with `sendOtp`/`otpNext`/`verifyOtp`). The OTP modal's exact wiring to Firebase phone auth vs. a custom flow was not traced line-by-line in this pass — **recommend a functional smoke-test before relying on it** in the new flow.

`onAuthStateChanged` drives a single `window.currentUser` object used everywhere (nav avatar, patient dashboard, admin gating).

---

## 9. Booking Tracker (Admin) — Already Sophisticated

Defined ~line 13,453 (`TRACKER_STATUSES`):

| Key | Label | Icon | Color |
|---|---|---|---|
| `booked` | Booked | 📅 | `#04378A` |
| `dispatched` | Agent Dispatched | 🚗 | `#7C3AED` |
| `collected` | Sample Collected | 🧪 | `#16a34a` |
| `processing` | Processing | 🔬 | `#d97706` |
| `report_ready` | Report Ready | 📄 | `#0891b2` |
| `completed` | Completed | ✅ | `#15803d` |
| `no_show` | No Show | ❌ | `#dc2626` |
| `cancelled` | Cancelled | 🚫 | `#94A3B8` |

`TRACKER_FLOW = ['booked','dispatched','collected','processing','report_ready','completed']` is the linear happy-path (`no_show`/`cancelled` are terminal side-exits reachable from any stage, not part of the linear flow).

State lives in Firestore `tracker_states/{bookingId}` — `{ trackerStatus, agentName, updatedAt, timeline: [{status, timestamp, by, note}] }` — live-synced via `onSnapshot` to every signed-in staff member, mirrored to `localStorage.mhl_tracker_states`, and terminal stages (`completed`/`cancelled`/`no_show`) mirror back into `bookings.status`.

Views: **Today, Upcoming (7-day), Pipeline (Kanban by stage), History, All** — plus KPI tiles, search/date/status/test filters, and CSV export. This is **entirely admin-only today** — reached via the admin dashboard's "Booking Tracker" tab, gated behind staff login. **There is no public-facing tracker.**

This flow maps almost 1:1 onto the public tracker sequence requested in the brief — see [BOOKING_FLOW.md §6](BOOKING_FLOW.md) for the exact label mapping and reuse recommendation.

---

## 10. Customer Account Area ("My Account")

Reached via the nav user-dropdown → `openDashboard(page)` → full-screen `#pdOverlay` with a left sidebar (`pd-nav`) and 4 tabs: **Overview, My Profile, My Bookings, My Reports, My Payments**. Data is read client-side from `localStorage` (`mhl_appointments` filtered by the logged-in email, `mhl_reports[email]`, `mhl_prof_<uid>`) — it does **not** currently run its own scoped Firestore query; it relies on whatever the shared booking/report caches already hold in that browser. This is functionally adequate for a single-device demo but is a real gap for a patient who books on one device and checks status on another — worth deciding whether the new "My Bookings"/"My Reports" pages should upgrade to a direct Firestore query by patient email/uid.

This overlay is the direct ancestor of the requested standalone "My Bookings" / "My Reports" pages and should be preserved functionally, just re-hosted as real pages.

---

## 11. Admin Dashboard — Page Inventory

Confirmed via section comments in the markup (RBAC-gated nav, `data-roles` attributes per item):

Dashboard · Analytics · Date-wise Analytics · User Management · Team Management (staff CRUD) · Booking Management · Report Management (Cloudinary upload) · Payment Management · Test Management · Package Management · Coupons · Settings (incl. Cloudinary config, admin emails, Claude API key) · AI Insights · Activity Log · Cash Flow (Income / Expense / Ad Spend sub-tabs, own modals) · **Booking Tracker**.

Plus supporting modals: Create/Edit Staff, Transfer Collection Agent, Booking Edit, WhatsApp Manual Booking, Received Amount, Missing Payment Data, Global Admin Search.

A separate mobile bottom nav exists for the admin dashboard specifically (`ADMIN MOBILE BOTTOM NAV`), independent of the public site's mobile hamburger.

**This system is large, functional, and out of scope for the redesign's first phases** — see "must not break" list in [BACKEND_DEPENDENCIES.md](BACKEND_DEPENDENCIES.md).

---

## 12. RBAC & Security Model

Three staff roles, stored in Firestore `staff_users/{uid}`: **`main_admin`**, **`sub_admin`**, **`collection_agent`**.

- Exactly **two hardcoded "Head Admin" owner emails** can ever self-bootstrap as `main_admin` (only if no `staff_users` doc exists yet for their uid): `workwithme.digital@gmail.com` and `thisisamansaini@gmail.com`. These are a plain JS constant (`MHL_OWNER_EMAILS`), not editable from any UI, and are stated in comments to be mirrored exactly in Firestore Security Rules.
- A permanent, immutable lock document (`system_meta/main_admins/locked/{uid}`) is created the first time each Head Admin logs in; rules are said to treat *that* uid as Main Admin from then on — a server-enforced guarantee, not just a client convention.
- **Booking/report/staff visibility is scoped by role**: `main_admin` sees everything; `sub_admin` sees rows where `parentSubAdminId == uid`; `collection_agent` sees rows where `createdByUserId == uid`. This scoping is applied consistently to Firestore queries *and* as a client-side safety net over the shared `localStorage` cache (`_scopeBookingsToCurrentRole`, `_isBookingIdInMyScope`).
- The code comments document a **real, previously-shipped privilege-escalation bug** (an attacker could set `localStorage.mhl_admin_emails` and self-promote to admin) that was found and fixed by moving the source of truth to Firestore + hardcoded owner emails + rules enforcement. This is a strong signal the backend has already been through a genuine security-hardening pass — **do not regress it**.
- A legacy `mhl_admin_emails` localStorage list (`_isAdminEmail`) still exists as a bootstrap failsafe only, explicitly **not** the source of truth anymore.

**⚠️ Finding:** `firestore.rules` — referenced by name **29 times** in code comments as "the real backstop" — **is not present in this repository**. It is deployed directly to the Firebase project outside of version control. See [BACKEND_DEPENDENCIES.md](BACKEND_DEPENDENCIES.md) for the recommendation to pull it into the repo.

---

## 13. Data Model — Firestore Collections Found

See [BACKEND_DEPENDENCIES.md](BACKEND_DEPENDENCIES.md) for the full schema table. Collections in active use: `bookings`, `config` (singleton docs: `packages`, `tests`, `coupons`, `admins`), `staff_users`, `system_meta/main_admins/locked/{uid}`, `tracker_states`, `cashflow_income`, `cashflow_expense`, `cashflow_ads`, `download_logs`, `users`, `reports`.

---

## 14. `localStorage` Inventory

**29 distinct keys** are read/written across the file (full list in [BACKEND_DEPENDENCIES.md](BACKEND_DEPENDENCIES.md)), the heaviest being `mhl_appointments` (the shared booking cache, read/written in 60+ places). Firestore is the source of truth wherever both exist; `localStorage` functions as an optimistic local cache/offline buffer, explicitly merged with Firestore snapshots on every listener tick (see `_startBookingsListener`, module script line ~247).

---

## 15. Notable Integration Details

### 15.1 Firebase Storage — legacy fallback only
`getStorage`/`storageRef`/`uploadBytesResumable`/`getDownloadURL` are imported and initialized, but the only call site (`handleReportDownload`, ~line 9,691) uses Storage exclusively to **refresh an expired download token for old `firebasestorage.googleapis.com` URLs** — i.e., reports uploaded before Cloudinary became the primary file host. New uploads go through Cloudinary only (`adminUploadReportCloudinary`, cloud name `dm8jiomy3`, unsigned preset `metro_reports`, `resource_type: raw`, folder `metro_reports/<sanitized-email>`).

### 15.2 Razorpay — present but disabled
```js
const RAZORPAY_KEY_ID  = 'rzp_test_XXXXXXXXXXXXXXXX'; // placeholder
const RAZORPAY_ENABLED = false;
```
Both booking pathways check this flag and silently fall back to "Pay Later" / cash-on-collection when it's off. **Online payment is not currently live in production.** Enabling it is purely a config change (real key + `true`), not a code change — but the same Razorpay-open logic is duplicated between Pathway A and Pathway B (see [BACKEND_DEPENDENCIES.md](BACKEND_DEPENDENCIES.md)).

### 15.3 Other embedded config (already public in shipped client code, not new secrets)
- Google Sheets Apps Script webhook URL — every booking POSTed here as a backup log (fire-and-forget, `mode: 'no-cors'`).
- WhatsApp admin number `917428456590` used both for the on-page `wa.me` links and as the target of the auto-generated new-booking WhatsApp message.
- GA4 measurement ID `G-SEPVHXBRQP` (matches Firebase's `measurementId`).

---

## 16. Known Gaps, Placeholders & Discrepancies

1. **Referenced-but-missing files**: `/manifest.json`, `/icons/mstile-150x150.png`, `/browserconfig.xml`, `robots.txt`/`sitemap.xml` (implied by SEO tags) are linked from `<head>` but do not exist anywhere in this repository. Either they live only on the production server (never committed) or the PWA/tile features are currently broken. **Needs verification with whoever manages hosting/deploys.**
2. **`firestore.rules` not in repo** (§12) — the actual enforced security rules cannot currently be reviewed or version-controlled from this codebase.
3. **Favicons/logo embedded as base64** directly in HTML (several 6.5–17 KB base64 blobs inline) rather than as linked files — inflates page weight and prevents independent browser caching of those images across page loads. Worth extracting to real files during the redesign regardless of the multi-page work.
4. **Two parallel booking code paths** (Pathway A/B) with duplicated validation and duplicated Razorpay logic — a maintenance risk independent of this redesign.
5. **Claude API key stored in plaintext in `localStorage`** (`mhl_claude_api_key`) and called directly from the browser for the admin "AI Insights" feature. Functionally fine for a single-admin convenience feature, but worth flagging as a security consideration for later — **out of scope to fix in this redesign**.
6. **Patient "My Account" reads only `localStorage`**, not a live per-user Firestore query (§10) — works on one device/browser, not guaranteed cross-device.
7. **No public booking-status lookup exists at all** — confirmed absence, not just "unpolished."
8. Razorpay is not actually live (test key, disabled) — any UI copy implying "pay online now works" should be treated as aspirational, not currently true in production.

---

## 17. What Already Works Well (preserve, don't rebuild)

- The Firestore data model and its real-time listener pattern.
- The RBAC role/ownership-scoping model and its security-hardening history.
- The Booking Tracker's status vocabulary, timeline design, and live-sync mechanism.
- The visual design tokens (colors, font pairing, dark mode).
- The Cloudinary report-upload pipeline.
- The toast notification system and modal open/close/focus-trap utilities (reusable across new pages).
- The Head-Admin lock mechanism — a genuinely good piece of security design worth keeping exactly as-is.

---

## 18. Files Analyzed

`index-1.html` — read in full (all 14,319 lines, via structural grep pass + full-content reads of every functionally significant section: Firebase/RBAC init, nav, auth modals, both booking pathways, patient dashboard, booking tracker constants + full render/update logic, RBAC helper functions, Cloudinary upload, package/test admin CRUD, and all third-party config constants). Git metadata (`git status`, `git remote -v`, `git branch`, `git ls-remote`, `git log`) inspected directly. Supabase project list/tables/migrations/extensions inspected read-only (see [SUPABASE_MIGRATION_PLAN.md](SUPABASE_MIGRATION_PLAN.md) §1).
