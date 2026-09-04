-- ============================================================
-- Migration: 0004_bookings_schema
-- ============================================================
-- Booking domain tables. Design notes (full detail in DATABASE.md):
--
--   - bookings.status  = coarse lifecycle (pending/confirmed/failed/
--     cancelled/completed) — mirrors the original app's field exactly.
--   - bookings.stage   = fine-grained operational pipeline (booked/
--     dispatched/collected/processing/report_ready/completed/
--     cancelled/no_show) — the exact TRACKER_FLOW vocabulary from
--     index-1.html, kept unrenamed per instruction.
--   - booking_status_history replaces the original's tracker_states
--     timeline ARRAY with a normalized table (better Postgres
--     practice), and is also this migration's audit trail for
--     bookings.status changes.
--   - collection_addresses is 1-way (address -> booking), not 1:1
--     circular, and only created for collection_type='home'.
--   - appointment_slots is a real reference table replacing the
--     hardcoded <select> options in the original modal — same 8
--     windows, now with a genuine (if placeholder-value) capacity
--     model so availability checks are real, not fake.
--
-- RLS is enabled on every table below, in this same migration —
-- never a window where a table exists without it (see SECURITY.md
-- for why that discipline exists).
-- ============================================================

-- ------------------------------------------------------------
-- appointment_slots
-- ------------------------------------------------------------
create table public.appointment_slots (
  id                uuid primary key default gen_random_uuid(),
  label             text not null,
  start_time        time not null,
  end_time          time not null,
  sort_order        int not null,
  default_capacity  int not null default 12,
  is_active         boolean not null default true
);
comment on table public.appointment_slots is
  'Reference list of bookable time windows. default_capacity is a placeholder pending the business''s real operational numbers — see DATABASE.md.';

alter table public.appointment_slots enable row level security;
create policy "appointment_slots_public_read" on public.appointment_slots for select using (is_active = true);
create policy "appointment_slots_main_admin_read_all" on public.appointment_slots for select using (public.is_main_admin());
create policy "appointment_slots_main_admin_insert" on public.appointment_slots for insert with check (public.is_main_admin());
create policy "appointment_slots_main_admin_update" on public.appointment_slots for update using (public.is_main_admin());
create policy "appointment_slots_main_admin_delete" on public.appointment_slots for delete using (public.is_main_admin());
grant select on public.appointment_slots to anon, authenticated;

