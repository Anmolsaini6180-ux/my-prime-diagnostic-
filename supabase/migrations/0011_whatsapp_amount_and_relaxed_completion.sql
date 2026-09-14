-- ============================================================
-- Migration: 0011_whatsapp_amount_and_relaxed_completion
-- ============================================================
-- Follow-up to the WhatsApp Booking admin page (Sections 12/13):
-- staff asked for (a) a real, editable "Total Amount" field when
-- creating a booking from a pasted WhatsApp message, and (b) a way to
-- record how much of that amount has actually been received.
--
-- This does NOT weaken the price-integrity invariant from migration
-- 0010 ("no client ever supplies final_amount, it's always re-derived
-- server-side"). Instead it adds a narrow, explicitly-audited
-- exception:
--   - A manual amount override is only honoured when the DATABASE
--     itself determines (from profiles.role, never from anything the
--     client claims) that the caller is staff (main_admin/sub_admin).
--     A patient calling create_booking() still cannot influence
--     final_amount in any way — v_creator_role is computed from
--     auth.uid() + profiles, exactly as migration 0010 already does.
--   - Every override is logged to booking_status_history (with both
--     the catalogue price and the overridden amount) and to
--     activity_log, so it's fully auditable after the fact.
--   - admin_update_booking() — the RPC used to EDIT an existing
--     booking after creation — still does not accept a price field at
--     all. The only new capability there is recording money received
--     against the amount already fixed at creation time.
-- ============================================================

-- ------------------------------------------------------------
-- PART 1 — amount_received: real, persisted "how much has actually
-- been collected" tracking. Previously there was no column for this
-- at all; the payment_status enum ('pending'/'paid'/'failed'/'cash')
-- only ever recorded a coarse label, never a rupee amount.
-- ------------------------------------------------------------
alter table public.bookings
  add column amount_received numeric(10,2) not null default 0;

alter table public.bookings
  add constraint bookings_amount_received_check check (amount_received >= 0);

comment on column public.bookings.amount_received is
  'Amount actually collected from the patient so far (cash or online). Independent of payment_status, which stays a coarse label. balance_due = final_amount - amount_received.';

-- ------------------------------------------------------------
-- PART 2 — create_booking(): add two trailing, staff-only, default
-- parameters. Adding parameters with defaults at the end is the one
-- shape change CREATE OR REPLACE allows without dropping the function
-- (same OID, same existing grants) — same technique migration 0010
-- used to add p_source.
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
  p_idempotency_key uuid,
  p_source text default 'web',
  -- Staff-only (enforced below from the caller's real DB role, never
  -- trusted from the client). null = use the catalogue price as-is,
  -- exactly like before this migration.
  p_override_amount numeric default null,
  -- Staff-only. How much of the (possibly overridden) final amount was
  -- already collected at booking time — e.g. cash taken on the spot.
  p_amount_received numeric default 0
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
  v_payment_status text;
  v_uid uuid := auth.uid();
  v_caller_role public.staff_role;
  v_caller_name text;
  v_creator_role text;
  v_booking_user_id uuid;
  v_parent_sub_admin uuid;
  v_amount_received numeric(10,2);
  v_note text;
  v_overridden boolean := false;
begin
  if v_uid is null then
    raise exception 'You must be signed in to create a booking.' using errcode = '28000';
  end if;

  select role, coalesce(full_name, email) into v_caller_role, v_caller_name
    from public.profiles where id = v_uid;

  if v_caller_role in ('main_admin', 'sub_admin') then
    v_creator_role := 'staff';
    v_booking_user_id := null;
    v_parent_sub_admin := case when v_caller_role = 'sub_admin' then v_uid else null end;
  else
    v_creator_role := 'patient';
    v_booking_user_id := v_uid;
    v_parent_sub_admin := null;
  end if;

  -- Hard boundary: even if a non-staff caller somehow sent these
  -- params, they are refused outright rather than silently ignored —
  -- fail loud, not quiet, on a security-relevant mismatch.
  if p_override_amount is not null and v_creator_role <> 'staff' then
    raise exception 'Only staff can set a manual booking amount' using errcode = '42501';
  end if;
  if coalesce(p_amount_received, 0) <> 0 and v_creator_role <> 'staff' then
    raise exception 'Only staff can record an amount received' using errcode = '42501';
  end if;
  if p_override_amount is not null and p_override_amount < 0 then
    raise exception 'Amount cannot be negative';
  end if;
  if coalesce(p_amount_received, 0) < 0 then
    raise exception 'Amount received cannot be negative';
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
    raise exception 'This time slot is fully booked -- please choose another slot';
  end if;

  if p_coupon_code is not null and length(trim(p_coupon_code)) > 0 then
    select * into v_coupon from public.validate_coupon(p_coupon_code, v_item_price);
    if not v_coupon.valid then
      raise exception '%', v_coupon.message;
    end if;
    v_discount := v_coupon.discount;
  end if;

  if p_override_amount is not null then
    v_final := p_override_amount;
    v_overridden := (p_override_amount is distinct from greatest(v_item_price - v_discount, 0));
  else
    v_final := greatest(v_item_price - v_discount, 0);
  end if;

  v_amount_received := coalesce(p_amount_received, 0);
  v_status := case when p_payment_mode = 'offline' then 'confirmed' else 'pending' end;
  v_payment_status := case
    when v_final > 0 and v_amount_received >= v_final then 'paid'
    when p_payment_mode = 'offline' then 'cash'
    else 'pending'
  end;
  v_new_booking_code := public.generate_booking_code();

  insert into public.bookings (
    booking_code, idempotency_key, user_id,
    patient_name, patient_phone, patient_email, patient_dob, patient_gender,
    collection_type, scheduled_date, slot_id, special_notes,
    subtotal_amount, discount_amount, coupon_code, final_amount, amount_received,
    payment_mode, payment_status, status, stage,
    source, creator_role, created_by_user_id, created_by_name, parent_sub_admin_id
  ) values (
    v_new_booking_code, p_idempotency_key, v_booking_user_id,
    p_patient_name, p_patient_phone, p_patient_email, p_patient_dob, p_patient_gender,
    p_collection_type, p_scheduled_date, p_slot_id, p_special_notes,
    v_item_price, v_discount, nullif(upper(trim(p_coupon_code)), ''), v_final, v_amount_received,
    p_payment_mode, v_payment_status, v_status, 'booked',
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

  v_note := case when v_creator_role = 'staff' then 'Booking created by staff (' || coalesce(p_source,'admin') || ')' else 'Booking created' end;
  if v_overridden then
    v_note := v_note || ' -- amount manually set to Rs.' || v_final || ' (catalogue price Rs.' || v_item_price || ')';
  end if;
  if v_amount_received > 0 then
    v_note := v_note || ' -- Rs.' || v_amount_received || ' received at booking';
  end if;

  insert into public.booking_status_history (booking_id, old_status, new_status, changed_by, changed_by_name, note)
  values (v_new_booking_id, null, 'booked', v_uid, coalesce(v_caller_name, p_patient_name, 'Guest'), v_note);

  perform private.log_activity(
    'booking_created', 'booking', v_new_booking_id::text,
    jsonb_build_object('source', coalesce(p_source,'web'), 'creator_role', v_creator_role, 'amount', v_final,
      'amount_overridden', v_overridden, 'amount_received', v_amount_received)
  );

  return query select v_new_booking_id, v_new_booking_code, v_final, v_status;
end;
$$;

revoke execute on function public.create_booking(
  text, uuid, text, text, text, date, text, text, jsonb, date, uuid, text, text, text, uuid, text, numeric, numeric
) from public, anon;
grant execute on function public.create_booking(
  text, uuid, text, text, text, date, text, text, jsonb, date, uuid, text, text, text, uuid, text, numeric, numeric
) to authenticated;

-- ------------------------------------------------------------
-- PART 3 — admin_update_booking(): unchanged pricing stance (still no
-- final_amount/override param — a price fixed at creation stays fixed
-- after the fact). New capability: record additional money received
-- against a booking that already exists, e.g. staff collect the
-- balance later. Auto-promotes payment_status to 'paid' once the
-- running total reaches final_amount.
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
  p_note text default null,
  p_amount_received numeric default null
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
  v_new_amount_received numeric(10,2);
  v_new_payment_status text;
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

  if p_amount_received is not null and p_amount_received < 0 then
    raise exception 'Amount received cannot be negative';
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
      raise exception 'This time slot is fully booked -- please choose another slot';
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

  v_new_amount_received := coalesce(p_amount_received, v_booking.amount_received);
  if p_amount_received is not null and p_amount_received <> v_booking.amount_received then
    v_changes := array_append(v_changes, 'amount_received: Rs.' || v_booking.amount_received || ' -> Rs.' || p_amount_received);
  end if;
  v_new_payment_status := case
    when v_booking.final_amount > 0 and v_new_amount_received >= v_booking.final_amount then 'paid'
    else v_booking.payment_status
  end;

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
    amount_received = v_new_amount_received,
    payment_status  = v_new_payment_status,
    updated_at      = now()
  where id = p_booking_id;

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
  uuid, text, text, text, date, text, text, jsonb, date, uuid, text, text, uuid, text, numeric
) to authenticated;
