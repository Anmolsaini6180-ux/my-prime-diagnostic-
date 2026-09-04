# UI_PLAN.md — Visual & UX Direction

Companion to [AUDIT.md §5](AUDIT.md) (existing design system) and [ARCHITECTURE_PLAN.md](ARCHITECTURE_PLAN.md) (page structure). This document is direction, not implementation — no CSS/HTML has been written yet.

---

## 1. Existing Design System to Keep

Per AUDIT.md §5, the current site already has a genuinely premium foundation. **Reuse, don't replace:**

- **Color tokens**: `--blue #04378A` (primary), `--orange #F16C0F` (accent), plus the full light/dark pairs already defined in `:root`.
- **Type pairing**: `Clash Display` (headings) + `Sora` (body) — a real premium pairing, keep exactly as-is.
- **Working dark mode** via `data-theme` attribute — carry it to every new page from day one, not bolted on later.
- **Admin's separate SaaS-dark palette** (`--a-*` tokens) stays scoped to the admin dashboard only; new public pages never use it.

---

## 2. Design Principles → Concrete Rules

Translating "premium, professional, modern, medical, trustworthy, clean, responsive" into checkable rules for every new page:

| Principle | Concrete rule |
|---|---|
| Premium / Clean | Generous whitespace: minimum 24px section padding on mobile, 64px+ on desktop. Never more than 2 accent colors (blue + orange) visible in one viewport. |
| Professional / Medical / Trustworthy | Every page that collects or shows patient data displays a trust cue (NABL-certified badge, security/lock icon, or "Verified" mark) — reusing copy already present in the existing JSON-LD/hero ("NABL-certified"). |
| Modern | Cards use soft shadows + large border-radius (matches existing `.package-card`/`.pd-card` conventions) — not flat/skeuomorphic, not glassmorphism/gradients-everywhere. |
| Responsive | Every new page is designed mobile-first and verified at 375px, 768px, and 1280px+ before being called done. |

---

## 3. Explicit Anti-Patterns (mirrors the brief's "avoid" list)

| Avoid | How this plan avoids it |
|---|---|
| Overcrowding | Homepage sections are single-purpose (§5) — no section does more than one job. Booking is 5 focused pages, not 1 crowded form. |
| Huge forms | Booking wizard: max **4 fields per page** (see [BOOKING_FLOW.md](BOOKING_FLOW.md) §3.1). |
| Cheap gradients | Gradients limited to the existing hero treatment and status-timeline dots (already in the codebase); no new decorative gradients introduced. |
| Too many colors | Two-accent rule (above). Package/test cards use one badge color, not a rainbow of category tags. |
| Excessive animations | Reuse the existing `.reveal`/`transition: var(--transition)` conventions only; no new scroll-jacking, parallax, or auto-playing carousels. |
| Single-page everything | The entire point of this redesign — real URLs per [ARCHITECTURE_PLAN.md §4](ARCHITECTURE_PLAN.md). |
| Overly dense cards | Package/test cards cap visible content (the existing `MAX_VISIBLE = 6` features-then-"+N more" pattern in `renderWebsitePackages` already does this well — carry it forward unchanged). |

---

## 4. Navigation

