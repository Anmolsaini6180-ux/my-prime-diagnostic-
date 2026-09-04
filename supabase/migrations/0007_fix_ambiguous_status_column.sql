-- ============================================================
-- Migration: 0007_fix_ambiguous_status_column
-- ============================================================
-- Real bug caught by actually running the booking flow in-browser
-- (not just reading the SQL): create_booking()'s `RETURNS TABLE(...,
-- status text)` makes `status` an implicit PL/pgSQL variable inside
-- the function body. The slot-capacity check queried public.bookings
-- with a bare, unqualified `status` column reference, which Postgres
-- correctly refused to resolve ("column reference status is
-- ambiguous") since it could mean either the OUT variable or the
-- table column. Every booking submission was failing on this until
-- caught in testing. Fixed by aliasing the table and qualifying the
-- reference — same fix applied defensively to the idempotency lookup
-- for consistency, even though that one was already qualified.
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
    select bk.id, bk.booking_code, bk.final_amount, bk.status
      into v_existing
      from public.bookings bk
      where bk.idempotency_key = p_idempotency_key;
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

  -- FIX: qualified with `bk.` — was the bare, ambiguous `status` reference.
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
