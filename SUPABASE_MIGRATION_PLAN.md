# SUPABASE_MIGRATION_PLAN.md — Planning Only, Not Executed

> **Status: NOT STARTED. No Supabase resources have been created or modified as part of this task.**
> Per explicit instruction: Firebase remains the sole production backend. This document is a forward-looking plan for a *future, separately-approved* phase — nothing here is scheduled or implied to happen automatically after the current redesign work.

---

## 1. Current Supabase State (checked read-only, 2026-09-04)

Two Supabase projects exist on this account:

| Project | Region | Status | Relevant? |
|---|---|---|---|
| "Anmolsaini6180-ux's Project" (`tnjnbbeqlqhpbfkoebpl`) | ap-northeast-2 | ACTIVE_HEALTHY | No — unrelated default project |
| **"my prime diagnoatics lab"** (`woedykgrzczgogtymfxg`) | ap-south-1 (Mumbai) | ACTIVE_HEALTHY, created 2026-08-29 | **Yes — the designated target for this business** |

Checked on the relevant project (`woedykgrzczgogtymfxg`), all read-only:
- `list_tables` → **0 tables** in `public` schema.
- `list_migrations` → **0 migrations** ever applied.
- `list_extensions` → only Supabase's default bootstrap extensions installed (`pgcrypto`, `uuid-ossp`, `pg_stat_statements`, `plpgsql`, `supabase_vault`) — nothing custom.

**Conclusion: this project is a completely blank slate.** It appears to have been provisioned in anticipation of a future migration but has never been used. No schema, no data, no prior migration attempt. This plan targets that project, but **creates nothing in it.**

---

## 2. Why This Plan Exists Now (and why it isn't executed now)

The user has a Supabase project ready and asked for a migration plan to be documented alongside the front-end redesign audit. The explicit backend rule for this task is: **do not touch Supabase, do not touch Firebase, do not migrate anything yet.** This document exists so that *when* a migration is approved as its own project, there's an accurate, code-grounded starting point — not a generic Firebase→Supabase tutorial.

---

## 3. Firebase → Supabase Concept Mapping

| Firebase concept (current) | Supabase equivalent | Notes |
|---|---|---|
| Firebase Auth (Google, email/password, phone-OTP) | Supabase Auth | Supports the same three methods; UID scheme differs (see §8 risks) |
| Firestore collection/document | Postgres table + row | Requires real schema design — Firestore's schemaless documents (e.g. the `bookings` mega-object with 30+ optional fields) map best to a table with nullable columns, not a 1:1 blind copy |
| `onSnapshot` realtime listener | Supabase Realtime (Postgres logical replication channels) | Conceptually equivalent; subscription API differs |
| Firestore Security Rules | Postgres Row Level Security (RLS) policies | The RBAC scoping logic in [BACKEND_DEPENDENCIES.md §12](BACKEND_DEPENDENCIES.md) translates fairly directly into RLS policies keyed on `auth.uid()` |
| Firebase Storage (legacy fallback) | Supabase Storage | Only relevant for old report files still resolved via Firebase Storage tokens — see AUDIT.md §15.1 |
| `config/packages`, `config/tests`, `config/coupons`, `config/admins` (singleton docs holding an `items` array) | Real tables (`packages`, `tests`, `coupons`) with one row per item, plus an `app_settings` table for admin emails/toggles | This is a **schema improvement**, not just a port — Firestore's "one doc holding a JSON array" pattern was likely a pragmatic choice for `onSnapshot` simplicity, but Postgres tables give real per-row querying/indexing |

---

## 4. Proposed Postgres Schema Sketch (design only — not created)

Column lists are illustrative, drawn directly from the actual fields found in code (see [BACKEND_DEPENDENCIES.md §2](BACKEND_DEPENDENCIES.md)), not guessed:

