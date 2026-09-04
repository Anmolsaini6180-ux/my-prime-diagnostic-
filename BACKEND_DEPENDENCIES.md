# BACKEND_DEPENDENCIES.md — Full Backend & Integration Inventory

This is the reference document for "what must not break." Every fact below was confirmed by reading the actual code in `index-1.html` (line numbers given), not inferred. See [AUDIT.md](AUDIT.md) for narrative context.

---

## 1. Firebase Project

| Field | Value |
|---|---|
| SDK | Firebase JS SDK **v10.12.0**, modular, loaded via `<script type="module">` from `gstatic.com` (no npm) — index-1.html:112–116 |
| `projectId` | `metrohealthlab-c864d` |
| `authDomain` | `metrohealthlab-c864d.firebaseapp.com` |
| `storageBucket` | `metrohealthlab-c864d.firebasestorage.app` |
| `measurementId` | `G-SEPVHXBRQP` (same ID used directly for the separate `gtag.js` GA4 snippet) |
| Services actually used | **Auth**, **Firestore** (primary), **Storage** (legacy fallback only — see §3) |
| Config location | index-1.html:124–132, inside the first `<script type="module">` |

The `apiKey`/`appId` values are present in the file (not reproduced here) — they are standard Firebase **web client** config, not secrets; access control is enforced by Firestore Security Rules and Firebase Auth, not by hiding this config.

---

## 2. Firestore — Collections & Schema

| Collection / doc path | Shape (key fields) | Written by | Read by | Notes |
|---|---|---|---|---|
| `bookings/{bookingId}` | See [BOOKING_FLOW.md §1.1](BOOKING_FLOW.md) for full field list | Both booking pathways (public/patient); staff edit modals; tracker mirror | Admin Booking Management, Booking Tracker, Cash Flow, patient's own bookings (via localStorage cache today) | `bookingId` = `MPD-<Date.now()>`. RBAC-scoped reads via `parentSubAdminId`/`createdByUserId` |
| `config/packages` | `{ items: [...], updatedAt }` | Admin Package Management (`_saveFirestorePackages`) | Public listener (`_startPkgListener`) — broadcast to **every visitor**, no auth required | Package object shape: `{ id?, name, desc, price, originalPrice?, badge?, features: [string]` (legacy) `\| tests: [{fullName/name, code, count}]` (current), `sampleType?, reportTime?, preparationRequired?, emoji?, featured? }` |
| `config/tests` | `{ items: [...], updatedAt }` | Admin Test Management (`_saveFirestoreTests`) | Public listener (`_startTestsListener`) — same broadcast pattern | Test object shape: `{ name, cat, price, icon, section }` |
| `config/coupons` | `{ items: [...], updatedAt }` | Admin Coupons page (`_saveFirestoreCoupons`) | `_loadFirestoreCoupons`, `lookupCoupon` (cart checkout pathway) | Coupon shape: `{ code, type: 'percent'\|'flat', value, active, expires? }` |
| `config/admins` | `{ emails: [...], updatedAt }` | Admin Settings (`addAdminEmail`/`removeAdminEmail`) | `_fetchFirestoreAdmins` | Legacy bootstrap-failsafe list — **not** the RBAC source of truth (see §12) |
| `staff_users/{uid}` | `{ name, email, phone, role: 'main_admin'\|'sub_admin'\|'collection_agent', status: 'active'\|other, parentSubAdminId, branchId, cityId, permissions, createdBy, createdAt, updatedAt, lastLogin }` | Team Management (create/edit staff), self-bootstrap for Head Admins | `_resolveStaffRole` on every login; Team Management list | Doc ID = Firebase Auth `uid`. Role source of truth. |
| `system_meta/main_admins/locked/{uid}` | `{ uid, email, lockedAt }` | `_ensureMainAdminLock`, once per Head Admin uid, immutable thereafter | Firestore Security Rules (`isMainAdmin()`) | The real, server-enforced Main-Admin guarantee — see §12 |
| `tracker_states/{bookingId}` | `{ trackerStatus, agentName, updatedAt, timeline: [{status, timestamp, by, note}] }` | `updateTrackerStatus` (admin Booking Tracker) | Live listener (`_startTSListener`, staff-only), public Track Booking page (**new**, read-only, needs a rules decision — see [BOOKING_FLOW.md §6.2](BOOKING_FLOW.md)) | Doc ID = the booking's ID, 1:1 |
| `cashflow_income/{id}` | Income ledger row; auto-synced from paid bookings (`_cfAutoSyncBookingToIncome`, doc id `auto_<bookingId>` for auto-rows) | Admin Cash Flow → Income | Admin Cash Flow dashboards | Main-Admin-only feature |
| `cashflow_expense/{id}` | Expense ledger row | Admin Cash Flow → Expense | Admin Cash Flow dashboards | Main-Admin-only feature |
| `cashflow_ads/{id}` | Ad-spend ledger row | Admin Cash Flow → Ads | Admin Cash Flow dashboards, Marketing Efficiency widget | Main-Admin-only feature |
| `download_logs/{auto-id}` | `{ reportId, reportName, patientEmail, pdfUrl, at }` | `trackReportDownload` | Admin (implied, not traced in depth) | Every report download is logged |
| `users/{email}` | Patient/user profile mirror | `saveUserToFirestore` on login | `loadUsersFromFirestore` (admin User Management) | Keyed by email, not uid |
| `reports/{docId}` | `{ name, icon, status, pdfUrl, fileId, phone, parentSubAdminId, ... }` under a per-patient structure | `saveReportToFirestore`, admin report upload | Patient Report Portal, admin Report Management | PDF URL points to Cloudinary (current) or legacy Firebase Storage (old records) |

