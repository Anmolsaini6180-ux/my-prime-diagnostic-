# BOOKING_FLOW.md — Booking & Tracker: As-Is and Implemented

Companion to [AUDIT.md](AUDIT.md) §7/§9 and [ARCHITECTURE_PLAN.md](ARCHITECTURE_PLAN.md) §6. This document is the detailed field-level reference for the booking experience.

> **Status: the multi-step wizard described in §3, and the Track Booking design in §6, are now built, tested, and live against Supabase** — see [BOOKING_IMPLEMENTATION.md](BOOKING_IMPLEMENTATION.md) for what was actually verified. §1-2 below remain as the historical record of the *original Firebase app's* flow (still running, untouched, in `index-1.html`); §3-8 have been updated from "proposed" to "as-built" where the design was carried through unchanged, with actual deviations called out explicitly.
>
> **Superseding update**: the new (Supabase-backed) wizard now requires login before a booking can be created — a deliberate change from the "guest bookings are real" position in §6.2 below, made explicit for this phase and enforced at both the RPC level (`create_booking()` rejects a null session outright) and the UI level (the wizard's entry point redirects to Login, preserving the draft, and returns the visitor to exactly where they left off). See [SECURITY.md §2.3](SECURITY.md) for the fix and its live verification. This does **not** apply to admin-created bookings (Admin Add Booking / WhatsApp Booking) — staff are always authenticated as themselves and book *on behalf of* a patient who may have no account at all, which is a different, still-supported case (see ADMIN_MIGRATION_MAP.md §3).

---

## 1. Current Booking Flow — As-Is

### 1.1 Pathway A: Package Modal (primary — `openPkgModal` → `handleModalBooking`, index-1.html:11,405–11,806)

```
Package card "View Details & Book"
   → #pkgModal opens, Step 1 (read-only package detail: name, price, badge, tests/features list, sample type, report time, prep-required)
   → "BOOK THIS TEST" → Step 2 (single form, all fields below)
   → "Confirm Appointment" → validation → [Razorpay if online] → Firestore write → Step 3 (success screen)
```

**Step 2 fields (all in one screen today):**

| Field | id | Required | Validation |
|---|---|---|---|
| Full Name | `mbkName` | ✅ | ≥2 chars, letters/spaces only |
| Mobile Number | `mbkPhone` | ✅ | `^[6-9]\d{9}$` |
| Email Address | `mbkEmail` | ✅ | basic email regex |
| Date of Birth | `mbkDob` | optional | — |
| Address | `mbkAddress` | optional | free text, labeled "for home collection" |
| Pin Code | `mbkPincode` | ✅ | 6 digits |
| City / Area | `mbkCity` | optional | free text |
| Preferred Date | `mbkDate` | ✅ | non-empty; min=today, max=today+30 |
| Preferred Time Slot | `mbkSlot` | ✅ | one of 8 fixed slots, 7 AM–5 PM (skips 12–2 PM) |
| Special Notes | `mbkNotes` | optional | free text |
| Payment Method | radio-card: `payCardLater` / `payCardNow` | ✅ | "Pay Later" (offline/cash-on-collection) or "Pay Online" (Razorpay) |

There is **no explicit "collection type" choice** — every booking through this pathway is implicitly Home Sample Collection (hardcoded string `'Home Sample Collection'` in the booking object).

**Booking object written to Firestore `bookings/{bookingId}`** (bookingId = `'MPD-' + Date.now()`):
```
bookingId, packageId, packageName, packagePrice, userName, userMobile, userEmail, userDob,
userAddress, userPincode, userCity, scheduledDate, scheduledTimeSlot, specialNotes,
paymentMode ('online'|'offline'), paymentStatus ('pending'|'paid'|'failed'),
razorpayOrderId, razorpayPaymentId, status ('pending'|'confirmed'|'failed'|'cancelled'|'completed'),
source ('web'), createdAt, updatedAt, _savedAt,
// legacy/admin-compatibility mirror fields:
id, name, phone, email, date, slot, test, collection, area, address, pincode, amount, discount, coupon,
submittedAt, submittedAtDisplay, userId,
// RBAC ownership (via attachBookingOwnership):
createdByUserId, creatorRole, createdByName, parentSubAdminId, assignedCollectionAgentId, branchId, cityId, sampleStatus
```

### 1.2 Pathway B: Cart Checkout (`handleBooking`, index-1.html:4,810–4,988)

Add one or more tests/packages to cart → "Proceed to Booking" → scrolls to a form with: name, phone, email, date, slot, area, pin, test (dropdown, combined if from cart), **collection type** (`bkCollection` — a real dropdown, unlike Pathway A), address, **coupon code** (`bkCoupon`, validated against `lookupCoupon()`). Same validation rules as Pathway A for name/phone/pin, plus a past-date check. Produces the same booking shape (slightly different field set — no `userDob`, has `coupon`/`discount`).

**Coupon shape** (Firestore `config/coupons`, doc `{ items: [...] }`): `{ code, type: 'percent'|'flat', value, active, expires? }`.

### 1.3 Which pathway to build the new flow on

**Recommendation: base the new multi-page wizard on Pathway A** (package-first, single-item) — it matches the brief's explicit desired flow ("Customer clicks Book Now on a package → Patient Details → Address → Date & Time → Review → Confirm") field-for-field. Pathway B's two extra concerns (multi-item cart, coupon code) are real and shouldn't be dropped, but are a **separate product decision**: either (a) fold "coupon code" into the new Review step for every booking regardless of source, and treat "cart of multiple tests" as a later enhancement of the same wizard, or (b) keep Pathway B as a legacy/secondary flow untouched for now. **This choice is flagged as open, not decided here** — recommend confirming with the business owner before Phase 3 of the architecture plan.

---

## 2. Current Booking Tracker — As-Is

Full detail in [AUDIT.md](AUDIT.md) §9. Summary of the machinery being reused:

- **Status vocabulary** (`TRACKER_STATUSES`, index-1.html:13,453): `booked → dispatched → collected → processing → report_ready → completed`, with `cancelled`/`no_show` as terminal side-exits.
- **State store**: Firestore `tracker_states/{bookingId}` = `{ trackerStatus, agentName, updatedAt, timeline: [{status, timestamp, by, note}] }`, live-synced (`onSnapshot`) to staff, mirrored to `localStorage.mhl_tracker_states`.
- **Inference rule** (`_getTS`): if no tracker state exists yet, effective status is derived from `booking.status` (`cancelled`→`cancelled`, `completed`→`completed`, else `booked`) — meaning a public tracker page can render a sensible status **even for a booking whose staff never touched the tracker yet**.
- Terminal stages mirror back into `bookings.status` (`_mirrorBookingStatus`).

This is admin-only today (no public read path exists) — the only new mechanism needed is a way for a patient to *look up* this same data. No changes to how staff *write* tracker updates.

---

## 3. Proposed New Multi-Page Booking Flow

```
Package/Test card → [Book Now]
        │
        ▼
┌─────────────────────────────┐
│ package-detail.html          │  full detail page (was Step 1 of the modal)
│ [Book This Package] ─────────┼──► writes {packageId, packageName, packagePrice} to the draft
└─────────────────────────────┘
        ▼
┌─────────────────────────────┐
│ booking/patient-details.html │  Name*, Mobile*, Email*, DOB
└─────────────────────────────┘        ▲
        ▼                              │  compact package summary
┌─────────────────────────────┐        │  ("📦 {name} — ₹{price}  [Change]")
│ booking/address.html         │  Collection type (Home/Lab), Address, Pincode*, City   │  stays visible/sticky
└─────────────────────────────┘        │  on every one of these
        ▼                              │  five pages — see
┌─────────────────────────────┐        │  ARCHITECTURE_PLAN.md §6
│ booking/schedule.html        │  Preferred Date*, Time Slot*                            │
└─────────────────────────────┘        │
        ▼                              │
┌─────────────────────────────┐        │
│ booking/review.html          │  read-only summary of everything above + payment choice │
│ [Confirm Booking] ────────────┼──► same Firestore write logic as today's                │
└─────────────────────────────┘     handleModalBooking (Razorpay if online → setDoc)      ▼
        ▼
┌─────────────────────────────┐
│ booking/confirmation.html     │  Booking ID + full summary — the "beautiful" page the brief asks for
│ [Track This Booking] ─────────┼──► pages/track-booking.html?id=<bookingId>
└─────────────────────────────┘
```

### 3.1 Field-to-step mapping (old form → new pages)

| New page | Fields (same `id`/names as today, carried in the draft) |
|---|---|
| Patient Details | `userName`, `userMobile`, `userEmail`, `userDob` |
| Address | *(new)* `collectionType` ('home'\|'lab'), `userAddress`, `userPincode`, `userCity` |
| Schedule | `scheduledDate`, `scheduledTimeSlot` |
| Review | Read-only recap of all of the above, editable via "Change" links back to each step; `specialNotes` (optional, can live here instead of its own step); payment method choice (`paymentMode`) |
| Confirm → Confirmation | Triggers the existing write logic; displays `bookingId`, package, date/slot, address summary, payment status — same content `_showSuccessScreen` already assembles today, just as a full page instead of a modal panel |

No field is renamed. This is deliberate: **the admin Booking Management table, Booking Tracker, Cash Flow auto-sync, and CSV exports all key off these exact field names today and must keep working unmodified.**

### 3.2 Collection Type — new field, needs a product decision

Today's Pathway A hardcodes "Home Sample Collection." The brief's flow diagram says "Address / Collection Type," implying a real choice should exist. Recommendation: add a simple two-option choice (Home Collection / Visit Lab) on the Address page, **defaulting to Home Collection** (matches the brand's stated strength — "Free home sample collection" appears in the hero, JSON-LD schema, and meta description). If the business does not actually operate a walk-in lab-visit option, this should collapse to Home-Collection-only — **confirm with the business owner before building the Address page.**

---

## 4. Data Persistence Across Steps

See [ARCHITECTURE_PLAN.md §6](ARCHITECTURE_PLAN.md) for the mechanism (`sessionStorage` draft object, same field names as the final Firestore doc). Key rules:
- The draft is created the moment a package/test is selected and is never valid across a browser restart (by design — `sessionStorage`).
- Each step page both **reads** the draft on load (so back/forward and page-refresh mid-flow don't lose data) and **writes** its own fields on "Continue."
- The Review page never re-collects data — it only reads the draft and renders it, with "Change" links back to the specific step.
- On successful submit, the draft is cleared and the booking is looked up by ID from then on (not from the draft) — refreshing the Confirmation page must never re-submit.

---

## 5. Reconciling the Two Existing Pathways

Not resolved in this document — flagged explicitly as a decision for the business owner before Phase 3 of the architecture plan:

- **Option A**: New wizard fully replaces Pathway A. Pathway B (cart/multi-item + coupons) stays exactly as-is, reachable from wherever "Add to Cart" currently lives, as a secondary/legacy flow, until a future phase folds coupon support into the new wizard.
- **Option B**: New wizard absorbs coupon-code support at the Review step from day one (small addition — `lookupCoupon()` already exists and is pure/reusable), and the cart/multi-item path is deprecated once the wizard supports adding more than one package to a single booking.

Recommendation leans **Option A** for Phase 1 (smaller, lower-risk, matches the brief's package-first flow exactly) with coupon support added to Review as a fast-follow — but this is the business owner's call, not a technical one.

---

## 6. Public Track Booking — Design

### 6.1 Status label mapping (reusing the existing machinery, per the brief's explicit instruction to preserve/reuse tracker logic)

| Internal key (unchanged) | Admin label (unchanged) | Public-facing label (new, customer-friendly) |
|---|---|---|
| `booked` | Booked | **Booking Confirmed** |
| `dispatched` | Agent Dispatched | **Agent Assigned** |
| `collected` | Sample Collected | **Sample Collection** |
| `processing` | Processing | **Sample Received / Processing** |
| `report_ready` | Report Ready | **Report Ready** |
| `completed` | Completed | **Completed** |
| `cancelled` / `no_show` | Cancelled / No Show | **Booking Cancelled** (shown as a distinct end-state, not a step in the happy-path progress bar) |

This is a 1:1 relabeling — **no new statuses, no changed flow order, no changes to how staff move a booking through stages.** `assets/js/tracker-shared.js` (per ARCHITECTURE_PLAN.md §8) holds exactly this mapping table so the public page and the admin page can never drift out of sync on wording.

### 6.2 Lookup mechanism — decided and built

**Decision made: Booking Code + the exact phone number used at booking time**, verified inside a `SECURITY DEFINER` Postgres RPC (`track_booking()` / `track_booking_timeline()` — option (1) from the original three-way tradeoff below, minus needing a *separate* Edge Function, since a Postgres RPC gives the same "server checks both fields, returns only a safe payload" guarantee natively). A wrong phone against a real code returns the same empty result as a wrong code — the two failure modes are indistinguishable, so a partial guess can't be narrowed down. Verified live: a real booking code with an incorrect phone returns nothing; the correct phone returns the real status. Full detail in [BOOKING_IMPLEMENTATION.md §5](BOOKING_IMPLEMENTATION.md).

The three options originally weighed (kept here for context on why option 1's *spirit* won even though the implementation isn't a Cloud/Edge Function specifically):
1. ~~A small serverless function~~ → became a Postgres RPC instead — same security property, no separate deployable.
2. A narrow rules-based `get` with a companion doc — not needed; RLS plus a `SECURITY DEFINER` function covers this natively in Postgres.
3. Require login — rejected as the primary path (guest bookings are real, per AUDIT.md), but implemented as a *bonus* fast path: a logged-in patient viewing their own booking from My Bookings skips straight to a real-time RLS-gated view, no phone re-entry needed.

### 6.3 What the Track Booking page shows — built

A vertical progress indicator on mobile, horizontal on desktop (CSS breakpoint at 768px, same component for both), current stage highlighted, past stages checked off with timestamps, using the shared color/icon values from `assets/js/tracker-shared.js` — reused, not reinvented, so a future admin-side tracker UI can consume the exact same module and never drift on wording from the public page.

---

## 7. Booking ID Format — decided differently than originally recommended, deliberately

Phase 0 recommended **keeping** `MPD-<timestamp>` for continuity. That recommendation was **not followed** once the Supabase schema was actually built, for a concrete reason found during implementation: the timestamp scheme is sequential and guessable, and the new public Track Booking page makes that a live exposure it wasn't before (nothing public could look up a booking by ID in the old Firebase app at all). The new scheme — `MPD-` + 6 random characters from a 31-symbol alphabet (`generate_booking_code()`, DATABASE.md §3) — keeps the same visual format and the same "easy for a customer to read over the phone" property, while removing the guessability. This only affects **new** bookings created against the Supabase schema; nothing about the existing Firebase `MPD-<timestamp>` IDs already issued needs to change, since that system is untouched.

---

## 8. What Must Not Change

**Regarding `index-1.html` (unchanged, still running)**:
- The `bookings` Firestore document shape and field names (§1.1) — the admin Booking Management, Booking Tracker, Cash Flow auto-sync, and CSV export all depend on these exact names today.
- `attachBookingOwnership()` must still run on every new booking there, unchanged, so RBAC scoping keeps working.
- The `TRACKER_STATUSES`/`TRACKER_FLOW` values and `tracker_states` document shape.
- Razorpay/Cloudinary/EmailJS/WhatsApp/Google-Sheets call sites there — untouched.

**Regarding the new Supabase-backed booking system (built in Phase 2)** — see [BOOKING_IMPLEMENTATION.md](BOOKING_IMPLEMENTATION.md) and [DATABASE.md](DATABASE.md) for the authoritative, current reference: the `bookings`/`booking_items`/`collection_addresses`/`booking_status_history` schema, the `status`+`stage` dual-column model (deliberately mirroring the original's status/tracker-status split), and the RPC-only write path are now the source of truth for anything built against Supabase going forward, and should not be casually altered without updating the RLS policies and the wizard pages that depend on the exact field names.