```sql
-- bookings: mirrors the current Firestore booking object
create table bookings (
  id                 text primary key,          -- keep existing "MPD-<ts>" scheme for continuity
  package_id         text,
  package_name       text,
  package_price      numeric,
  user_name          text,
  user_mobile        text,
  user_email         text,
  user_dob           date,
  user_address       text,
  user_pincode       text,
  user_city          text,
  scheduled_date     date,
  scheduled_time_slot text,
  special_notes      text,
  payment_mode       text,        -- 'online' | 'offline'
  payment_status     text,        -- 'pending' | 'paid' | 'failed' | 'cash'
  razorpay_order_id  text,
  razorpay_payment_id text,
  status             text,        -- 'pending' | 'confirmed' | 'failed' | 'cancelled' | 'completed'
  source             text,        -- 'web' | 'whatsapp'
  created_by_user_id uuid references auth.users(id),
  creator_role       text,
  created_by_name    text,
  parent_sub_admin_id uuid references auth.users(id),
  assigned_collection_agent_id uuid references auth.users(id),
  branch_id          text,
  city_id            text,
  sample_status      text,
  coupon_code        text,
  discount           numeric,
  amount             numeric,
  submitted_at       timestamptz default now(),
  updated_at         timestamptz,
  updated_by         uuid,
  updated_by_name    text
);

-- tracker_states → normalized into two tables (timeline becomes real rows, not a JSON array)
create table tracker_states (
  booking_id   text primary key references bookings(id),
  tracker_status text,
  agent_name   text,
  updated_at   timestamptz
);
create table tracker_timeline (
  id           bigint generated always as identity primary key,
  booking_id   text references bookings(id),
  status       text,
  ts           timestamptz,
  by_name      text,
  note         text
);

create table staff_users (
  id           uuid primary key references auth.users(id),
  name         text, email text, phone text,
  role         text check (role in ('main_admin','sub_admin','collection_agent')),
  status       text default 'active',
  parent_sub_admin_id uuid references auth.users(id),
  branch_id    text, city_id text,
  created_by   text, created_at timestamptz default now(), updated_at timestamptz, last_login timestamptz
);

create table main_admin_locks (          -- replaces system_meta/main_admins/locked/{uid}
  uid uuid primary key references auth.users(id),
  email text, locked_at timestamptz default now()
);

create table packages ( id text primary key, name text, desc text, price numeric, original_price numeric,
  badge text, features jsonb, tests jsonb, sample_type text, report_time text,
  preparation_required boolean, emoji text, featured boolean );

create table tests ( id bigint generated always as identity primary key, name text, cat text, price text, icon text, section text );

create table coupons ( code text primary key, type text check (type in ('percent','flat')), value numeric, active boolean, expires date );

create table app_settings ( key text primary key, value jsonb );   -- replaces config/admins + mhl_settings toggles

create table cashflow_income  ( id text primary key, date date, amount numeric, label text, status text, deleted_at timestamptz, deleted_by uuid /* + fields TBD from full read */ );
create table cashflow_expense ( id text primary key, date date, amount numeric, label text, status text, deleted_at timestamptz, deleted_by uuid );
create table cashflow_ads     ( id text primary key, date date, amount numeric, label text, status text, deleted_at timestamptz, deleted_by uuid );

create table download_logs ( id bigint generated always as identity primary key, report_id text, report_name text, patient_email text, pdf_url text, at timestamptz default now() );
```

**Note**: the Cash Flow tables above are sketched from partial evidence (field names seen in query/sort calls, e.g. `orderBy('date','desc')`) — a full read of the Cash Flow CRUD functions would be needed before finalizing those three tables. Flagged as incomplete-by-design for this planning pass.

---

## 5. RBAC Equivalent — Row Level Security Sketch

Mirroring [BACKEND_DEPENDENCIES.md §12](BACKEND_DEPENDENCIES.md) exactly:

```sql
alter table bookings enable row level security;

create policy "main_admin sees all" on bookings for select
  using (exists (select 1 from staff_users where id = auth.uid() and role = 'main_admin' and status = 'active'));

create policy "sub_admin sees own team" on bookings for select
  using (parent_sub_admin_id = auth.uid());

create policy "collection_agent sees own" on bookings for select
  using (created_by_user_id = auth.uid());
```

The **Head Admin bootstrap + immutable lock** mechanism (AUDIT.md §12) would need an equivalent Postgres trigger/function pattern — e.g., a `before insert` trigger on `staff_users` that only allows `role = 'main_admin'` for a fixed list of emails and only when no lock row exists yet, mirroring `_resolveStaffRole`/`_ensureMainAdminLock` — this is a genuine rewrite (RLS policies are not a copy-paste of Firestore rules syntax), not a mechanical translation, and should get its own careful design pass and security review when this phase is actually undertaken.

---

## 6. Migration Strategy Options

