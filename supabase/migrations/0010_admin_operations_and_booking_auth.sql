-- ============================================================
-- Migration: 0010_admin_operations_and_booking_auth
-- ============================================================
-- Full-audit findings (inspected before writing anything, per
-- instruction) and what this migration does about each:
--
--   1. CRITICAL SECURITY GAP: create_booking() read auth.uid() into
--      v_uid but never checked it was non-null, and was GRANTed to
--      `anon`. A logged-out visitor could call the RPC directly
--      (bypassing the UI entirely) and create a real booking with
--      user_id = NULL. Confirmed exploitable by reading the live
--      function body before touching it. Fixed below: the function
--      now raises an exception when auth.uid() is null, and EXECUTE
--      is revoked from `anon` entirely (defense in depth — belt AND
--      suspenders, not just the runtime check).
--
--   2. Staff (main_admin/sub_admin) need to create a booking ON
--      BEHALF OF a patient (Admin Add Booking, WhatsApp Booking) who
--      may have no Supabase account at all. Rather than duplicate
--      create_booking's pricing/availability/coupon logic in a second
--      function (explicitly forbidden by instruction — "do not
--      duplicate business logic in JavaScript", which extends to not
--      duplicating it in a second RPC either), create_booking() now
--      branches ONE extra time on the CALLER's own role (never a
--      value the client sends): staff -> creator_role='staff',
--      user_id stays NULL, created_by_user_id/name record who staff
--      it was; anyone else -> unchanged existing behavior
--      (creator_role='patient', user_id=caller). A new optional
--      p_source param (default 'web', backward compatible with the
--      existing call site) records web/admin/whatsapp for reporting.
--
--   3. bookings_sub_admin_select only matched parent_sub_admin_id,
--      which nothing had ever set (verified: 0 of 2 existing bookings
--      have it) — a sub_admin account would see ZERO bookings today.
--      Broadened to also include bookings they personally created and
--      bookings assigned to collection agents on their own team.
--
--   4. Gap found in profiles RLS: profiles_main_admin_update_all lets
--      ANY main_admin update ANY profile's role/status, and the
--      existing self-escalation trigger only restricts a user editing
--      THEIR OWN row. Nothing stopped a main_admin from demoting or
--      deactivating the protected Super Admin's row. Closed with a
--      new trigger that makes every uid in main_admin_locks immutable
--      on role/status, independent of who's asking.
--
--   5. New schema needed for this phase's admin modules, reusing
--      existing tables/RPCs wherever possible (per instruction) and
--      adding only what's genuinely new: activity_log (Section 31),
--      app_settings (Section 32, seeded with REAL values already
--      public in index-1.html/AUDIT.md — nothing invented), plus RPCs
--      for agent assignment, booking edits, and RLS-respecting
--      dashboard/workload aggregates.
-- ============================================================


-- ============================================================
-- PART 1 — create_booking(): require auth, support staff-on-behalf
-- ============================================================