**None of this schema changes as part of the redesign.** New pages read/write these same collections with these same field names.

---

## 3. Firebase Storage — Legacy Fallback Only

`getStorage`, `storageRef`, `uploadBytesResumable`, `getDownloadURL`, `deleteObject` are imported and initialized (index-1.html:115, 135, 144–147) but the **only actual call site** is `handleReportDownload` (index-1.html:9,691–9,710), which detects a `firebasestorage.googleapis.com` URL on an *old* report record and re-fetches a fresh download token for it (tokens on Storage URLs expire). **All new report uploads go through Cloudinary, not Storage** (see §5). Do not remove the Storage init — old reports still depend on it.

---

## 4. Authentication

| Method | Firebase call | Entry point |
|---|---|---|
| Google | `signInWithPopup` + `GoogleAuthProvider` | `googleAuth()` |
| Email/password login | `signInWithEmailAndPassword` | `emailLogin()` |
| Email/password signup | `createUserWithEmailAndPassword` | `emailSignup()` |
| Password reset | `sendPasswordResetEmail` | `forgotPassword()` |
| Phone/OTP | `RecaptchaVerifier` + `signInWithPhoneNumber` (scaffolded), custom modal (`sendOtp`/`otpNext`/`verifyOtp`) | OTP modal — **wiring not fully traced; smoke-test before relying on it in the new Login page** |
| Session | `onAuthStateChanged` → `window.currentUser`, `window.currentStaffRole`, `window.currentStaffProfile` | Module script, index-1.html:471–500 |
| Staff-account creation | A throwaway **secondary** Firebase app instance (`_createStaffAuthAccount`) so creating a new staff login doesn't sign out the admin creating it | index-1.html:169–181 |

---

## 5. Cloudinary

| Field | Value |
|---|---|
| Cloud name | `dm8jiomy3` (index-1.html:5,038, overridable via Settings → `localStorage.mhl_cloudName`) |
| Upload preset | `metro_reports` (unsigned, index-1.html:5,039, overridable via `mhl_cloudPreset`) |
| Resource type | `raw` (PDFs) |
| Folder scheme | `metro_reports/<email-with-non-alphanumerics-replaced-by-_>` |
| Public ID scheme | `<safeEmail>_<Date.now()>.pdf` |
| Upload endpoint | `https://api.cloudinary.com/v1_1/<cloudName>/raw/upload` (direct `XMLHttpRequest` from the browser, admin-only UI) |
| Used for | **Patient report PDFs only** — nothing else in the app uses Cloudinary |
| Known fix already applied in code | `_ensurePdfUrl`/`_pdfDownloadUrl` append `.pdf` and handle `fl_attachment` because old raw uploads lacked a content-type-implying extension — keep this logic when porting report-download code |