| Strategy | Description | Recommendation |
|---|---|---|
| **Big-bang cutover** | Export all Firestore data, transform, bulk-import to Postgres, switch the app over in one deploy. | ❌ Not recommended — this is a **live business** (real patient bookings, real payments); a big-bang cutover risks losing or corrupting in-flight bookings. |
| **Dual-write / strangler pattern** | New code writes to both Firestore and Supabase for a transition period; reads gradually move to Supabase once parity is verified; Firestore writes are dropped last. | ✅ **Recommended** when this phase is undertaken — zero-downtime, verifiable at each step, fully revertible until the very last cutover. |
| **Read-replica sync job** | A scheduled job continuously mirrors Firestore → Postgres; app keeps writing to Firestore until the very end. | 🔷 Viable alternative to dual-write, slightly simpler to build (no app-code changes until cutover) but introduces sync lag to reason about. |

---

## 7. Data Migration Steps (when approved)

1. Export every Firestore collection listed in [BACKEND_DEPENDENCIES.md §2](BACKEND_DEPENDENCIES.md) (e.g. via the Firebase Admin SDK or `gcloud firestore export`).
2. Transform: flatten `serverTimestamp()` values to `timestamptz`; explode `tracker_states.timeline` arrays into `tracker_timeline` rows; explode `config/packages.items` / `config/tests.items` / `config/coupons.items` arrays into real table rows.
3. Import into the Postgres schema (§4), preserving existing Firestore document IDs as primary keys where humans see them (`bookings.id`) so nothing customer-facing (Booking IDs already shared with patients) changes.
4. Re-create RBAC as RLS policies (§5) and **security-review them explicitly** before relying on them — this is the highest-risk single step.
5. Rebuild the realtime pieces (package/test live-update broadcast, tracker live sync) using Supabase Realtime channels.
6. Parallel-run (dual-write strategy) until every admin page and every public page has been verified against Postgres reads.

---

## 8. Migration-Specific Risks

- **Auth UID mismatch**: Firebase `uid`s and Supabase Auth `uid`s are different identifier spaces. Existing `staff_users`/`bookings.createdByUserId`/RBAC ownership fields all key off Firebase UIDs today. A migration needs either a UID-mapping table or a forced re-authentication/re-linking step for every existing staff account — **this alone is a significant sub-project**, not a footnote.
- **RLS policy correctness**: the current Firestore rules (not in this repo — see BACKEND_DEPENDENCIES.md §13) encode real, previously-hardened security logic (including the fixed privilege-escalation bug in AUDIT.md §12). Recreating this as RLS is a rewrite that must be independently security-reviewed, not assumed equivalent just because the SQL "looks right."
- **Realtime listener rewiring**: every `onSnapshot` call site in the current code (packages, tests, bookings, tracker_states — 5+ distinct listeners) needs a Supabase Realtime equivalent, individually tested.
- **Cash Flow schema is only partially reconstructed** in this document (§4 note) — needs a dedicated full read of those functions before real migration work starts.
- **Third-party integrations are backend-agnostic and low-risk**: Razorpay, Cloudinary, EmailJS, WhatsApp links, and the Google Sheets webhook all call external HTTP APIs directly from the client/admin code — none of them depend on Firebase specifically, so they carry over to a Supabase-backed app unchanged.
- **Booking ID scheme** (`MPD-<timestamp>`) should be preserved as the Postgres primary key exactly as recommended in [BOOKING_FLOW.md §7](BOOKING_FLOW.md), so no previously-issued Booking ID (already given to real patients) ever breaks.

---

## 9. Recommended Sequencing Relative to the Website Redesign

**Do the multi-page UI/UX redesign first, entirely against Firebase as-is** (per [ARCHITECTURE_PLAN.md](ARCHITECTURE_PLAN.md)). Only after that ships and stabilizes in production should a Supabase migration be considered — and at that point, it should be run as its own separately-scoped project with its own audit of the Cash Flow module specifically (the one area this pass could not fully verify) and its own explicit RLS security review. Running both projects simultaneously would make it impossible to tell whether a bug came from the new front-end or the new backend.

---

## 10. Explicit Reminder

**Nothing in this document should be acted upon without separate, explicit approval.** No tables, policies, functions, or data have been created in the `woedykgrzczgogtymfxg` Supabase project as part of this task, and none should be until that approval is given.
