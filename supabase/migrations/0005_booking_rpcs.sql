-- ============================================================
-- Migration: 0005_booking_rpcs
-- ============================================================
-- Every write to the booking domain goes through one of these
-- SECURITY DEFINER functions. None of them trust a value the client
-- sends for anything security- or money-sensitive — price, discount,
-- slot availability, and role are always re-derived from the database.
-- ============================================================

-- ------------------------------------------------------------
-- get_slot_availability — real capacity check, not a fake "always
-- available" list. Counts actual non-cancelled bookings per slot.
-- ------------------------------------------------------------
create or replace function public.get_slot_availability(p_date date)
returns table(
  slot_id uuid, label text, start_time time, end_time time,
  sort_order int, capacity int, booked_count bigint, is_available boolean
)
language sql security definer stable set search_path = public
as $$
  select
    s.id, s.label, s.start_time, s.end_time, s.sort_order, s.default_capacity,
    coalesce(b.cnt, 0),
    coalesce(b.cnt, 0) < s.default_capacity
  from public.appointment_slots s
  left join (
    select slot_id, count(*) as cnt
    from public.bookings
    where scheduled_date = p_date and status not in ('cancelled','failed')
    group by slot_id
  ) b on b.slot_id = s.id
  where s.is_active = true
  order by s.sort_order;
$$;
grant execute on function public.get_slot_availability(date) to anon, authenticated;

-- ------------------------------------------------------------
-- create_booking — the ONLY way a booking is ever created.
-- Transactional (a plpgsql function body is one implicit transaction:
-- any exception rolls back every insert it already made). Idempotent
-- via idempotency_key: a retried submit returns the existing booking
-- instead of creating a second one.
-- ------------------------------------------------------------
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
  p_idempotency_key uuid
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
begin
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
    from public.bookings
    where scheduled_date = p_scheduled_date and slot_id = p_slot_id and status not in ('cancelled','failed');
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
    creator_role, created_by_user_id, created_by_name
  ) values (
    v_new_booking_code, p_idempotency_key, v_uid,
    p_patient_name, p_patient_phone, p_patient_email, p_patient_dob, p_patient_gender,
    p_collection_type, p_scheduled_date, p_slot_id, p_special_notes,
    v_item_price, v_discount, nullif(upper(trim(p_coupon_code)), ''), v_final,
    p_payment_mode, case when p_payment_mode = 'offline' then 'cash' else 'pending' end, v_status, 'booked',
    'patient', v_uid, coalesce(p_patient_name, 'Guest')
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
  values (v_new_booking_id, null, 'booked', v_uid, coalesce(p_patient_name, 'Guest'), 'Booking created');

  return query select v_new_booking_id, v_new_booking_code, v_final, v_status;
end;
$$;

grant execute on function public.create_booking(
  text, uuid, text, text, text, date, text, text, jsonb, date, uuid, text, text, text, uuid
) to anon, authenticated;

-- ------------------------------------------------------------
-- update_booking_stage — the write-side of the tracker. Not consumed
-- by any UI yet (admin migration is a later phase, per instruction),
-- but built and tested now since the tracker/realtime/history work in
-- this phase needs a real way to advance a booking to test against.
--
-- main_admin / sub_admin: full flexibility, matching the original
-- app's admin tracker (any stage, any time — it never enforced strict
-- linear order either, per AUDIT.md).
-- collection_agent: deliberately narrower — only the stages an actual
-- field agent's job covers, and only on bookings assigned to them.
-- ------------------------------------------------------------
create or replace function public.update_booking_stage(p_booking_id uuid, p_new_stage text, p_note text default null)
returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_old_stage text;
  v_valid_stages text[] := array['booked','dispatched','collected','processing','report_ready','completed','cancelled','no_show'];
  v_agent_allowed_stages text[] := array['dispatched','collected','cancelled','no_show'];
  v_role public.staff_role := public.current_user_role();
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
end;
$$;
grant execute on function public.update_booking_stage(uuid, text, text) to authenticated;

-- ------------------------------------------------------------
-- track_booking / track_booking_timeline — the ONLY public surface for
-- checking a booking's status. Requires BOTH the booking code AND the
-- exact phone number used at booking time; a wrong guess of either
-- returns nothing (deliberately not distinguishing "wrong code" from
-- "wrong phone", so an attacker can't use the error to narrow down
-- which half they got right). Returns only safe, minimal fields —
-- never internal notes, staff names, or anything about other bookings.
-- ------------------------------------------------------------
create or replace function public.track_booking(p_booking_code text, p_phone text)
returns table(
  booking_code text, patient_name text, item_name text, scheduled_date date,
  slot_label text, collection_type text, city text, pincode text,
  status text, stage text, created_at timestamptz
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
      (select ca.city from public.collection_addresses ca where ca.booking_id = v_booking.id),
      (select ca.pincode from public.collection_addresses ca where ca.booking_id = v_booking.id),
      v_booking.status, v_booking.stage, v_booking.created_at;
end;
$$;
grant execute on function public.track_booking(text, text) to anon, authenticated;

create or replace function public.track_booking_timeline(p_booking_code text, p_phone text)
returns table(new_status text, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
declare
  v_booking_id uuid;
begin
  select id into v_booking_id from public.bookings
    where booking_code = upper(trim(p_booking_code)) and patient_phone = p_phone;
  if v_booking_id is null then
    return;
  end if;

  return query
    select h.new_status, h.created_at
    from public.booking_status_history h
    where h.booking_id = v_booking_id
    order by h.created_at asc;
end;
$$;
grant execute on function public.track_booking_timeline(text, text) to anon, authenticated;

-- ------------------------------------------------------------
-- Realtime — needed for a logged-in patient's own "My Bookings ->
-- Track" view to update live (RLS-gated: only rows visible to the
-- subscribing user are ever delivered, same as any other query). A
-- guest tracking via track_booking() (no session) cannot use this —
-- anon has no table-level grant on bookings — so the public tracker
-- page polls the RPC instead. Both are documented plainly in
-- BOOKING_IMPLEMENTATION.md rather than presenting the guest path as
-- push-based when it isn't.
-- ------------------------------------------------------------
alter publication supabase_realtime add table public.bookings;
alter publication supabase_realtime add table public.booking_status_history;