---

## 6. Razorpay

| Field | Value |
|---|---|
| SDK | `checkout.js` via CDN, index-1.html:505 |
| Key | `RAZORPAY_KEY_ID = 'rzp_test_XXXXXXXXXXXXXXXX'` — **placeholder, test mode** |
| Enabled flag | `RAZORPAY_ENABLED = false` — **online payment is currently OFF in production** |
| Call sites | Duplicated between Pathway A (`handleModalBooking`, ~11,684) and Pathway B (`handleBooking`, ~4,881) — same options shape, same handler pattern |
| Behavior when disabled | Both pathways silently fall back to offline/"Pay Later" |
| Behavior on success | Sets `razorpayPaymentId`, `paymentStatus: 'paid'`, `status: 'confirmed'` |
| Behavior on failure/cancel | Booking is still saved (status `failed`) — **no data is lost on a failed payment**, a deliberate existing safeguard, keep it |

Enabling real payments is a **config change** (real key + `true`), not a code change, and is a business decision outside this redesign's scope.

---

## 7. EmailJS

Loaded via `@emailjs/browser@4` CDN (index-1.html:503). Used for: booking-confirmation email (`sendBookingEmail`) and report-ready email (`sendReportReadyEmail`). A `console.warn` fires if the SDK or public key isn't present (index-1.html:3,879) — confirms the app is designed to degrade gracefully if email isn't configured. Both toggled per-booking by admin Settings flags `togEmail`/`togReport` in `localStorage.mhl_settings`.

---

## 8. WhatsApp

**Not the official WhatsApp Business API** — purely `wa.me` deep links opened via `window.open()`. Two distinct uses:
1. **Customer-facing**: "WhatsApp Help" links (static, admin number).
2. **Staff-facing**: `sendToWhatsApp()` auto-opens a pre-filled `wa.me` link to notify the admin's own WhatsApp number of a new booking; the **WhatsApp Manual Booking modal** (index-1.html:11,808+) is a separate staff tool that lets a staff member paste an incoming customer WhatsApp message and auto-parse it into a booking (`parseAndFillBooking`) — this is a data-entry convenience for phone/WhatsApp-originated bookings, not a customer-facing feature.

Admin WhatsApp number: `917428456590` (also the number shown publicly on the site).

---

## 9. Google Sheets (backup log)

Every booking (both pathways) is POSTed, fire-and-forget (`mode: 'no-cors'`, no response read), to a Google Apps Script Web App URL (index-1.html:4,776) as a redundant off-Firestore log. Failure here never blocks a booking (wrapped in try/catch). Purely additive — safe to port unchanged, safe to leave out of a first prototype without affecting Firestore data integrity.

---

## 10. Google Analytics 4