**Desktop nav** (per the brief, replacing today's anchor-only nav — see AUDIT.md §6):
```
[Logo]   Home   Tests   Packages   About Us   Contact   Track Booking   |   Login   [Book a Test]
```
"Book a Test" is the one filled/primary button (orange or blue solid); everything else is a plain text link; "Track Booking" and "Login" are secondary-weight. Cart and dark-mode toggle can be kept as icon buttons at the far right, consistent with today.

**Mobile**: a real hamburger drawer (not the current collapsed-anchor-list pattern) — full-height slide-in panel listing the same items in the same order, plus the logged-in-state user menu when applicable. Reuse the existing `.hamburger`/`#mobileNav` open/close JS pattern (it already exists and works) rather than writing a new drawer component.

---

## 5. Homepage Section List

Per the brief, the homepage stays **focused** — no booking system embedded. Sections, in order:

1. **Hero** — value prop + primary CTA ("Book a Test" → Tests/Packages, not a form).
2. **Trust Indicators** — NABL certification, years in operation, reports-in-24h, ratings (JSON-LD already claims 4.8★/1,240 reviews — surface this visually).
3. **Popular Packages** — 3–4 cards max (reuse `renderWebsitePackages`'s existing card design + "View All" pattern), each linking to `package-detail.html`, not opening a modal.
4. **Popular Tests** — same pattern, linking to `test-detail.html`.
5. **Why Choose Us** — existing section content, kept.
6. **Home Sample Collection** — existing value prop, promoted to its own section per the brief (today it's folded into other copy) — this is the lab's stated core differentiator and deserves visual weight.
7. **How It Works** — a simple 3–4 step visual (Book → Sample Collected → Report Ready → Download) that also **previews the tracker stages**, priming users for Track Booking.
8. **Existing supported info** — Testimonials and the Report Portal teaser (both exist today and are worth a condensed homepage mention linking to their full pages) — carry forward, don't invent new content.
9. **Final CTA** — repeat of "Book a Test."
10. **Footer** — existing content/links, extended with the new page URLs.

**Explicitly removed from the homepage**: the Package Detail Modal, the cart-based booking form, and the Login/Signup modals as homepage-embedded elements — these become their own pages/flows, linked to rather than layered on top of the homepage.

---

## 6. Page-by-Page UI Notes

| Page | Key UI notes |
|---|---|
| **Tests** | Grid of test cards (icon, name, price, category filter) — same visual language as `renderTestGrid`, minus the admin edit affordances. |
| **Test Detail** | Full description, sample type, prep instructions, price, single "Book This Test" CTA → wizard. New content type (today only a small modal exists — `openTestModal`); copy will need to be written per test, flagged as a content task, not a design one. |
| **Packages** | Same grid pattern as Tests; "Most Popular" badge treatment already exists, keep it. |
| **Package Detail** | This is today's `#pkgModal` Step 1, promoted to a full page — tests-included list, sample type/report time/prep-required meta row, price, "Book This Package" CTA. |
| **About / Contact** | Existing section content, promoted to standalone pages with the existing Google Map embed on Contact. |
| **Booking wizard (5 steps)** | Shared layout: a **step progress indicator** at the top (Details → Address → Schedule → Review → Confirm), the **compact package summary** rail (per BOOKING_FLOW.md §3, sticky on desktop, collapsible on mobile), and a persistent "Back"/"Continue" footer bar. |
| **Booking Confirmation** | The one page in this plan that should feel the most celebratory/premium: large checkmark, Booking ID in a copyable/shareable format, full summary card, a clear "Track This Booking" primary CTA, and a secondary "Book Another Test" link. |
| **Track Booking** | Two states: (1) a lookup form (Booking ID + phone) for anonymous visitors, (2) the vertical progress view once a booking resolves (per BOOKING_FLOW.md §6.3), using the same stage colors/icons as the admin tracker for visual consistency. |
| **Login** | Consolidate the existing Login/Signup/OTP modals into tabs on one page rather than three separate modals — same fields, same Firebase calls, just page-hosted. |
| **My Bookings / My Reports** | Same table/card layouts as the existing `pd-bookings`/`pd-reports` tabs (AUDIT.md §10) — no visual redesign needed here, just re-hosting as pages with their own URLs. |

---

## 7. Componentization (build once, reuse everywhere)

- **Package/Test card** — one component, used on Home, Tests/Packages listings, and search results.
- **Step progress indicator** — used across all 5 booking-wizard pages.
- **Compact package summary rail** — used across all 5 booking-wizard pages (see BOOKING_FLOW.md §3).
- **Status timeline / progress tracker** — one visual component shared by Track Booking (public) and the admin Booking Tracker's detail modal, driven by the shared `tracker-shared.js` label map (ARCHITECTURE_PLAN.md §8) so they can never visually diverge.
- **Toast system** — reuse existing `toast()` unchanged.
- **Modal system** — kept for the things that should stay modals (e.g., a quick login prompt triggered mid-flow), reusing the existing open/close/focus-trap utilities rather than a new library.

---

## 8. Responsive & Accessibility Notes

- Verify every new page at 375px (mobile), 768px (tablet), 1280px+ (desktop) before sign-off, per §2.
- Preserve the existing focus-trap and `Escape`-to-close behavior already implemented for `#pkgModal` (`_pkgModalKeyHandler`) for any new modal usage.
- Booking wizard "Continue" buttons must be disabled (not just visually, but actually non-submitting) until the current step's required fields validate — same validation functions as today (`validateMbkField`-equivalent per field), just invoked per-page instead of all at once.

---

## 9. Asset Hygiene (carried from AUDIT.md §16.3)

Extract the embedded base64 favicons/logo images (currently 6.5–17 KB each, inline in HTML) into real files under `assets/img/`. This is good practice regardless of the multi-page work and directly benefits every new page (shared, cacheable assets instead of a repeated inline blob per page).