-- ------------------------------------------------------------
-- bookings
-- ------------------------------------------------------------
create table public.bookings (
  id                  uuid primary key default gen_random_uuid(),
  booking_code        text unique not null,
  idempotency_key     uuid unique,

  -- Patient snapshot — always stored directly on the booking (not a
  -- foreign key to a "patients" table), matching the original app's
  -- model: a booking can be made by a guest with no account at all.
  user_id             uuid references auth.users(id) on delete set null,
  patient_name        text not null,
  patient_phone       text not null check (patient_phone ~ '^[6-9][0-9]{9}$'),
  patient_email       text,
  patient_dob         date,
  patient_gender      text check (patient_gender in ('male','female','other')),

  -- Collection — the two real options confirmed in the source app
  -- (AUDIT.md / BOOKING_FLOW.md), no others invented.
  collection_type     text not null check (collection_type in ('home','lab_visit')),
  scheduled_date      date not null,
  slot_id             uuid not null references public.appointment_slots(id),

  special_notes       text,

  -- Pricing — always server-computed by create_booking(); never a
  -- column the client can write directly (see RLS below: no
  -- insert/update grant on this table for anon/authenticated at all).
  subtotal_amount     numeric(10,2) not null,
  discount_amount     numeric(10,2) not null default 0,
  coupon_code         text references public.coupons(code),
  final_amount        numeric(10,2) not null,

  payment_mode        text not null check (payment_mode in ('online','offline')),
  payment_status      text not null default 'pending' check (payment_status in ('pending','paid','failed','cash')),
  razorpay_order_id   text,
  razorpay_payment_id text,

  status              text not null default 'pending' check (status in ('pending','confirmed','failed','cancelled','completed')),
  stage               text not null default 'booked' check (stage in ('booked','dispatched','collected','processing','report_ready','completed','cancelled','no_show')),

  source              text not null default 'web',
  creator_role        text not null default 'patient',
  created_by_user_id  uuid references auth.users(id),
  created_by_name     text,
  parent_sub_admin_id uuid references auth.users(id),
  assigned_collection_agent_id uuid references auth.users(id),

  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

create index idx_bookings_user on public.bookings(user_id);
create index idx_bookings_date_slot on public.bookings(scheduled_date, slot_id);
create index idx_bookings_status on public.bookings(status);
create index idx_bookings_stage on public.bookings(stage);
create index idx_bookings_parent_sub_admin on public.bookings(parent_sub_admin_id);
create index idx_bookings_assigned_agent on public.bookings(assigned_collection_agent_id);

create trigger trg_bookings_updated_at before update on public.bookings for each row execute function public.set_updated_at();

-- Human-friendly, collision-safe booking code. Deliberately NOT the
-- original's `MPD-<timestamp>` scheme (sequential/guessable) — 6
-- characters from a 31-symbol alphabet (no 0/O/1/I/L) is easy to
-- read/type and gives ~887M combinations, checked for collision with
-- a bounded retry loop rather than hoped-for uniqueness.
create or replace function public.generate_booking_code()
returns text
language plpgsql
set search_path = public
as $$
declare
  charset text := '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  code text;
  i int;
  attempt int := 0;
begin
  loop
    code := 'MPD-';
    for i in 1..6 loop
      code := code || substr(charset, floor(random() * length(charset) + 1)::int, 1);
    end loop;
    exit when not exists (select 1 from public.bookings where booking_code = code);
    attempt := attempt + 1;
    if attempt > 20 then
      raise exception 'Could not generate a unique booking code after % attempts', attempt;
    end if;
  end loop;
  return code;
end;
$$;

-- ------------------------------------------------------------
-- booking_items — schema supports multiple items per booking (the
-- source app's cart/checkout pathway combines several tests into one
-- booking); the wizard built in this phase always inserts exactly one.
-- ------------------------------------------------------------
create table public.booking_items (
  id              uuid primary key default gen_random_uuid(),
  booking_id      uuid not null references public.bookings(id) on delete cascade,
  item_type       text not null check (item_type in ('package','test')),
  package_id      uuid references public.packages(id),
  test_id         uuid references public.tests(id),
  name_snapshot   text not null,
  price_snapshot  numeric(10,2) not null,
  quantity        int not null default 1,
  constraint booking_items_item_ref_check check (
    (item_type = 'package' and package_id is not null and test_id is null) or
    (item_type = 'test' and test_id is not null and package_id is null)
  )
);
create index idx_booking_items_booking on public.booking_items(booking_id);

-- ------------------------------------------------------------
-- collection_addresses — one-way FK to bookings (booking created
-- first, address second, inside the same transaction), only for
-- collection_type='home'.
-- ------------------------------------------------------------
create table public.collection_addresses (
  id            uuid primary key default gen_random_uuid(),
  booking_id    uuid not null unique references public.bookings(id) on delete cascade,
  address_line  text not null,
  city          text,
  state         text,
  pincode       text not null check (pincode ~ '^[0-9]{6}$'),
  landmark      text,
  created_at    timestamptz not null default now()
);

-- ------------------------------------------------------------
-- booking_status_history — the audit trail. Deliberately excludes
-- nothing at the schema level (staff need the full picture), but the
-- customer-facing RPCs (track_booking_timeline, see 0005) only ever
-- select new_status + created_at — internal notes/who-changed-it are
-- never part of any customer-facing return shape.
-- ------------------------------------------------------------
create table public.booking_status_history (
  id              bigint generated always as identity primary key,
  booking_id      uuid not null references public.bookings(id) on delete cascade,
  old_status      text,
  new_status      text not null,
  changed_by      uuid references auth.users(id),
  changed_by_name text,
  note            text,
  created_at      timestamptz not null default now()
);
create index idx_bsh_booking on public.booking_status_history(booking_id, created_at);

-- ------------------------------------------------------------
-- RLS helper — reused by every booking child table below so their
-- policies can't drift out of sync with bookings' own visibility rule.
-- ------------------------------------------------------------
create or replace function public.can_view_booking(p_booking_id uuid)
returns boolean
language sql security definer stable set search_path = public
as $$
  select exists (
    select 1 from public.bookings b
    where b.id = p_booking_id
    and (
      b.user_id = auth.uid()
      or public.is_main_admin()
      or (public.current_user_role() = 'sub_admin' and b.parent_sub_admin_id = auth.uid())
      or (public.current_user_role() = 'collection_agent' and (b.assigned_collection_agent_id = auth.uid() or b.created_by_user_id = auth.uid()))
    )
  );
$$;

-- ------------------------------------------------------------
-- RLS: bookings and children.
--
-- No insert/update/delete policy is defined for bookings, booking_items,
-- or collection_addresses for anon/authenticated — deliberately. Every
-- write goes through the SECURITY DEFINER RPCs in migration 0005
-- (create_booking, update_booking_stage), which validate everything
-- server-side. This makes "customer cannot modify price/status/
-- ownership" trivially true: there is no direct write path at all.
-- ------------------------------------------------------------
alter table public.bookings enable row level security;
create policy "bookings_owner_select" on public.bookings for select using (user_id = auth.uid());
create policy "bookings_main_admin_select" on public.bookings for select using (public.is_main_admin());
create policy "bookings_sub_admin_select" on public.bookings for select using (public.current_user_role() = 'sub_admin' and parent_sub_admin_id = auth.uid());
create policy "bookings_collection_agent_select" on public.bookings for select using (public.current_user_role() = 'collection_agent' and (assigned_collection_agent_id = auth.uid() or created_by_user_id = auth.uid()));
grant select on public.bookings to authenticated;

alter table public.booking_items enable row level security;
create policy "booking_items_visible" on public.booking_items for select using (public.can_view_booking(booking_id));
grant select on public.booking_items to authenticated;

alter table public.collection_addresses enable row level security;
create policy "collection_addresses_visible" on public.collection_addresses for select using (public.can_view_booking(booking_id));
grant select on public.collection_addresses to authenticated;

alter table public.booking_status_history enable row level security;
create policy "booking_status_history_visible" on public.booking_status_history for select using (public.can_view_booking(booking_id));
grant select on public.booking_status_history to authenticated;