Standard `gtag.js` snippet, measurement ID `G-SEPVHXBRQP` (index-1.html:69–76), plus a JSON-LD `MedicalBusiness` schema block (index-1.html:78–108) for search rich results — claims `ratingValue: 4.8`, `reviewCount: 1240` (unclear if these are live/real or placeholder marketing figures — **worth confirming with the business owner before carrying them onto new pages**, since JSON-LD ratings claims are subject to Google's review-snippet guidelines).

---

## 11. Claude API (AI Insights admin feature)

Admin pastes a Claude API key into Settings; it's stored in `localStorage.mhl_claude_api_key` and called **directly from the browser** to generate a natural-language summary of business data (`initAIPage`, `getClaudeKey`, index-1.html:10,867+). This is a client-side API key exposure pattern — functionally fine for a single-trusted-admin convenience tool, but **flagged as a security consideration for a future hardening pass, explicitly out of scope for this redesign.**

---

## 12. RBAC Model (detail)

- Roles: `main_admin`, `sub_admin`, `collection_agent`, stored in `staff_users/{uid}.role`.
- **Head Admins**: exactly two hardcoded emails (`MHL_OWNER_EMAILS`, index-1.html:344) can self-bootstrap as `main_admin` — only if no `staff_users` doc exists yet for their uid. Not editable from any UI or via `localStorage`.
- **Lock mechanism**: `system_meta/main_admins/locked/{uid}` is created once per Head Admin and is described in comments as immutable via Firestore rules (`allow update, delete: if false`) — the actual server-side enforcement of "only these 2 people, ever" lives in `firestore.rules`, **not in this repo** (see §13).
- **Ownership stamping**: every new booking passes through `attachBookingOwnership()` (index-1.html:12,832), which sets `createdByUserId`, `creatorRole`, `createdByName`, `parentSubAdminId`, `assignedCollectionAgentId`, `branchId`, `cityId`, `sampleStatus` based on who's creating it (staff member vs. anonymous/patient self-booking).
- **Scoping pattern, applied consistently**:
  - Firestore query level: `_bookingsQueryForCurrentRole()` — `main_admin` unfiltered, `sub_admin` filtered by `parentSubAdminId`, `collection_agent` filtered by `createdByUserId`.
  - Client-side safety net over the shared `localStorage` cache: `_scopeBookingsToCurrentRole()`, `_isBookingIdInMyScope()`, `_isEmailInMyScope()`.
  - Permission gates: `_requireRole(allowedRoles, actionLabel)` / `_requireMainAdmin(actionLabel)` — used before every sensitive write (catalog edits, staff changes, cash flow, exports).
- **Documented security history**: a prior bug allowed privilege escalation via an editable `localStorage.mhl_admin_emails` list; comments describe the fix (hardcoded owner emails + Firestore-rule-enforced lock) in detail — a strong signal this system has already had a real security review. **Do not reintroduce a client-trusted admin-email list as a source of truth.**

---

## 13. Firestore Security Rules — Not In This Repository

`firestore.rules` is referenced by name **29 times** across code comments as "the real backstop" for every RBAC and ownership check described above, but **the file itself does not exist anywhere in this repository**. It is deployed directly to the Firebase project (via Console or a CLI setup that isn't checked in). This means:
- The actual enforced rules cannot currently be reviewed, diffed, or version-controlled alongside the application code.
- Any change to the client's assumptions about roles/ownership (e.g., adding a new role, or the new public Track Booking read path in [BOOKING_FLOW.md §6.2](BOOKING_FLOW.md)) requires a **separate, out-of-repo rules deployment** that this codebase cannot verify.

**Recommendation**: pull the currently-deployed rules into the repo as `firestore.rules` (via `firebase firestore:rules:get` if the Firebase CLI is available, or copy-pasted from the Console) as a first, purely-additive, zero-risk step — this makes every future change reviewable and gives a rollback point. Not done as part of this audit (no write access to Firebase assumed/used).

---

## 14. Absolute Must-Not-Break List

1. `bookings` collection field names and shape (multiple admin systems key off exact names).
2. `attachBookingOwnership()` running on every booking creation path.
3. `staff_users` role values (`main_admin`/`sub_admin`/`collection_agent`) and the two hardcoded Head Admin emails.
4. The `system_meta/main_admins/locked/{uid}` mechanism.
5. `config/packages` and `config/tests` singleton-doc + `onSnapshot` broadcast pattern (both admin catalog editing and public display depend on it).
6. `tracker_states` shape and the `TRACKER_STATUSES`/`TRACKER_FLOW` vocabulary.
7. The Cloudinary cloud name/preset and folder/public-ID scheme (existing report URLs must keep resolving).
8. The Firebase Storage legacy-fallback code path (old reports still need it).
9. Any `localStorage` key the admin dashboard reads (full 29-key list identifiable via the codebase's `localStorage.getItem/setItem` call sites; the heaviest are `mhl_appointments`, `mhl_admin_packages`, `mhl_admin_tests`, `mhl_reports`, `mhl_users`, `mhl_settings`, `mhl_tracker_states`, `mhl_coupons`).
10. `firestore.rules` as currently deployed (not in this repo, but must not be assumed changeable without separate, explicit action).
