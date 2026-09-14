// ============================================================
// Bookings service — the only place that calls the booking RPCs.
// Every write goes through create_booking(); nothing here computes
// price/discount/availability client-side and sends it to the server
// as fact — the server always re-derives those from trusted data.
// ============================================================
import { supabase } from '../supabase-client.js';

export async function fetchSlotAvailability(dateStr) {
  const { data, error } = await supabase.rpc('get_slot_availability', { p_date: dateStr });
  if (error) throw error;
  return data || [];
}

export async function submitBooking(draft) {
  const { data, error } = await supabase.rpc('create_booking', {
    p_item_type: draft.itemType,
    p_item_id: draft.itemId,
    p_patient_name: draft.patientName,
    p_patient_phone: draft.patientPhone,
    p_patient_email: draft.patientEmail || null,
    p_patient_dob: draft.patientDob || null,
    p_patient_gender: draft.patientGender || null,
    p_collection_type: draft.collectionType,
    p_address: draft.collectionType === 'home' ? {
      address_line: draft.address.addressLine,
      city: draft.address.city,
      state: draft.address.state,
      pincode: draft.address.pincode,
      landmark: draft.address.landmark,
    } : null,
    p_scheduled_date: draft.scheduledDate,
    p_slot_id: draft.slotId,
    p_special_notes: draft.specialNotes || null,
    p_coupon_code: draft.couponCode || null,
    p_payment_mode: draft.paymentMode,
    p_idempotency_key: draft.idempotencyKey,
    // 'web' (default) for the public wizard; admin/add-booking.html and
    // admin/whatsapp-booking.html pass 'admin'/'whatsapp' explicitly.
    // Purely descriptive for reporting — create_booking() decides who
    // actually owns the booking from the CALLER's own role server-side,
    // never from this value. See migration 0010.
    p_source: draft.source || 'web',
    // Both staff-only, enforced server-side from the caller's real DB
    // role (never trusted from here) — see migration 0011. Left
    // undefined/null/0 by every non-staff caller (the public wizard
    // never sets these fields on its draft at all), so this is a no-op
    // for patients even if someone tampered with the client code.
    p_override_amount: draft.overrideAmount ?? null,
    p_amount_received: draft.amountReceived ?? 0,
  });
  if (error) throw error;
  return data && data[0]; // { booking_id, booking_code, final_amount, status }
}

export async function trackBooking(bookingCode, phone) {
  const { data, error } = await supabase.rpc('track_booking', { p_booking_code: bookingCode, p_phone: phone });
  if (error) throw error;
  return data && data[0]; // undefined if code+phone didn't match
}

export async function trackBookingTimeline(bookingCode, phone) {
  const { data, error } = await supabase.rpc('track_booking_timeline', { p_booking_code: bookingCode, p_phone: phone });
  if (error) throw error;
  return data || [];
}

export async function fetchMyBookings() {
  const { data, error } = await supabase
    .from('bookings')
    .select(`
      id, booking_code, scheduled_date, status, stage, final_amount, collection_type, created_at,
      booking_items ( name_snapshot )
    `)
    .order('created_at', { ascending: false });
  if (error) throw error;
  return data || [];
}

export async function fetchMyBookingDetail(bookingId) {
  const { data: booking, error } = await supabase
    .from('bookings')
    .select(`
      *, booking_items ( name_snapshot, price_snapshot ),
      collection_addresses ( address_line, city, state, pincode, landmark )
    `)
    .eq('id', bookingId)
    .maybeSingle();
  if (error) throw error;
  if (!booking) return null;

  const { data: history } = await supabase
    .from('booking_status_history')
    .select('new_status, created_at')
    .eq('booking_id', bookingId)
    .order('created_at', { ascending: true });

  return { ...booking, history: history || [] };
}