create or replace function public.create_booking(
  p_item_type text,
  p_item_id uuid,
  p_patient_name text,
  p_patient_phone text,
  p_patient_email text,
  p_patient_dob date,
  p_patient_gender text,
  p_collection_type text,
  p_address jsonb,
  p_scheduled_date date,
  p_slot_id uuid,
  p_special_notes text,
  p_coupon_code text,
  p_payment_mode text,
  p_idempotency_key uuid,
  p_source text default 'web'
)
returns table(booking_id uuid, booking_code text, final_amount numeric, status text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing record;
  v_item_name text;
  v_item_price numeric(10,2);
  v_item_active boolean;
  v_slot record;
  v_booked_count int;
  v_discount numeric(10,2) := 0;
  v_coupon record;
  v_final numeric(10,2);
  v_new_booking_id uuid;
  v_new_booking_code text;
  v_status text;
  v_uid uuid := auth.uid();
  v_caller_role public.staff_role;
  v_caller_name text;
  v_creator_role text;
  v_booking_user_id uuid;
  v_parent_sub_admin uuid;
begin
  -- Fix #1: the single most important line in this migration. No
  -- session, no booking — verified by direct RPC test, see SECURITY.md.
  if v_uid is null then
    raise exception 'You must be signed in to create a booking.' using errcode = '28000';
  end if;

  select role, coalesce(full_name, email) into v_caller_role, v_caller_name
    from public.profiles where id = v_uid;

  if v_caller_role in ('main_admin', 'sub_admin') then
    -- Staff creating a booking on behalf of a patient who may not have
    -- (or need) a Supabase account at all — Admin Add Booking /
    -- WhatsApp Booking. Never attributed to the staff member's own
    -- "My Bookings" — user_id stays null, exactly like a guest booking
    -- taken over the phone in the original app.
    v_creator_role := 'staff';
    v_booking_user_id := null;
    v_parent_sub_admin := case when v_caller_role = 'sub_admin' then v_uid else null end;
  else
    -- Patient (or a collection_agent booking a test for themselves,
    -- which is harmless and not restricted) — unchanged from before.
    v_creator_role := 'patient';
    v_booking_user_id := v_uid;
    v_parent_sub_admin := null;
  end if;

  if p_idempotency_key is not null then
    select b.id, b.booking_code, b.final_amount, b.status
      into v_existing
      from public.bookings b
      where b.idempotency_key = p_idempotency_key;
    if found then
      return query select v_existing.id, v_existing.booking_code, v_existing.final_amount, v_existing.status;
      return;
    end if;
  end if;

  if p_item_type = 'package' then
    select name, price, is_active into v_item_name, v_item_price, v_item_active
      from public.packages where id = p_item_id;
  elsif p_item_type = 'test' then
    select name, price, is_active into v_item_name, v_item_price, v_item_active
      from public.tests where id = p_item_id;
  else
    raise exception 'Invalid item type: %', p_item_type;
  end if;

  if v_item_name is null then
    raise exception 'Selected % was not found', p_item_type;
  end if;
  if not coalesce(v_item_active, false) then
    raise exception '% is no longer available for booking', v_item_name;
  end if;

  if p_collection_type not in ('home','lab_visit') then
    raise exception 'Invalid collection type: %', p_collection_type;
  end if;
  if p_collection_type = 'home' and (p_address is null or coalesce(p_address->>'pincode','') = '' or coalesce(p_address->>'address_line','') = '') then
    raise exception 'Address is required for home collection';
  end if;

  if p_scheduled_date < current_date or p_scheduled_date > current_date + interval '30 days' then
    raise exception 'Please choose a date between today and the next 30 days';
  end if;

  select * into v_slot from public.appointment_slots where id = p_slot_id and is_active = true;
  if not found then
    raise exception 'Selected time slot is not available';
  end if;

  select count(*) into v_booked_count
    from public.bookings bk
    where bk.scheduled_date = p_scheduled_date and bk.slot_id = p_slot_id and bk.status not in ('cancelled','failed');
  if v_booked_count >= v_slot.default_capacity then
    raise exception 'This time slot is fully booked — please choose another slot';
  end if;

  if p_coupon_code is not null and length(trim(p_coupon_code)) > 0 then
    select * into v_coupon from public.validate_coupon(p_coupon_code, v_item_price);
    if not v_coupon.valid then
      raise exception '%', v_coupon.message;
    end if;
    v_discount := v_coupon.discount;
  end if;

  v_final := greatest(v_item_price - v_discount, 0);
  v_status := case when p_payment_mode = 'offline' then 'confirmed' else 'pending' end;
  v_new_booking_code := public.generate_booking_code();

  insert into public.bookings (
    booking_code, idempotency_key, user_id,
    patient_name, patient_phone, patient_email, patient_dob, patient_gender,
    collection_type, scheduled_date, slot_id, special_notes,
    subtotal_amount, discount_amount, coupon_code, final_amount,
    payment_mode, payment_status, status, stage,
    source, creator_role, created_by_user_id, created_by_name, parent_sub_admin_id
  ) values (
    v_new_booking_code, p_idempotency_key, v_booking_user_id,
    p_patient_name, p_patient_phone, p_patient_email, p_patient_dob, p_patient_gender,
    p_collection_type, p_scheduled_date, p_slot_id, p_special_notes,
    v_item_price, v_discount, nullif(upper(trim(p_coupon_code)), ''), v_final,
    p_payment_mode, case when p_payment_mode = 'offline' then 'cash' else 'pending' end, v_status, 'booked',
    coalesce(p_source, 'web'), v_creator_role, v_uid, coalesce(v_caller_name, p_patient_name, 'Guest'), v_parent_sub_admin
  ) returning id into v_new_booking_id;

  insert into public.booking_items (booking_id, item_type, package_id, test_id, name_snapshot, price_snapshot)
  values (
    v_new_booking_id, p_item_type,
    case when p_item_type = 'package' then p_item_id end,
    case when p_item_type = 'test' then p_item_id end,
    v_item_name, v_item_price
  );

  if p_collection_type = 'home' then
    insert into public.collection_addresses (booking_id, address_line, city, state, pincode, landmark)
    values (
      v_new_booking_id,
      p_address->>'address_line', p_address->>'city', p_address->>'state',
      p_address->>'pincode', p_address->>'landmark'
    );
  end if;

  if v_discount > 0 then
    update public.coupons set used_count = used_count + 1 where code = upper(trim(p_coupon_code));
  end if;

  insert into public.booking_status_history (booking_id, old_status, new_status, changed_by, changed_by_name, note)
  values (v_new_booking_id, null, 'booked', v_uid, coalesce(v_caller_name, p_patient_name, 'Guest'),
    case when v_creator_role = 'staff' then 'Booking created by staff (' || coalesce(p_source,'admin') || ')' else 'Booking created' end);

  perform private.log_activity(
    'booking_created', 'booking', v_new_booking_id::text,
    jsonb_build_object('source', coalesce(p_source,'web'), 'creator_role', v_creator_role, 'amount', v_final)
  );

  return query select v_new_booking_id, v_new_booking_code, v_final, v_status;
end;
$$;

-- Fix #1 continued: anon loses EXECUTE entirely — a guest has no path
-- to this function at all now, not even one that immediately errors.
revoke execute on function public.create_booking(
  text, uuid, text, text, text, date, text, text, jsonb, date, uuid, text, text, text, uuid, text
) from anon;
grant execute on function public.create_booking(
  text, uuid, text, text, text, date, text, text, jsonb, date, uuid, text, text, text, uuid, text
) to authenticated;


-- ============================================================
-- PART 2 — bookings_sub_admin_select: fix visibility (Fix #3)
-- ============================================================

drop policy if exists "bookings_sub_admin_select" on public.bookings;
create policy "bookings_sub_admin_select" on public.bookings for select using (
  private.current_user_role() = 'sub_admin' and (
    parent_sub_admin_id = auth.uid()
    or created_by_user_id = auth.uid()
    or assigned_collection_agent_id in (
      select id from public.profiles where parent_sub_admin_id = auth.uid()
    )
  )
);


-- ============================================================
-- PART 3 — Absolute protection for locked main_admins (Fix #4)
-- ============================================================
-- Independent of prevent_self_role_escalation() (which only stops a
-- non-main_admin editing their OWN row). This stops EVERYONE,
-- including another main_admin, from changing role/status away from
-- main_admin/active for any uid that main_admin_locks says is
-- permanently protected. Checked on UPDATE (the only write profiles
-- allows at all from the client; there is still no delete grant).
-- ------------------------------------------------------------
create or replace function private.protect_locked_main_admins()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (select 1 from public.main_admin_locks where uid = old.id) then
    if new.role <> 'main_admin' or new.status <> 'active' then
      raise exception 'This account is a protected Super Admin and cannot be demoted, deactivated, or have its reporting line changed.';
    end if;
  end if;
  return new;
end;
$$;

create trigger trg_protect_locked_main_admins
  before update on public.profiles
  for each row execute function private.protect_locked_main_admins();

-- Belt-and-suspenders: profiles has no delete GRANT today, so this can
-- never actually fire via the client — added anyway so a future
-- migration can never accidentally grant delete without this guard
-- already being in place.
create or replace function private.prevent_locked_main_admin_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (select 1 from public.main_admin_locks where uid = old.id) then
    raise exception 'This account is a protected Super Admin and cannot be deleted.';
  end if;
  return old;
end;
$$;

create trigger trg_prevent_locked_main_admin_delete
  before delete on public.profiles
  for each row execute function private.prevent_locked_main_admin_delete();


-- ============================================================
-- PART 4 — activity_log (Section 31)
-- ============================================================
create table public.activity_log (
  id           bigint generated always as identity primary key,
  actor_id     uuid references auth.users(id),
  actor_name   text,
  actor_role   text,
  action       text not null,
  entity_type  text not null,
  entity_id    text,
  metadata     jsonb,
  created_at   timestamptz not null default now()
);
create index idx_activity_log_entity on public.activity_log(entity_type, entity_id);
create index idx_activity_log_created on public.activity_log(created_at desc);
create index idx_activity_log_actor on public.activity_log(actor_id);
comment on table public.activity_log is
  'General admin action audit trail (staff/catalog/settings/booking-edit/assignment actions). Booking status/stage changes remain in booking_status_history as before — this table is the new general-purpose log Section 31 asked for, not a replacement for it.';

alter table public.activity_log enable row level security;
create policy "activity_log_main_admin_all" on public.activity_log for select using (private.is_main_admin());
-- entity_id is a free-form text column shared across every entity type
-- (bookings use a uuid string, coupons use their code, settings use
-- their key, etc.) — the regex guard below stops Postgres from ever
-- attempting entity_id::uuid on a non-booking row, which would raise a
-- cast error rather than just evaluating to false (AND is not
-- guaranteed short-circuit order in a planner qual).
create policy "activity_log_sub_admin_scoped" on public.activity_log for select using (
  private.current_user_role() = 'sub_admin' and (
    actor_id = auth.uid()
    or (
      entity_type = 'booking'
      and entity_id ~ '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
      and private.can_view_booking(entity_id::uuid)
    )
  )
);
create policy "activity_log_collection_agent_own" on public.activity_log for select using (
  private.current_user_role() = 'collection_agent' and actor_id = auth.uid()
);
-- No insert/update/delete policy for any client role — written only by
-- private.log_activity() and the catalog triggers below, both
-- SECURITY DEFINER, matching this project's "no direct write path"
-- pattern used everywhere else (SECURITY.md §5).
grant select on public.activity_log to authenticated;

create or replace function private.log_activity(
  p_action text, p_entity_type text, p_entity_id text, p_metadata jsonb default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_name text;
  v_role text;
begin
  select coalesce(full_name, email), role::text into v_name, v_role
    from public.profiles where id = v_uid;

  insert into public.activity_log (actor_id, actor_name, actor_role, action, entity_type, entity_id, metadata)
  values (v_uid, v_name, v_role, p_action, p_entity_type, p_entity_id, p_metadata);
end;
$$;

-- Catalog CRUD (tests/packages/coupons) happens via direct table
-- writes under existing is_main_admin()-gated RLS (Part 1 of migration
-- 0001) — not RPCs — so it's logged via triggers instead of an inline
-- call, without duplicating any business logic.
create or replace function private.log_catalog_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id text;
  v_label text;
begin
  v_id := coalesce((case when TG_OP = 'DELETE' then old.id else new.id end)::text, null);
  v_label := case when TG_OP = 'DELETE' then old.name else new.name end;
  perform private.log_activity(
    lower(TG_TABLE_NAME) || '_' || lower(TG_OP),
    TG_TABLE_NAME,
    v_id,
    jsonb_build_object('name', v_label)
  );
  return coalesce(new, old);
end;
$$;

create trigger trg_log_tests_change
  after insert or update or delete on public.tests
  for each row execute function private.log_catalog_change();
create trigger trg_log_packages_change
  after insert or update or delete on public.packages
  for each row execute function private.log_catalog_change();

-- coupons has no `name` column — a tiny variant so the shared function
-- above doesn't have to special-case it.
create or replace function private.log_coupon_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform private.log_activity(
    'coupons_' || lower(TG_OP), 'coupons',
    coalesce(case when TG_OP = 'DELETE' then old.code else new.code end, null),
    jsonb_build_object('code', case when TG_OP = 'DELETE' then old.code else new.code end)
  );
  return coalesce(new, old);
end;
$$;
create trigger trg_log_coupons_change
  after insert or update or delete on public.coupons
  for each row execute function private.log_coupon_change();


-- ============================================================
-- PART 5 — update_booking_stage: also write to activity_log
-- (kept 100% behavior-compatible — only an added log line)
-- ============================================================
create or replace function public.update_booking_stage(p_booking_id uuid, p_new_stage text, p_note text default null)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_old_stage text;
  v_valid_stages text[] := array['booked','dispatched','collected','processing','report_ready','completed','cancelled','no_show'];
  v_agent_allowed_stages text[] := array['dispatched','collected','cancelled','no_show'];
  v_role public.staff_role := private.current_user_role();
  v_uid uuid := auth.uid();
  v_name text;
begin
  if v_role not in ('main_admin','sub_admin','collection_agent') then
    raise exception 'Only staff can update booking stage';
  end if;

  if p_new_stage <> all(v_valid_stages) then
    raise exception 'Invalid stage: %', p_new_stage;
  end if;

  if v_role = 'collection_agent' and p_new_stage <> all(v_agent_allowed_stages) then
    raise exception 'Collection agents can only set: dispatched, collected, cancelled, or no_show';
  end if;

  if v_role = 'collection_agent' and not exists (
    select 1 from public.bookings
    where id = p_booking_id and (assigned_collection_agent_id = v_uid or created_by_user_id = v_uid)
  ) then
    raise exception 'You are not assigned to this booking';
  end if;

  select stage into v_old_stage from public.bookings where id = p_booking_id;
  if v_old_stage is null then
    raise exception 'Booking not found';
  end if;

  select coalesce(full_name, email) into v_name from public.profiles where id = v_uid;

  update public.bookings
    set stage = p_new_stage,
        status = case when p_new_stage = 'completed' then 'completed'
                      when p_new_stage in ('cancelled','no_show') then 'cancelled'
                      else status end,
        assigned_collection_agent_id = coalesce(assigned_collection_agent_id, case when p_new_stage = 'dispatched' then v_uid end),
        updated_at = now()
    where id = p_booking_id;

  insert into public.booking_status_history (booking_id, old_status, new_status, changed_by, changed_by_name, note)
  values (p_booking_id, v_old_stage, p_new_stage, v_uid, coalesce(v_name, 'Staff'), p_note);

  perform private.log_activity(
    'booking_stage_updated', 'booking', p_booking_id::text,
    jsonb_build_object('old_stage', v_old_stage, 'new_stage', p_new_stage)
  );
end;
$$;
-- Grant unchanged (already authenticated-only from migration 0005).


-- ============================================================
-- PART 6 — Shared agent-assignment validation + assign_collection_agent RPC
-- (Section 21)
-- ============================================================
create or replace function private.validate_agent_assignment(p_agent_id uuid, p_caller_role public.staff_role, p_caller_uid uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_agent record;
begin
  select role, status, parent_sub_admin_id into v_agent from public.profiles where id = p_agent_id;
  if v_agent is null or v_agent.role <> 'collection_agent' then
    raise exception 'Selected staff member is not an active collection agent';
  end if;
  if v_agent.status <> 'active' then
    raise exception 'This collection agent is deactivated';
  end if;
  if p_caller_role = 'sub_admin' and v_agent.parent_sub_admin_id is distinct from p_caller_uid then
    raise exception 'You can only assign collection agents on your own team';
  end if;
end;
$$;

create or replace function public.assign_collection_agent(p_booking_id uuid, p_agent_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role public.staff_role := private.current_user_role();
  v_uid uuid := auth.uid();
  v_stage text;
  v_agent_name text;
  v_caller_name text;
begin
  if v_role not in ('main_admin','sub_admin') then
    raise exception 'Only Main Admin or Sub Admin can assign a collection agent';
  end if;
  if v_role = 'sub_admin' and not private.can_view_booking(p_booking_id) then
    raise exception 'Not authorized to modify this booking';
  end if;

  perform private.validate_agent_assignment(p_agent_id, v_role, v_uid);

  select stage into v_stage from public.bookings where id = p_booking_id;
  if v_stage is null then
    raise exception 'Booking not found';
  end if;

  update public.bookings
    set assigned_collection_agent_id = p_agent_id, updated_at = now()
    where id = p_booking_id;

  select coalesce(full_name, email) into v_agent_name from public.profiles where id = p_agent_id;
  select coalesce(full_name, email) into v_caller_name from public.profiles where id = v_uid;

  insert into public.booking_status_history (booking_id, old_status, new_status, changed_by, changed_by_name, note)
  values (p_booking_id, v_stage, v_stage, v_uid, coalesce(v_caller_name, 'Staff'), 'Assigned to collection agent: ' || coalesce(v_agent_name, 'Unknown'));

  perform private.log_activity('agent_assigned', 'booking', p_booking_id::text, jsonb_build_object('agent_id', p_agent_id, 'agent_name', v_agent_name));
end;
$$;
grant execute on function public.assign_collection_agent(uuid, uuid) to authenticated;


-- ============================================================
-- PART 7 — admin_update_booking RPC (Section 9)
-- ============================================================
-- Deliberately does NOT accept an amount/price field at all — pricing
-- stays exclusively server-computed at creation time (Section 27); an
-- edit here can change patient/schedule/collection/status/notes/agent,
-- never the historical amount. Partial-update pattern: any parameter
-- left null keeps the existing value (so this can't be used to blank
-- out a required field by omission).
-- ------------------------------------------------------------
create or replace function public.admin_update_booking(
  p_booking_id uuid,
  p_patient_name text default null,
  p_patient_phone text default null,
  p_patient_email text default null,
  p_patient_dob date default null,
  p_patient_gender text default null,
  p_collection_type text default null,
  p_address jsonb default null,
  p_scheduled_date date default null,
  p_slot_id uuid default null,
  p_special_notes text default null,
  p_status text default null,
  p_assigned_agent_id uuid default null,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_role public.staff_role := private.current_user_role();
  v_uid uuid := auth.uid();
  v_caller_name text;
  v_booking public.bookings;
  v_new_date date;
  v_new_slot uuid;
  v_slot record;
  v_booked_count int;
  v_changes text[] := array[]::text[];
begin
  if v_role not in ('main_admin','sub_admin') then
    raise exception 'Only Main Admin or Sub Admin can edit bookings';
  end if;
  if v_role = 'sub_admin' and not private.can_view_booking(p_booking_id) then
    raise exception 'Not authorized to edit this booking';
  end if;

  select * into v_booking from public.bookings where id = p_booking_id;
  if v_booking is null then
    raise exception 'Booking not found';
  end if;

  select coalesce(full_name, email) into v_caller_name from public.profiles where id = v_uid;

  v_new_date := coalesce(p_scheduled_date, v_booking.scheduled_date);
  v_new_slot := coalesce(p_slot_id, v_booking.slot_id);

  if v_new_date <> v_booking.scheduled_date or v_new_slot <> v_booking.slot_id then
    select * into v_slot from public.appointment_slots where id = v_new_slot and is_active = true;
    if not found then
      raise exception 'Selected time slot is not available';
    end if;
    select count(*) into v_booked_count
      from public.bookings
      where scheduled_date = v_new_date and slot_id = v_new_slot
        and status not in ('cancelled','failed') and id <> p_booking_id;
    if v_booked_count >= v_slot.default_capacity then
      raise exception 'This time slot is fully booked — please choose another slot';
    end if;
    v_changes := array_append(v_changes, 'schedule');
  end if;

  if p_collection_type is not null and p_collection_type <> v_booking.collection_type then
    if p_collection_type not in ('home','lab_visit') then
      raise exception 'Invalid collection type: %', p_collection_type;
    end if;
    v_changes := array_append(v_changes, 'collection_type');
  end if;

  if p_status is not null and p_status <> v_booking.status then
    v_changes := array_append(v_changes, 'status: ' || v_booking.status || ' -> ' || p_status);
  end if;

  if p_assigned_agent_id is not null and p_assigned_agent_id is distinct from v_booking.assigned_collection_agent_id then
    perform private.validate_agent_assignment(p_assigned_agent_id, v_role, v_uid);
    v_changes := array_append(v_changes, 'agent_reassigned');
  end if;

  update public.bookings set
    patient_name    = coalesce(p_patient_name, patient_name),
    patient_phone   = coalesce(p_patient_phone, patient_phone),
    patient_email   = coalesce(p_patient_email, patient_email),
    patient_dob     = coalesce(p_patient_dob, patient_dob),
    patient_gender  = coalesce(p_patient_gender, patient_gender),
    collection_type = coalesce(p_collection_type, collection_type),
    scheduled_date  = v_new_date,
    slot_id         = v_new_slot,
    special_notes   = coalesce(p_special_notes, special_notes),
    status          = coalesce(p_status, status),
    assigned_collection_agent_id = coalesce(p_assigned_agent_id, assigned_collection_agent_id),
    updated_at      = now()
  where id = p_booking_id;

  -- Address: upsert when moving to/staying on home collection with new
  -- details; remove if moving away from home collection.
  if coalesce(p_collection_type, v_booking.collection_type) = 'home' and p_address is not null then
    insert into public.collection_addresses (booking_id, address_line, city, state, pincode, landmark)
    values (p_booking_id, p_address->>'address_line', p_address->>'city', p_address->>'state', p_address->>'pincode', p_address->>'landmark')
    on conflict (booking_id) do update set
      address_line = excluded.address_line, city = excluded.city, state = excluded.state,
      pincode = excluded.pincode, landmark = excluded.landmark;
  elsif p_collection_type = 'lab_visit' and v_booking.collection_type = 'home' then
    delete from public.collection_addresses where booking_id = p_booking_id;
  end if;

  insert into public.booking_status_history (booking_id, old_status, new_status, changed_by, changed_by_name, note)
  values (
    p_booking_id, v_booking.status, coalesce(p_status, v_booking.status), v_uid, coalesce(v_caller_name, 'Staff'),
    coalesce(p_note, 'Booking details updated' || case when array_length(v_changes,1) > 0 then ' (' || array_to_string(v_changes, ', ') || ')' else '' end)
  );

  perform private.log_activity('booking_updated', 'booking', p_booking_id::text, jsonb_build_object('changes', v_changes));
end;
$$;
grant execute on function public.admin_update_booking(
  uuid, text, text, text, date, text, text, jsonb, date, uuid, text, text, uuid, text
) to authenticated;


-- ============================================================
-- PART 8 — app_settings (Section 32)
-- Seeded with values already public today in index-1.html/the live
-- site footer — not invented. No "home collection charge" setting:
-- confirmed via AUDIT.md/BACKEND_DEPENDENCIES.md that no such charge
-- exists anywhere in this business's real pricing model, so a setting
-- for it would be unused by the application — exactly what the
-- instruction says not to create.
-- ------------------------------------------------------------
create table public.app_settings (
  key         text primary key,
  value       jsonb not null,
  updated_at  timestamptz not null default now(),
  updated_by  uuid references auth.users(id)
);
comment on table public.app_settings is
  'Small key/value config store. Every row here is read by real application code — see README.md for which pages consume which key.';

alter table public.app_settings enable row level security;
-- Public read: every seeded key is already public-facing information
-- (phone/email/name already shown on the live site) — nothing
-- sensitive is ever stored here.
create policy "app_settings_public_read" on public.app_settings for select using (true);
create policy "app_settings_main_admin_write" on public.app_settings for insert with check (private.is_main_admin());
create policy "app_settings_main_admin_update" on public.app_settings for update using (private.is_main_admin());
create policy "app_settings_main_admin_delete" on public.app_settings for delete using (private.is_main_admin());
create trigger trg_app_settings_updated_at before update on public.app_settings for each row execute function public.set_updated_at();
grant select on public.app_settings to anon, authenticated;
grant insert, update, delete on public.app_settings to authenticated;

create or replace function private.log_settings_change()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  perform private.log_activity(
    'setting_' || lower(TG_OP), 'app_settings',
    coalesce(new.key, old.key),
    jsonb_build_object('value', coalesce(new.value, old.value))
  );
  return coalesce(new, old);
end;
$$;
create trigger trg_log_settings_change
  after insert or update or delete on public.app_settings
  for each row execute function private.log_settings_change();

insert into public.app_settings (key, value) values
  ('lab_name', '"My Prime Diagnostic"'),
  ('support_phone', '"+91 74284 56590"'),
  ('support_email', '"myprimediagnosticssupport@gmail.com"')
on conflict (key) do nothing;


-- ============================================================
-- PART 9 — RLS-respecting aggregate RPCs (Sections 6, 24)
-- Deliberately NOT security definer — runs as the calling role, so
-- Postgres applies the caller's own RLS to `bookings`/`profiles`
-- exactly as a normal query would (main_admin: everything; sub_admin:
-- their scoped rows per Part 2; collection_agent: their own rows).
-- No role-based branching duplicated here — the database's existing
-- RLS is the only thing deciding what each caller's numbers include.
-- ============================================================
create or replace function public.admin_dashboard_stats()
returns table (
  total_bookings bigint, today_bookings bigint, pending_count bigint, confirmed_count bigint,
  sample_collected_count bigint, processing_count bigint, completed_count bigint, cancelled_count bigint,
  home_count bigint, walkin_count bigint, unassigned_count bigint, assigned_count bigint,
  total_revenue numeric
)
language sql
stable
set search_path = public
as $$
  select
    count(*),
    count(*) filter (where scheduled_date = current_date),
    count(*) filter (where status = 'pending'),
    count(*) filter (where status = 'confirmed'),
    count(*) filter (where stage = 'collected'),
    count(*) filter (where stage = 'processing'),
    count(*) filter (where status = 'completed'),
    count(*) filter (where status = 'cancelled'),
    count(*) filter (where collection_type = 'home'),
    count(*) filter (where collection_type = 'lab_visit'),
    count(*) filter (where assigned_collection_agent_id is null and status not in ('cancelled','failed')),
    count(*) filter (where assigned_collection_agent_id is not null),
    coalesce(sum(final_amount) filter (where status not in ('cancelled','failed')), 0)
  from public.bookings;
$$;
grant execute on function public.admin_dashboard_stats() to authenticated;

create or replace function public.team_workload()
returns table(
  agent_id uuid, agent_name text, agent_email text, agent_status text,
  today_assigned bigint, upcoming_assigned bigint, completed_count bigint, pending_count bigint
)
language sql
stable
set search_path = public
as $$
  select
    p.id, p.full_name, p.email, p.status,
    count(b.id) filter (where b.scheduled_date = current_date and b.status not in ('cancelled','failed')),
    count(b.id) filter (where b.scheduled_date > current_date and b.status not in ('cancelled','failed')),
    count(b.id) filter (where b.status = 'completed'),
    count(b.id) filter (where b.stage not in ('completed','cancelled','no_show'))
  from public.profiles p
  left join public.bookings b on b.assigned_collection_agent_id = p.id
  where p.role = 'collection_agent'
  group by p.id, p.full_name, p.email, p.status;
$$;
grant execute on function public.team_workload() to authenticated;


-- ============================================================
-- PART 10 — track_booking(): add final_amount + address_line
-- (needed for the customer-facing WhatsApp confirmation message,
-- Section 14/15 — same auth model as before: requires the exact
-- phone match, nothing new is exposed to a wrong guess).
-- ============================================================
drop function if exists public.track_booking(text, text);
create function public.track_booking(p_booking_code text, p_phone text)
returns table(
  booking_code text, patient_name text, item_name text, scheduled_date date,
  slot_label text, collection_type text, address_line text, city text, pincode text,
  status text, stage text, final_amount numeric, created_at timestamptz
)
language plpgsql security definer set search_path = public
as $$
declare
  v_booking public.bookings;
begin
  select b.* into v_booking
    from public.bookings b
    where b.booking_code = upper(trim(p_booking_code))
    and b.patient_phone = p_phone;

  if not found then
    return;
  end if;

  return query
    select
      v_booking.booking_code, v_booking.patient_name,
      (select bi.name_snapshot from public.booking_items bi where bi.booking_id = v_booking.id limit 1),
      v_booking.scheduled_date,
      (select s.label from public.appointment_slots s where s.id = v_booking.slot_id),
      v_booking.collection_type,
      (select ca.address_line from public.collection_addresses ca where ca.booking_id = v_booking.id),
      (select ca.city from public.collection_addresses ca where ca.booking_id = v_booking.id),
      (select ca.pincode from public.collection_addresses ca where ca.booking_id = v_booking.id),
      v_booking.status, v_booking.stage, v_booking.final_amount, v_booking.created_at;
end;
$$;
grant execute on function public.track_booking(text, text) to anon, authenticated;
